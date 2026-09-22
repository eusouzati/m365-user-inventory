# Microsoft 365 User Inventory

A cloud automation project that retrieves Microsoft 365 users through Microsoft Graph and exports an extended inventory to a CSV file.

## Project Goal

Automate Microsoft 365 user inventory collection using Python, Microsoft Graph and app-only authentication through Microsoft Entra ID.

## Architecture

```text
Microsoft Entra ID
        |
        v
App Registration
        |
        v
Microsoft Graph API
        |
        v
Python Automation
        |
        v
CSV Export
```

## Technologies

- Python 3.12
- Microsoft Graph SDK
- Microsoft Entra ID
- Azure Identity
- PowerShell
- Git and GitHub

## Version 5 Features

- App-only authentication with client credentials
- Microsoft 365 user retrieval
- Automatic pagination for tenants with more than 100 users
- Export of display name, UPN, email, department, job title and account status
- CSV encoded for Excel and separated with semicolons
- Friendly error when the CSV file is open in Excel
- Microsoft Graph and unexpected error handling
- Execution log with timestamps, page totals and duration
- Credential cleanup even when an error occurs
- Idempotent PowerShell script for lab user provisioning
- Automated unit tests for pagination, CSV export and logging
- GitHub Actions validation on pushes and pull requests
- Scheduled Azure Function execution at 08:00 Brasilia time (11:00 UTC)
- Azure Functions Flex Consumption hosting in Brazil South
- Passwordless Microsoft Graph and Blob Storage authentication
- User-assigned managed identity with least-privilege access
- Private Blob Storage CSV output
- Application Insights execution monitoring
- Credentials, generated output and backup files excluded from source control

## Project Structure

```text
m365-user-inventory/
|-- function_app.py
|-- host.json
|-- local.settings.example.json
|-- scripts/
|   |-- Deploy-AzureV5.ps1
|   |-- New-LabUsers.ps1
|-- src/
|   |-- main.py
|-- tests/
|   |-- test_main.py
|-- .env.example
|-- .gitignore
|-- README.md
|-- requirements.txt
```

## Prerequisites

- Python 3.12
- Microsoft Entra ID app registration
- Microsoft Graph application permission `User.Read.All` with admin consent
- Microsoft Graph PowerShell permissions when using the lab provisioning script

## Environment Variables

Create a `.env` file based on `.env.example`:

```text
TENANT_ID=
CLIENT_ID=
CLIENT_SECRET=
```

Never commit the `.env` file.

## Installation

Create and activate a virtual environment on Windows:

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
```

Install dependencies:

```powershell
python -m pip install -r requirements.txt
```

## Running the Inventory

Close the CSV file in Excel before running:

```powershell
python src\main.py
```

The application creates:

```text
output/m365_users.csv
logs/m365_inventory.log
```

## Azure Deployment

The Azure deployment uses a Flex Consumption Function App in `brazilsouth`.
It runs every day at 11:00 UTC, which corresponds to 08:00 in Brasilia.

The cloud function uses a user-assigned managed identity. No tenant client
secret or storage account key is deployed with the application.

Required tools:

- Azure CLI
- Azure Functions Core Tools 4
- Python 3.11 or 3.12 for development and tests
- A tenant administrator able to grant Microsoft Graph `User.Read.All`

Deploy from the repository root:

```powershell
.\scripts\Deploy-AzureV5.ps1
```

The deployment script displays all resource names and requires typing
`DEPLOY` before it creates Azure resources. It creates:

- Resource group `rg-m365-user-inventory`
- Flex Consumption Function App
- Standard LRS Storage Account with shared-key access disabled
- Private `inventory` blob container
- User-assigned managed identity
- Application Insights instance

The latest CSV is stored as:

```text
inventory/m365_users.csv
```

## Creating Lab Users

Connect to Microsoft Graph with the required permissions and run:

```powershell
.\scripts\New-LabUsers.ps1
```

Existing users are skipped, so the script can be executed more than once without creating duplicates.


## Running the Tests

```powershell
python -m unittest discover -s tests -v
```

The GitHub Actions workflow runs the syntax check and automated tests on every push to `main` and on every pull request.

## Security

- Secrets are stored only in `.env`
- `.env`, `.venv`, generated CSV files, logs and backups are ignored by Git
- The inventory application uses read-only Microsoft Graph access
- Azure uses managed identity instead of a client secret
- The storage account has public and shared-key access disabled
- The cloud identity receives only `User.Read.All` and storage data access
- The initial lab password is entered securely at runtime

## Roadmap

- Add historical CSV retention as an optional feature
- Add failure notifications
- Add infrastructure-as-code validation

## Status

Version 5 - Azure deployment ready


