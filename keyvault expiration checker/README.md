# Key Vault Secret Expiration Checker — Azure Function App

Timer-triggered Python Function App (v2 programming model). Runs every 24 hours,
lists all secrets in a Key Vault, builds an HTML table (green = expires in more
than the threshold, red = expires within the threshold, gray = no expiration set),
and emails the table via Azure Communication Services (ACS) Email — only when
at least one secret is within the threshold. Default threshold: 30 days.

## Files
- `function_app.py` — the function (Python v2 decorator model)
- `requirements.txt` — pinned minimum package versions
- `host.json` — runtime config, extension bundle
- `local.settings.json.example` — copy to `local.settings.json` for local runs, do not commit

## Required app settings (Function App → Configuration)
| Setting | Purpose |
|---|---|
| `KEY_VAULT_URL` | e.g. `https://my-vault.vault.azure.net/` |
| `ACS_ENDPOINT` | e.g. `https://my-acs-resource.communication.azure.com` |
| `SENDER_ADDRESS` | Verified sender address from the ACS Email domain |
| `DISTRO_RECIPIENTS` | Comma-separated recipient list |
| `EXPIRY_THRESHOLD_DAYS` | Optional, default `30` |
| `TIMER_SCHEDULE` | NCRONTAB expression, default `0 0 0 * * *` (daily, 00:00 UTC) |
| `FUNCTIONS_WORKER_RUNTIME` | `python` |

No connection strings or secrets are stored in app settings. Auth is via
system-assigned managed identity (`DefaultAzureCredential`) for both Key Vault
and ACS Email.

## Required role assignments (Azure RBAC)
Enable a system-assigned managed identity on the Function App, then assign:

1. On the Key Vault (must be using Azure RBAC authorization, not legacy access
   policies): **Key Vault Secrets User** — grants `get`/`list` on secrets, no
   write access.
2. On the ACS resource: **Communication and Email Service Owner**, or a custom
   role scoped to `Microsoft.Communication/EmailServices/Send/action` for
   least privilege.

## Deploy
```bash
func azure functionapp publish <function-app-name>
```

## Notes / assumptions
- No parameters were given for hosting plan, region, or naming — none of
  those affect the code, only the `az` deployment commands, which aren't
  included here since no target environment was specified.
- Disabled secrets are excluded from the report.
- Secrets with no `expires_on` set are listed but flagged "No expiration set"
  and excluded from the 30-day trigger logic (Key Vault does not require an
  expiration date on secrets).
- Timer trigger relies on `AzureWebJobsStorage` for the singleton lock across
  scaled-out instances — this is provisioned automatically with the Function App.

## Source currency
All package versions and code patterns below were verified against Microsoft
Learn / PyPI on 2026-07-13:
- Timer trigger reference — updated 2026-06-15
- azure-keyvault-secrets 4.11.0 — doc updated 2026-04-17
- azure-communication-email 1.1.0 — doc updated 2025-10-20 (9 months old, no newer major version found)
- azure-identity DefaultAzureCredential — current per Microsoft Learn (2026-07-13)
- Key Vault Secrets User / Communication and Email Service Owner roles — per Microsoft Learn RBAC guide
