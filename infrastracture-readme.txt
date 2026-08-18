Naming convention:
App-Resource-environment  
(no dashes if naming is not allowed)



### TL/DR

Migrating 21 VM-hosted services to Azure across 8 phases (Front End, App Config, Storage, Tasks,
API's, SQL, Redis, Function App). Only Phase 1 (frontend, cmstx) is underway, and only in sandbox -
AKS infra, runtime config, and pipelines all work end-to-end there. Still missing: the frontend's
own image build/push pipeline, and dev/uat/staging/prod haven't been touched. Every other phase
(App Config beyond the hub, Storage, Tasks, API's, SQL, Redis, Function App) hasn't started.

### Progress

Overall VM -> Azure migration, 21 services total. Phases below match the project phases/timeline doc
("project phases and timeline.docx") and its stated phase order: Front End, App Config, Storage, Tasks,
API's, SQL, Redis, Function App. Only Phase 1 (Front End) has any real work done so far, and only in the
sandbox environment.

Phase 1 - Front End [IN PROGRESS - sandbox only]
  (docx: containerize frontend + pipelines, gateway update, GitHub Actions automation,
  phased Dev>QA>Stage>Prod rollout - est. 2-4 weeks)
  Complete:
  - Hub foundation - ACR, App Configuration, Key Vault, Front Door, hub VNet
  - Sandbox spoke networking - VNet + VNet RG split, hub<->spoke peering, route table, subnets
  - Sandbox AKS platform - cluster, workload identity/OIDC, private DNS zone linked to hub,
    kubelet AcrPull/AppConfig grants, cluster admin RBAC grants
  - Runtime config + app deploy - App Config provider CR, Helm chart (runtime-config mount, amd64
    nodeSelector, hub ACR image path), Redis/Blob Cache/Blob Perm storage
  - Edge/traffic routing - Private Link Service, Front Door origin/origin group/route
  - Idempotent deploy pipeline (graduated fail-fast/continue policy) + best-effort teardown pipeline
  To do:
  - Image build/push automation - frontend repo (Dockerfile, nginx.conf, GitHub Actions build pipeline)
    doesn't exist in this workspace yet; images pushed to hub ACR manually today
  - Gateway update (docx sub-task) - not yet addressed
  - Remaining environments - dev, uat, staging, prod not yet deployed, only sandbox is real
  - AFD custom domain DNS validation - stays manual by design for now, not automated
  - Confirm hubAfdEndpointName (sandman-afdep) against the actual resource - currently inferred only

Phase 2 - App Config [PARTIALLY DONE - hub-level only]
  (docx: create App Config, move config data into Key Vault and App Config)
  Complete:
  - Hub App Configuration (sandman-Appconfig-hub) and Key Vault (sandman-kv-hub) exist, centralized
    and shared across all environments
  - Frontend runtime config migrated (App Config -> AzureAppConfigurationProvider CR -> ConfigMap -> pod)
  To do:
  - Migrate backend API config.ini data into App Configuration/Key Vault - not started, blocked on
    API containerization (Phase 5)

Phase 3 - Storage [NOT STARTED]
  (docx: move off Azure VM fileshares to individual per-environment fileshares, migrate data - est. 2-4 weeks)
  To do:
  - everything - not started

Phase 4 - Tasks [NOT STARTED]
  (docx: move Python scripts/tasks - data cache, bol verification, etc, 8 tasks total - into containers
  or cron jobs - est. 2-4 weeks)
  To do:
  - everything - not started

Phase 5 - API's [NOT STARTED]
  (docx: containerize API's, build automation pipeline, address memory/plain-text security/odd caching/
  django-runserver-in-prod concerns - est. 8-12 weeks; flagged in the docx as probably the largest single
  piece - needs to be built out and deployable before the project can move on from Dev)
  To do:
  - everything - not started

Phase 6 - SQL [NOT STARTED]
  (docx: move SQL VM off the prod subscription, create new VMs or Azure SQL, install SQL, set up DBs,
  work out security - est. 6-8 weeks; flagged in the docx as needing significant planning/testing to
  find the best approach)
  To do:
  - everything - not started

Phase 7 - Redis [NOT STARTED beyond the frontend's own instance]
  (docx: move Redis from a single instance to multiple instances, decide AKS-contained vs. individual
  instances - est. 3-5 weeks)
  Complete:
  - sandman-redis-{env} already exists per environment for the frontend's own use (Phase 1) - this is
    separate from the broader multi-instance Redis migration this phase covers
  To do:
  - everything else - not started

Phase 8 - Function App [NOT STARTED]
  (docx: move Function Apps off the prod subscription to new environments, decide containers vs.
  keep as Function Apps - est. 4 weeks)
  To do:
  - everything - not started

Out of scope for now (per CLAUDE.md): UAT and higher environment deployments beyond sandbox for Phase 1;
the remaining 19 services beyond what's listed above aren't separately tracked yet.


### resources

#Hub
sub: sandman-hub (main subscription used to store all the shared resources)
RG:sandman-rg-hub (house shared resources for all environments)
ACR: SandmanACRhub (stores Container images to be used to deploy containers)
AFD: Sandman-AFD (Azure Front door, to be used to direct incoming sandman traffic to needed environments)
AppConfig: Sandman-AppConfig-hub (used to store all the Config data for the API's and Frontend)
App agent VM: Sm-pipeagent (used as the Devops Pipeline Agent)
GH runner VM: sndm-vm-ghrun (GitHub Actions self-hosted runner, lives in the hub VNet, non-domain-joined
    Linux, points straight at Azure DNS)
MI: Sandman-MI-ghrunner (UAMI attached to sndm-vm-ghrun - intended for ACR push + AKS deploy auth,
    replacing the SP+secret used today)
    objectID: 86e497ba-fd2f-4026-bb5e-3e7a9d39d9f1
    clientID: 91c2aff7-a238-4827-8789-5fa99df1850d
KeyVault: sandman-kv-hub (centralized secret store, shared across all environments - no per-environment Key Vault)
AFD Endpoint: sandman-afdep (shared Front Door endpoint used by every environment's route - inferred from hostname, not independently confirmed)
Service Connection: sandman-sc-hub (Devops service connection used for hub-scoped deployment steps)
VNet: sandman-vnet-hub (hub networking, peered to every spoke VNet)


#Spoke (repeated per environment: sandbox, dev, uat, staging, prod)
sub: sandman-{env} (dedicated subscription per environment)
RG: sandman-rg-{env} (houses environment workload resources - AKS, Redis, PLS, storage)
RG: sandman-rg-{env}vnet (permanent networking RG - VNet, subnets, route table - kept separate so the teardown pipeline's RG delete never touches networking)
VNet: sandman-vnet-{env} (peered bidirectionally with sandman-vnet-hub)
Subnet: sandman-snet-aks (AKS node subnet)
Subnet: sandman-snet-pe (private endpoint subnet)
Route Table: sandman-rt-{env}
AKS: sandman-aks-{env} (private cluster, AMD64 node pools, Azure CNI, workload identity/OIDC, namespace sandman)
UAMI: sandman-uami-aks-{env} (AKS user-assigned managed identity)
Redis: sandman-redis-{env}
PLS: sandman-pls-frontend-{env} (Private Link Service exposing the internal LB to Front Door)
AFD Origin Group/Origin: sandman-{env} (shares one name for both)
AFD Route: sandman-{env}-route
AFD Custom Domain: sandman-{env}.chalksolutions.com (DNS-validated manually, not by the pipeline)
Service Connection: sandman-sc-{env}


### Layout

Traffic: Internet -> Front Door (hub) -> Private Link -> Internal LB :30440 (spoke) -> AKS nginx pod :80
  (no public ingress to AKS - everything enters through Front Door)

Config: App Configuration (hub) -> AzureAppConfigurationProvider CR (spoke) -> ConfigMap -> mounted into pod at runtime
  (no build-time env files - config is fetched at runtime, not baked into the image)

Images: build -> push to hub ACR -> AKS (spoke) pulls via AcrPull granted to kubelet identity
  (one shared ACR for all environments, not one per environment)

Networking: each spoke VNet peered bidirectionally to the hub VNet; AKS/ACR private DNS zones linked to
  the hub VNet too, so the hub-based pipeline agent can resolve spoke resources


### Pipeline

azure-pipelines-environment.yml (deploy/update one environment, idempotent - skips what already exists):
  networking  -> resource group, VNet RG, route table, VNet, peer to hub, link ACR DNS zone (hub)
  storage     -> Blob Cache, Blob Perm (own RSV RG), Redis
  AKS         -> deploy cluster, link its private DNS zone to hub, grant UAMI/AcrPull/AppConfig roles + RBAC admins,
                 grant GitHub runner MI AKS access
  app         -> install App Config provider, deploy provider CR, deploy frontend Helm chart, wait for LB IP
  edge        -> create PLS, grant hub read on PLS, configure Front Door origin, create Front Door route
  finish      -> post-deploy reminders + a config summary step (reports anything needing manual follow-up)

azure-pipelines-teardown.yml (tear down one environment - requires typing the environment name to confirm,
best-effort: continues past failures instead of stopping on the first one):
  delete Front Door route -> origin -> origin group
  delete frontend PLS's private endpoint connection -> the PLS itself
  delete the main resource group only (VNet RG is permanent, never touched)
  verify   -> checks hub + spoke state afterward and prints anything left over 

### Permissions

Accounts:
sandman-sc-hub      - Devops service connection SP, hub subscription
sandman-sc-{env}    - Devops service connection SP, one per spoke subscription
AKS kubelet identity - AKS's own identity, used to pull images / read config (per environment)
AKS UAMI: sandman-uami-aks-{env} - AKS cluster's user-assigned identity (per environment)
CSOL_Server_Admin   - AD group, human access to AKS
Sm-pipeagent        - self-hosted Devops pipeline agent VM, lives in the hub VNet
Sandman-MI-ghrunner - UAMI attached to the GitHub Actions self-hosted runner VM (sndm-vm-ghrun,
                      /subscriptions/c290fb32-8a22-4aeb-9147-d6d4e54071dd/resourceGroups/sandman-rg-hub/providers/Microsoft.Compute/virtualMachines/sndm-vm-ghrun)
                      objectID 86e497ba-fd2f-4026-bb5e-3e7a9d39d9f1, clientID 91c2aff7-a238-4827-8789-5fa99df1850d
                      Now assigned to the runner VM. AKS access (Cluster User Role + RBAC Writer,
                      per environment) is automated in azure-pipelines-environment.yml (see below) -
                      still needs AcrPush on the hub ACR (once), which isn't automated anywhere yet.
                      Runner still auths to ACR via an SP+secret today (client secret in a GitHub
                      Actions variable/secret) - MI is the planned replacement, not yet cut over.

Manual, one-time bootstrap (not done by the pipeline - see CLAUDE.md for exact commands):
sandman-sc-hub    -> User Access Administrator on sandman-rg-hub, ABAC-constrained to only
                     assign AcrPull / App Configuration Data Reader (hub-side, once ever)
sandman-sc-hub    -> Private DNS Zone Contributor on sandman-vnet-{env} (spoke-side, once per new environment)
sandman-sc-{env}  -> Private DNS Zone Contributor on sandman-vnet-hub (hub-side, once per new environment)

Automated every pipeline run:
AKS UAMI              -> Network Contributor on the AKS subnet
sandman-sc-{env} SP    -> Azure Kubernetes Service RBAC Cluster Admin on sandman-aks-{env}
CSOL_Server_Admin      -> Azure Kubernetes Service RBAC Cluster Admin on sandman-aks-{env}
AKS kubelet identity   -> AcrPull on the hub ACR
AKS kubelet identity   -> App Configuration Data Reader on the hub App Configuration
sandman-sc-hub SP      -> Reader on the frontend PLS (sandman-pls-frontend-{env}) - needed because
                          Front Door origin creation runs under the hub connection but the PLS lives in the spoke
Sandman-MI-ghrunner    -> Azure Kubernetes Service Cluster User Role on sandman-aks-{env}
Sandman-MI-ghrunner    -> Azure Kubernetes Service RBAC Writer on sandman-aks-{env}