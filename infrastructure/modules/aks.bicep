param environment string
param location string = resourceGroup().location
param aksSubnetId string
param acrId string
param podCidr string

// System node pool sizing
param systemNodeCount int
param systemNodeMinCount int
param systemNodeMaxCount int
param systemNodeVmSize string

// User node pool sizing
param userNodeVmSize string
param userNodePools array

// Kubernetes
param kubernetesVersion string

var aksName = 'sandman-aks-${environment}'
var dnsPrefix = 'sandman-aks-${environment}'
var uamiName = 'sandman-uami-aks-${environment}'
var logAnalyticsName = 'sandman-la-${environment}'
var serviceCidr = '192.168.0.0/24'
var dnsServiceIP = '192.168.0.10'

var tags = {
  app: 'sandman'
  env: environment
}

// Log Analytics Workspace
resource logAnalyticsWorkspace 'Microsoft.OperationalInsights/workspaces@2023-09-01' = {
  name: logAnalyticsName
  location: location
  tags: tags
  properties: {
    sku: {
      name: 'PerGB2018'
    }
    retentionInDays: 30
    publicNetworkAccessForIngestion: 'Enabled'
    publicNetworkAccessForQuery: 'Enabled'
  }
}

// User Assigned Managed Identity for AKS
resource aksUami 'Microsoft.ManagedIdentity/userAssignedIdentities@2023-01-31' = {
  name: uamiName
  location: location
  tags: tags
}

// ACR Pull Role Assignment
resource acrPullRoleAssignment 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  name: guid(acrId, aksUami.id, 'acrpull')
  scope: resourceGroup()
  properties: {
    roleDefinitionId: subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '7f951dda-4ed3-4680-a7ca-43fe172d538d')
    principalId: aksUami.properties.principalId
    principalType: 'ServicePrincipal'
  }
}

// AKS Cluster
resource aksCluster 'Microsoft.ContainerService/managedClusters@2025-10-02-preview' = {
  name: aksName
  location: location
  tags: tags
  sku: {
    name: 'Base'
    tier: 'Standard'
  }
  identity: {
    type: 'UserAssigned'
    userAssignedIdentities: {
      '${aksUami.id}': {}
    }
  }
  properties: {
    kubernetesVersion: kubernetesVersion
    dnsPrefix: dnsPrefix
    enableRBAC: true
    disableLocalAccounts: true
    supportPlan: 'KubernetesOfficial'

    apiServerAccessProfile: {
      enablePrivateCluster: true
      privateDNSZone: 'system'
      enablePrivateClusterPublicFQDN: false
    }

    agentPoolProfiles: concat(
      [
        {
          name: 'agentpool'
          mode: 'System'
          count: systemNodeCount
          minCount: systemNodeMinCount
          maxCount: systemNodeMaxCount
          enableAutoScaling: true
          vmSize: systemNodeVmSize
          osDiskSizeGB: 128
          osDiskType: 'Managed'
          osType: 'Linux'
          osSKU: 'Ubuntu'
          vnetSubnetID: aksSubnetId
          maxPods: 40
          type: 'VirtualMachineScaleSets'
          availabilityZones: [ '1', '2' ]
          scaleDownMode: 'Delete'
          enableNodePublicIP: false
          nodeTaints: [ 'CriticalAddonsOnly=true:NoSchedule' ]
          upgradeStrategy: 'Rolling'
          upgradeSettings: {
            maxSurge: '10%'
            maxUnavailable: '0'
          }
          securityProfile: {
            sshAccess: 'LocalUser'
            enableVTPM: false
            enableSecureBoot: false
          }
        }
      ],
      map(userNodePools, pool => {
        name: pool.name
        mode: 'User'
        count: pool.count
        minCount: pool.minCount
        maxCount: pool.maxCount
        enableAutoScaling: true
        vmSize: userNodeVmSize
        osDiskSizeGB: 128
        osDiskType: 'Managed'
        osType: 'Linux'
        osSKU: 'Ubuntu'
        vnetSubnetID: aksSubnetId
        maxPods: 40
        type: 'VirtualMachineScaleSets'
        availabilityZones: pool.availabilityZones
        scaleDownMode: 'Delete'
        enableNodePublicIP: false
        upgradeStrategy: 'Rolling'
        upgradeSettings: {
          maxSurge: '1'
          maxUnavailable: '0'
        }
        securityProfile: {
          sshAccess: 'LocalUser'
          enableVTPM: false
          enableSecureBoot: false
        }
      })
    )

    networkProfile: {
      networkPlugin: 'azure'
      networkPluginMode: 'overlay'
      networkPolicy: 'cilium'
      networkDataplane: 'cilium'
      loadBalancerSku: 'standard'
      podCidr: podCidr
      serviceCidr: serviceCidr
      dnsServiceIP: dnsServiceIP
      outboundType: 'loadBalancer'
      ipFamilies: [ 'IPv4' ]
    }

    aadProfile: {
      managed: true
      enableAzureRBAC: true
      tenantID: tenant().tenantId
    }

    securityProfile: {
      workloadIdentity: {
        enabled: true
      }
    }

    oidcIssuerProfile: {
      enabled: true
    }

    addonProfiles: {
      azurepolicy: {
        enabled: true
      }
      omsAgent: {
        enabled: true
        config: {
          logAnalyticsWorkspaceResourceID: logAnalyticsWorkspace.id
          useAADAuth: 'true'
        }
      }
    }

    autoScalerProfile: {
      'scale-down-delay-after-add': '10m'
      'scale-down-unneeded-time': '10m'
      'scale-down-utilization-threshold': '0.5'
      'scan-interval': '10s'
      'skip-nodes-with-system-pods': 'true'
    }

    autoUpgradeProfile: {
      upgradeChannel: 'none'
      nodeOSUpgradeChannel: 'None'
    }

    storageProfile: {
      diskCSIDriver: {
        enabled: true
      }
      fileCSIDriver: {
        enabled: true
      }
      snapshotController: {
        enabled: true
      }
    }
  }
}

output aksId string = aksCluster.id
output aksName string = aksCluster.name
output aksFqdn string = aksCluster.properties.privateFQDN
output oidcIssuerUrl string = aksCluster.properties.oidcIssuerProfile.issuerURL
output aksUamiClientId string = aksUami.properties.clientId
output aksUamiPrincipalId string = aksUami.properties.principalId
output logAnalyticsWorkspaceId string = logAnalyticsWorkspace.id
