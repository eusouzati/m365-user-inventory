[CmdletBinding()]
param(
    [string]$ResourceGroup = "rg-m365-user-inventory",
    [string]$Location = "brazilsouth",
    [string]$ScheduleUtc = "0 0 11 * * *"
)

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

function Assert-LastExitCode {
    param([string]$Message)

    if ($LASTEXITCODE -ne 0) {
        throw $Message
    }
}

function Test-AzCommand {
    param([string[]]$Arguments)

    $previousPreference = $ErrorActionPreference
    try {
        $ErrorActionPreference = "SilentlyContinue"
        & az @Arguments --only-show-errors *> $null
        $commandExitCode = $LASTEXITCODE
    }
    finally {
        $ErrorActionPreference = $previousPreference
    }

    return $commandExitCode -eq 0
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI was not found."
}

if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
    throw "Azure Functions Core Tools was not found."
}

$accountJson = az account show --output json
Assert-LastExitCode "Run az login before this script."
$account = $accountJson | ConvertFrom-Json

$subscriptionId = $account.id
$subscriptionName = $account.name
$signedInUser = $account.user.name

$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash(
    [System.Text.Encoding]::UTF8.GetBytes($subscriptionId)
)
$suffix = (
    [System.BitConverter]::ToString($hashBytes)
).Replace("-", "").Substring(0, 10).ToLowerInvariant()

$StorageAccount = "stm365inv$suffix"
$FunctionApp = "func-m365-inventory-$suffix"
$IdentityName = "id-m365-user-inventory"
$ContainerName = "inventory"
$BlobName = "m365_users.csv"

Write-Host "Azure V5 deployment plan"
Write-Host "User:             $signedInUser"
Write-Host "Subscription:     $subscriptionName"
Write-Host "Resource group:   $ResourceGroup"
Write-Host "Location:         $Location"
Write-Host "Storage account:  $StorageAccount"
Write-Host "Function app:     $FunctionApp"
Write-Host "Schedule:         $ScheduleUtc UTC"
Write-Host ""
Write-Host "This creates Azure resources that can consume free credit."
$confirmation = Read-Host "Type DEPLOY to continue"

if ($confirmation -cne "DEPLOY") {
    Write-Host "Deployment cancelled."
    exit 0
}

foreach ($provider in @(
    "Microsoft.Web",
    "Microsoft.Storage",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity"
)) {
    Write-Host "Registering provider: $provider"
    az provider register --namespace $provider --wait --only-show-errors
    Assert-LastExitCode "Could not register provider: $provider"
}

if (-not (Test-AzCommand @("group", "show", "--name", $ResourceGroup))) {
    Write-Host "Creating resource group..."
    az group create `
        --name $ResourceGroup `
        --location $Location `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the resource group."
}

if (-not (Test-AzCommand @(
    "storage", "account", "show",
    "--resource-group", $ResourceGroup,
    "--name", $StorageAccount
))) {
    Write-Host "Creating storage account..."
    az storage account create `
        --name $StorageAccount `
        --resource-group $ResourceGroup `
        --location $Location `
        --sku Standard_LRS `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the storage account."
}

if (-not (Test-AzCommand @(
    "identity", "show",
    "--resource-group", $ResourceGroup,
    "--name", $IdentityName
))) {
    Write-Host "Creating managed identity..."
    az identity create `
        --name $IdentityName `
        --resource-group $ResourceGroup `
        --location $Location `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the managed identity."
}

$identityJson = az identity show `
    --name $IdentityName `
    --resource-group $ResourceGroup `
    --output json
Assert-LastExitCode "Could not read the managed identity."
$identity = $identityJson | ConvertFrom-Json
$identityId = $identity.id
$principalId = $identity.principalId
$clientId = $identity.clientId

$storageId = az storage account show `
    --resource-group $ResourceGroup `
    --name $StorageAccount `
    --query id `
    --output tsv
Assert-LastExitCode "Could not read the storage account."

$storageRole = az role assignment list `
    --assignee $principalId `
    --scope $storageId `
    --role "Storage Blob Data Owner" `
    --query "[0].id" `
    --output tsv `
    --only-show-errors

if (-not $storageRole) {
    Write-Host "Granting storage access to the managed identity..."
    az role assignment create `
        --assignee-object-id $principalId `
        --assignee-principal-type ServicePrincipal `
        --role "Storage Blob Data Owner" `
        --scope $storageId `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not grant storage access."
}

