# Microsoft 365 User Inventory

A reusable cloud automation project that retrieves Microsoft 365 users through
Microsoft Graph and exports an inventory to CSV locally or to private Azure
Blob Storage.

## Main features

- Microsoft Graph app-only authentication
- Automatic pagination for large tenants
- User name, UPN, email, department, job title and account status export
- Excel-compatible CSV output
- Local execution with credentials stored in `.env`
- Scheduled Azure Functions execution
- Passwordless cloud authentication with managed identity
- Private Blob Storage output
- Application Insights monitoring
- Idempotent one-command Azure deployment
- Automated tests for Python 3.11 and 3.12

## Cloud architecture

```text
Azure Functions timer
        |
        v
User-assigned managed identity
        |
        +----> Microsoft Graph (User.Read.All)
        |
        +----> Private Azure Blob Storage
        |
        `----> Application Insights
```

No Microsoft 365 client secret or storage key is deployed to Azure.

## Project structure

```text
m365-user-inventory/
|-- docs/
|   `-- DEPLOYMENT.md
|-- scripts/
|   |-- Deploy.ps1
|   |-- Deploy-AzureV5.ps1
|   `-- New-LabUsers.ps1
|-- src/
|   `-- main.py
|-- tests/
|   `-- test_main.py
|-- .env.example
|-- .funcignore
|-- .gitignore
|-- function_app.py
|-- host.json
|-- local.settings.example.json
|-- requirements.txt
`-- README.md
```

## Quick Azure deployment

Prerequisites:

- Azure CLI
- Azure Functions Core Tools 4
- Python 3.11 or 3.12
- PowerShell 5.1 or PowerShell 7
- Azure permissions to create resources and role assignments
- Microsoft Entra administrator permission to grant Graph `User.Read.All`

Clone and configure:

```powershell
git clone https://github.com/eusouzati/m365-user-inventory.git
cd m365-user-inventory
Copy-Item .env.example .env
```

Fill in `.env`. The minimum cloud configuration is:

```dotenv
AZURE_TENANT_ID=
AZURE_SUBSCRIPTION_ID=
```

Deploy with one command:

```powershell
.\scripts\Deploy.ps1
```

The script validates the configuration and creates or updates the complete
Azure environment. Resource names can be provided in `.env` or generated
automatically.

See [the complete deployment guide](docs/DEPLOYMENT.md) for permissions,
variables, validation and troubleshooting.

## Local execution

Create `.env` from `.env.example` and configure:

```dotenv
M365_TENANT_ID=
M365_CLIENT_ID=
M365_CLIENT_SECRET=
```

The app registration requires Microsoft Graph application permission
`User.Read.All` with admin consent.

Create the environment and install dependencies:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install -r requirements.txt
```

Run the inventory:

```powershell
python src\main.py
```

Local output:

```text
output/m365_users.csv
logs/m365_inventory.log
```

## Cloud schedule and output

The default schedule is daily at 11:00 UTC, equivalent to 08:00 in Brasilia
while UTC-3 applies.

The latest CSV is stored in the private container as:

```text
inventory/m365_users.csv
```

Schedule, container and blob name can all be changed in `.env`.

## Tests

```powershell
python -m unittest discover -s tests -v
```

GitHub Actions validates Python 3.11 and 3.12 on pushes to `main` and pull
requests.

## Lab users

The optional lab provisioning script is idempotent:

```powershell
.\scripts\New-LabUsers.ps1
```

Existing users are skipped.

## Security

- `.env`, generated CSV files, logs and local settings are ignored by Git.
- `.env` is excluded from the Azure Functions deployment package.
- Azure uses managed identity instead of client secrets.
- The storage container is private and shared-key access is disabled.
- Microsoft Graph access is read-only.
- The deployment grants only the RBAC roles needed by the application and the
  signed-in operator.

## Version

Version 1.2.0 - portable one-command deployment configuration.
