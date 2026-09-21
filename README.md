# Microsoft 365 User Inventory

A cloud automation project that retrieves Microsoft 365 users through Microsoft Graph and exports the inventory to a CSV file.

## Project Goal

The goal of this project is to automate Microsoft 365 user inventory collection using Python and Microsoft Graph.

The application uses app-only authentication through Microsoft Entra ID.

## Architecture

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
Microsoft 365 Users
        |
        v
CSV Export

## Technologies

- Python 3.12
- Microsoft Graph
- Microsoft Entra ID
- Azure Identity
- Microsoft Graph SDK
- python-dotenv
- Git
- GitHub

## Current Features

- App-only authentication
- Microsoft Graph integration
- Microsoft 365 user retrieval
- CSV export
- Environment variable configuration
- Credentials excluded from source control

## Project Structure

m365-user-inventory/
|
|-- src/
|   |-- main.py
|
|-- .env.example
|-- .gitignore
|-- requirements.txt
|-- README.md

## Environment Variables

Create a `.env` file based on `.env.example`.

TENANT_ID=
CLIENT_ID=
CLIENT_SECRET=

Never commit the `.env` file.

## Installation

Create a virtual environment:

python -m venv .venv

Activate it on Windows:

.\.venv\Scripts\Activate.ps1

Install dependencies:

pip install -r requirements.txt

## Running

python src/main.py

The application creates:

output/m365_users.csv

## Security

The project follows basic security practices:

- Secrets are stored in environment variables
- `.env` is excluded by `.gitignore`
- Microsoft Graph uses application permissions
- The application currently uses read-only access

## Roadmap

- Export additional user attributes
- Add pagination
- Add logging
- Improve error handling
- Add automated tests
- Add GitHub Actions
- Deploy with Azure Functions
- Replace client secret with managed authentication

## Status

Version 1 - Functional