if (-not (Test-AzCommand @(
    "functionapp", "show",
    "--resource-group", $ResourceGroup,
    "--name", $FunctionApp
))) {
    Write-Host "Creating the Flex Consumption function app..."
    az functionapp create `
        --resource-group $ResourceGroup `
        --name $FunctionApp `
        --flexconsumption-location $Location `
        --runtime python `
        --runtime-version 3.11 `
        --storage-account $StorageAccount `
        --deployment-storage-auth-type UserAssignedIdentity `
        --deployment-storage-auth-value $IdentityName `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the function app. Run the script again after a few minutes."
}

Write-Host "Ensuring the managed identity is attached..."
az functionapp identity assign `
    --resource-group $ResourceGroup `
    --name $FunctionApp `
    --identities $identityId `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not attach the managed identity."

if (-not (Test-AzCommand @(
    "storage", "container-rm", "show",
    "--resource-group", $ResourceGroup,
    "--storage-account", $StorageAccount,
    "--name", $ContainerName
))) {
    Write-Host "Creating the private inventory container..."
    az storage container-rm create `
        --resource-group $ResourceGroup `
        --storage-account $StorageAccount `
        --name $ContainerName `
        --public-access off `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the inventory container."
}

Write-Host "Configuring passwordless application settings..."
az functionapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $FunctionApp `
    --settings `
        "AzureWebJobsStorage__accountName=$StorageAccount" `
        "AzureWebJobsStorage__credential=managedidentity" `
        "AzureWebJobsStorage__clientId=$clientId" `
        "APPLICATIONINSIGHTS_AUTHENTICATION_STRING=ClientId=$clientId;Authorization=AAD" `
        "AZURE_CLIENT_ID=$clientId" `
        "INVENTORY_STORAGE_ACCOUNT=$StorageAccount" `
        "INVENTORY_CONTAINER=$ContainerName" `
        "INVENTORY_BLOB_NAME=$BlobName" `
        "INVENTORY_SCHEDULE=$ScheduleUtc" `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not configure the function app."

az functionapp config appsettings delete `
    --resource-group $ResourceGroup `
    --name $FunctionApp `
    --setting-names AzureWebJobsStorage `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not remove the storage secret setting."

Write-Host "Granting Microsoft Graph User.Read.All..."
$graphAppId = "00000003-0000-0000-c000-000000000000"
$graphJson = az ad sp show --id $graphAppId --output json
Assert-LastExitCode "Could not read the Microsoft Graph service principal."
$graph = $graphJson | ConvertFrom-Json
$graphSpId = $graph.id
$graphRole = $graph.appRoles | Where-Object {
    $_.value -eq "User.Read.All" -and
    $_.allowedMemberTypes -contains "Application"
} | Select-Object -First 1

if (-not $graphRole) {
    throw "Microsoft Graph User.Read.All application role was not found."
}

$assignmentJson = az rest `
    --method GET `
    --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" `
    --output json
Assert-LastExitCode "Could not read Microsoft Graph role assignments."
$assignments = ($assignmentJson | ConvertFrom-Json).value
$existingGraphRole = $assignments | Where-Object {
    $_.resourceId -eq $graphSpId -and
    $_.appRoleId -eq $graphRole.id
}

if (-not $existingGraphRole) {
    $body = @{
        principalId = $principalId
        resourceId = $graphSpId
        appRoleId = $graphRole.id
    } | ConvertTo-Json -Compress

    az rest `
        --method POST `
        --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" `
        --body $body `
        --headers "Content-Type=application/json" `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not grant User.Read.All. A tenant administrator may be required."
}

Write-Host "Publishing the Azure Function..."
func azure functionapp publish $FunctionApp --python
Assert-LastExitCode "Function deployment failed."

Write-Host ""
Write-Host "Azure V5 deployment completed."
Write-Host "Function app: $FunctionApp"
Write-Host "Storage:     $StorageAccount"
Write-Host "Blob:        $ContainerName/$BlobName"
Write-Host "Schedule:    $ScheduleUtc UTC"
