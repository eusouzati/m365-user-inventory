# Deployment Guide

This guide deploys Microsoft 365 User Inventory to an Azure subscription that
belongs to the same Microsoft Entra tenant being inventoried.

## What the deployment creates

- Azure Functions Flex Consumption app
- Standard LRS storage account
- Private Blob Storage container
- User-assigned managed identity
- Application Insights monitoring
- Microsoft Graph `User.Read.All` application permission
- Required Azure RBAC assignments

The deployment is idempotent. Running it again updates the existing resources
instead of intentionally creating duplicates.

## Prerequisites

Install these tools before deployment:

- Git
- Azure CLI
- Azure Functions Core Tools 4
- Python 3.11 or 3.12
- PowerShell 5.1 or PowerShell 7

The deployment account needs:

- Access to the target Azure subscription
- Permission to create resource groups and Azure resources
- Permission to create Azure role assignments, such as Owner or User Access
  Administrator
- A Microsoft Entra administrative role allowed to grant Microsoft Graph
  application permissions

The Azure subscription and Microsoft 365 tenant must use the same Microsoft
Entra tenant. This is required because the Azure managed identity receives the
Microsoft Graph permission.

## 1. Clone the repository

```powershell
git clone https://github.com/eusouzati/m365-user-inventory.git
cd m365-user-inventory
```

## 2. Create the environment file

```powershell
Copy-Item .env.example .env
```

Open `.env` and configure at least:

```dotenv
AZURE_TENANT_ID=00000000-0000-0000-0000-000000000000
AZURE_SUBSCRIPTION_ID=00000000-0000-0000-0000-000000000000
```

The local Microsoft 365 variables are only needed when running
`python src/main.py` with an app registration:

```dotenv
M365_TENANT_ID=
M365_CLIENT_ID=
M365_CLIENT_SECRET=
```

For Azure deployment, the application uses managed identity. The local client
secret is never copied to Azure.

## 3. Deploy with one command

```powershell
.\scripts\Deploy.ps1
```

Review the plan and type `DEPLOY`. To use the same script in an approved
non-interactive pipeline:

```powershell
.\scripts\Deploy.ps1 -Yes
```

The script reads `.env`, validates the target subscription, creates or updates
the resources, grants permissions, configures the Function App and publishes
the code.

## Environment variables

| Variable | Required | Purpose |
| --- | --- | --- |
| `AZURE_TENANT_ID` | Yes | Tenant that owns the Azure subscription |
| `AZURE_SUBSCRIPTION_ID` | Yes | Deployment subscription |
| `AZURE_LOCATION` | No | Flex Consumption region |
| `AZURE_RESOURCE_GROUP` | No | Resource group name |
| `AZURE_STORAGE_ACCOUNT` | No | Globally unique storage name; generated when blank |
| `AZURE_FUNCTION_APP` | No | Globally unique Function App name; generated when blank |
| `AZURE_MANAGED_IDENTITY_NAME` | No | User-assigned identity name |
| `INVENTORY_CONTAINER` | No | Private Blob container |
| `INVENTORY_BLOB_NAME` | No | CSV object name |
| `INVENTORY_SCHEDULE` | No | Six-field NCRONTAB schedule in UTC |
| `M365_TENANT_ID` | Local only | Tenant used by local client credentials |
| `M365_CLIENT_ID` | Local only | App registration client ID |
| `M365_CLIENT_SECRET` | Local only | App registration secret |

If `AZURE_TENANT_ID` is empty, the script uses `M365_TENANT_ID`.

## Default schedule

The default value is:

```text
0 0 11 * * *
```

This runs daily at 11:00 UTC, equivalent to 08:00 in Brasilia while the UTC-3
offset applies. Azure Functions timer schedules use UTC unless app-specific
time zone configuration is supported and explicitly enabled.

## Validate the deployment

List the deployed functions:

```powershell
az functionapp function list `
    --resource-group <resource-group> `
    --name <function-app> `
    --output table
```

After the timer runs, list the private CSV blob:

```powershell
az storage blob list `
    --account-name <storage-account> `
    --container-name inventory `
    --auth-mode login `
    --output table
```

## Security model

- `.env` is excluded from Git and from the Function deployment package.
- The Function App uses a user-assigned managed identity.
- No storage key or Microsoft 365 client secret is deployed.
- Blob public access and storage shared-key access are disabled.
- Microsoft Graph access is read-only through `User.Read.All`.
- The signed-in deployment user receives read-only access to the inventory
  container.

## Common errors

### Tenant or subscription not found

Confirm `AZURE_TENANT_ID` and `AZURE_SUBSCRIPTION_ID`, then run:

```powershell
az login --tenant <tenant-id>
az account set --subscription <subscription-id>
```

### Cannot create role assignments

The deployment user needs Owner or User Access Administrator at the applicable
scope.

### Cannot grant User.Read.All

Run the deployment with a tenant administrator who is authorized to grant
Microsoft Graph application permissions.

### Function App name or storage name is unavailable

Set unique values for `AZURE_FUNCTION_APP` and `AZURE_STORAGE_ACCOUNT` in
`.env`, then run the same deployment command again.

### Region does not support Flex Consumption

Choose a supported value for `AZURE_LOCATION`. Available locations can be
listed with:

```powershell
az functionapp list-flexconsumption-locations --output table
```
