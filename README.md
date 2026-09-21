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

## Version 2 Features

- App-only authentication with client credentials
- Microsoft 365 user retrieval
- Export of display name, UPN, email, department, job title and account status
- CSV encoded for Excel and separated with semicolons
- Friendly error when the CSV file is open in Excel
- Credential cleanup even when an error occurs
- Idempotent PowerShell script for lab user provisioning
- Credentials, generated output and backup files excluded from source control

## Project Structure

```text
m365-user-inventory/
|-- scripts/
|   |-- New-LabUsers.ps1
|-- src/
|   |-- main.py
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
```

## Creating Lab Users

Connect to Microsoft Graph with the required permissions and run:

```powershell
.\scripts\New-LabUsers.ps1
```

Existing users are skipped, so the script can be executed more than once without creating duplicates.

## Security

- Secrets are stored only in `.env`
- `.env`, `.venv`, generated CSV files and backups are ignored by Git
- The inventory application uses read-only Microsoft Graph access
- The initial lab password is entered securely at runtime

## Roadmap

- Add pagination for large tenants
- Add structured logging and execution timestamps
- Improve Microsoft Graph error handling
- Add automated tests and GitHub Actions
- Replace the client secret with managed authentication when deployed to Azure

## Status

Version 2 - Functional
