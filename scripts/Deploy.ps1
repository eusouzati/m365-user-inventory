[CmdletBinding()]
param(
    [string]$EnvFile = ".env",
    [switch]$Yes
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

function Import-DotEnv {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Configuration file was not found: $Path. Copy .env.example to .env and fill in the required values."
    }

    $values = @{}
    $lineNumber = 0

    foreach ($rawLine in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $lineNumber += 1
        $line = $rawLine.Trim().TrimStart([char]0xFEFF)

        if (-not $line -or $line.StartsWith("#")) {
            continue
        }

        $separatorIndex = $line.IndexOf("=")
        if ($separatorIndex -lt 1) {
            throw "Invalid .env entry at line $lineNumber. Expected KEY=VALUE."
        }

        $key = $line.Substring(0, $separatorIndex).Trim()
        $value = $line.Substring($separatorIndex + 1).Trim()

        if ($key -notmatch "^[A-Z][A-Z0-9_]*$") {
            throw "Invalid variable name at line $lineNumber`: $key"
        }

        if ($value.Length -ge 2) {
            $firstCharacter = $value[0]
            $lastCharacter = $value[$value.Length - 1]
            if (
                ($firstCharacter -eq '"' -and $lastCharacter -eq '"') -or
                ($firstCharacter -eq "'" -and $lastCharacter -eq "'")
            ) {
                $value = $value.Substring(1, $value.Length - 2)
            }
        }

        $values[$key] = $value
    }

    return $values
}

function Get-ConfigValue {
    param(
        [hashtable]$Config,
        [string]$Name,
        [string]$Default = "",
        [switch]$Required
    )

    $value = $Default
    if (
        $Config.ContainsKey($Name) -and
        -not [string]::IsNullOrWhiteSpace([string]$Config[$Name])
    ) {
        $value = [string]$Config[$Name]
    }

    if ($Required -and [string]::IsNullOrWhiteSpace($value)) {
        throw "Required configuration is missing in .env: $Name"
    }

    return $value
}

function Add-RoleAssignmentIfMissing {
    param(
        [string]$PrincipalId,
        [string]$PrincipalType,
        [string]$Role,
        [string]$Scope,
        [string]$FailureMessage
    )

    $existingRole = az role assignment list `
        --assignee $PrincipalId `
        --scope $Scope `
        --role $Role `
        --query "[0].id" `
        --output tsv `
        --only-show-errors
    Assert-LastExitCode "Could not read the role assignment: $Role"

    if (-not $existingRole) {
        Write-Host "Granting role: $Role"
        az role assignment create `
            --assignee-object-id $PrincipalId `
            --assignee-principal-type $PrincipalType `
            --role $Role `
            --scope $Scope `
            --only-show-errors `
            --output none
        Assert-LastExitCode $FailureMessage
    }
}

if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw "Azure CLI was not found. Install Azure CLI and run the script again."
}

if (-not (Get-Command func -ErrorAction SilentlyContinue)) {
    throw "Azure Functions Core Tools 4 was not found."
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$resolvedEnvFile = if ([System.IO.Path]::IsPathRooted($EnvFile)) {
    $EnvFile
}
else {
    Join-Path $repositoryRoot $EnvFile
}

$config = Import-DotEnv -Path $resolvedEnvFile

$m365TenantId = Get-ConfigValue `
    -Config $config `
    -Name "M365_TENANT_ID"
$azureTenantId = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_TENANT_ID" `
    -Default $m365TenantId `
    -Required
$subscriptionId = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_SUBSCRIPTION_ID" `
    -Required
$location = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_LOCATION" `
    -Default "brazilsouth"
$resourceGroup = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_RESOURCE_GROUP" `
    -Default "rg-m365-user-inventory"
$identityName = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_MANAGED_IDENTITY_NAME" `
    -Default "id-m365-user-inventory"
$containerName = Get-ConfigValue `
    -Config $config `
    -Name "INVENTORY_CONTAINER" `
    -Default "inventory"
$blobName = Get-ConfigValue `
    -Config $config `
    -Name "INVENTORY_BLOB_NAME" `
    -Default "m365_users.csv"
$scheduleUtc = Get-ConfigValue `
    -Config $config `
    -Name "INVENTORY_SCHEDULE" `
    -Default "0 0 11 * * *"

$sha = [System.Security.Cryptography.SHA256]::Create()
try {
    $hashBytes = $sha.ComputeHash(
        [System.Text.Encoding]::UTF8.GetBytes($subscriptionId)
    )
}
finally {
    $sha.Dispose()
}

$suffix = (
    [System.BitConverter]::ToString($hashBytes)
).Replace("-", "").Substring(0, 10).ToLowerInvariant()

$storageAccount = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_STORAGE_ACCOUNT" `
    -Default "stm365inv$suffix"
$functionApp = Get-ConfigValue `
    -Config $config `
    -Name "AZURE_FUNCTION_APP" `
    -Default "func-m365-inventory-$suffix"

if ($storageAccount -notmatch "^[a-z0-9]{3,24}$") {
    throw "AZURE_STORAGE_ACCOUNT must contain 3-24 lowercase letters and numbers."
}

if ($functionApp -notmatch "^[A-Za-z0-9][A-Za-z0-9-]{0,58}[A-Za-z0-9]$") {
    throw "AZURE_FUNCTION_APP must contain 2-60 letters, numbers or hyphens."
}

if (-not (Test-AzCommand @("account", "set", "--subscription", $subscriptionId))) {
    Write-Host "Azure sign-in is required for tenant: $azureTenantId"
    az login --tenant $azureTenantId --only-show-errors --output none
    Assert-LastExitCode "Azure sign-in failed."

    az account set --subscription $subscriptionId --only-show-errors
    Assert-LastExitCode "The configured subscription is not available to this account."
}

$accountJson = az account show --subscription $subscriptionId --output json --only-show-errors
Assert-LastExitCode "Could not read the configured Azure subscription."
$account = $accountJson | ConvertFrom-Json

if ($account.tenantId -ne $azureTenantId) {
    throw "AZURE_TENANT_ID does not match the tenant of AZURE_SUBSCRIPTION_ID."
}

Write-Host "Microsoft 365 User Inventory deployment plan"
Write-Host "User:             $($account.user.name)"
Write-Host "Subscription:     $($account.name)"
Write-Host "Tenant:           $azureTenantId"
Write-Host "Resource group:   $resourceGroup"
Write-Host "Location:         $location"
Write-Host "Storage account:  $storageAccount"
Write-Host "Function app:     $functionApp"
Write-Host "Managed identity: $identityName"
Write-Host "Blob:             $containerName/$blobName"
Write-Host "Schedule:         $scheduleUtc UTC"
Write-Host ""
Write-Host "No client secret will be deployed to Azure."

if (-not $Yes) {
    Write-Host "This creates Azure resources that may generate charges."
    $confirmation = Read-Host "Type DEPLOY to continue"
    if ($confirmation -cne "DEPLOY") {
        Write-Host "Deployment cancelled."
        exit 0
    }
}

foreach ($provider in @(
    "Microsoft.Web",
    "Microsoft.Storage",
    "Microsoft.Insights",
    "Microsoft.ManagedIdentity"
)) {
    Write-Host "Registering provider: $provider"
    az provider register `
        --namespace $provider `
        --wait `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not register provider: $provider"
}

if (-not (Test-AzCommand @("group", "show", "--name", $resourceGroup))) {
    Write-Host "Creating resource group..."
    az group create `
        --name $resourceGroup `
        --location $location `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the resource group."
}

if (-not (Test-AzCommand @(
    "storage", "account", "show",
    "--resource-group", $resourceGroup,
    "--name", $storageAccount
))) {
    Write-Host "Creating storage account..."
    az storage account create `
        --name $storageAccount `
        --resource-group $resourceGroup `
        --location $location `
        --sku Standard_LRS `
        --allow-blob-public-access false `
        --allow-shared-key-access false `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the storage account."
}

if (-not (Test-AzCommand @(
    "identity", "show",
    "--resource-group", $resourceGroup,
    "--name", $identityName
))) {
    Write-Host "Creating managed identity..."
    az identity create `
        --name $identityName `
        --resource-group $resourceGroup `
        --location $location `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the managed identity."
}

$identityJson = az identity show `
    --name $identityName `
    --resource-group $resourceGroup `
    --output json `
    --only-show-errors
Assert-LastExitCode "Could not read the managed identity."
$identity = $identityJson | ConvertFrom-Json
$identityId = $identity.id
$principalId = $identity.principalId
$clientId = $identity.clientId

$storageId = az storage account show `
    --resource-group $resourceGroup `
    --name $storageAccount `
    --query id `
    --output tsv `
    --only-show-errors
Assert-LastExitCode "Could not read the storage account."

Add-RoleAssignmentIfMissing `
    -PrincipalId $principalId `
    -PrincipalType "ServicePrincipal" `
    -Role "Storage Blob Data Owner" `
    -Scope $storageId `
    -FailureMessage "Could not grant storage access."

if (-not (Test-AzCommand @(
    "functionapp", "show",
    "--resource-group", $resourceGroup,
    "--name", $functionApp
))) {
    Write-Host "Creating Flex Consumption function app..."
    az functionapp create `
        --resource-group $resourceGroup `
        --name $functionApp `
        --flexconsumption-location $location `
        --runtime python `
        --runtime-version 3.11 `
        --storage-account $storageAccount `
        --deployment-storage-auth-type UserAssignedIdentity `
        --deployment-storage-auth-value $identityName `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the function app. Run the script again after a few minutes."
}

Write-Host "Ensuring the managed identity is attached..."
az functionapp identity assign `
    --resource-group $resourceGroup `
    --name $functionApp `
    --identities $identityId `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not attach the managed identity."

$appInsightsId = az resource list `
    --resource-group $resourceGroup `
    --resource-type "Microsoft.Insights/components" `
    --query "[?name=='$functionApp'].id | [0]" `
    --output tsv `
    --only-show-errors
Assert-LastExitCode "Could not read the Application Insights resource."

if (-not $appInsightsId) {
    throw "Application Insights resource was not found."
}

Add-RoleAssignmentIfMissing `
    -PrincipalId $principalId `
    -PrincipalType "ServicePrincipal" `
    -Role "Monitoring Metrics Publisher" `
    -Scope $appInsightsId `
    -FailureMessage "Could not grant Application Insights telemetry access."

if (-not (Test-AzCommand @(
    "storage", "container-rm", "show",
    "--resource-group", $resourceGroup,
    "--storage-account", $storageAccount,
    "--name", $containerName
))) {
    Write-Host "Creating private inventory container..."
    az storage container-rm create `
        --resource-group $resourceGroup `
        --storage-account $storageAccount `
        --name $containerName `
        --public-access off `
        --only-show-errors `
        --output none
    Assert-LastExitCode "Could not create the inventory container."
}

if ($account.user.type -eq "user") {
    $signedInUserObjectId = az ad signed-in-user show `
        --query id `
        --output tsv `
        --only-show-errors
    Assert-LastExitCode "Could not read the signed-in user object ID."

    $containerScope = "$storageId/blobServices/default/containers/$containerName"
    Add-RoleAssignmentIfMissing `
        -PrincipalId $signedInUserObjectId `
        -PrincipalType "User" `
        -Role "Storage Blob Data Reader" `
        -Scope $containerScope `
        -FailureMessage "Could not grant read-only inventory access."
}

Write-Host "Configuring passwordless application settings..."
az functionapp config appsettings set `
    --resource-group $resourceGroup `
    --name $functionApp `
    --settings `
        "AzureWebJobsStorage__accountName=$storageAccount" `
        "AzureWebJobsStorage__credential=managedidentity" `
        "AzureWebJobsStorage__clientId=$clientId" `
        "APPLICATIONINSIGHTS_AUTHENTICATION_STRING=ClientId=$clientId;Authorization=AAD" `
        "AZURE_CLIENT_ID=$clientId" `
        "INVENTORY_STORAGE_ACCOUNT=$storageAccount" `
        "INVENTORY_CONTAINER=$containerName" `
        "INVENTORY_BLOB_NAME=$blobName" `
        "INVENTORY_SCHEDULE=$scheduleUtc" `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not configure the function app."

az functionapp config appsettings delete `
    --resource-group $resourceGroup `
    --name $functionApp `
    --setting-names AzureWebJobsStorage `
    --only-show-errors `
    --output none
Assert-LastExitCode "Could not remove the storage secret setting."

Write-Host "Granting Microsoft Graph User.Read.All..."
$graphAppId = "00000003-0000-0000-c000-000000000000"
$graphJson = az ad sp show `
    --id $graphAppId `
    --output json `
    --only-show-errors
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
    --output json `
    --only-show-errors
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

    $bodyFilePath = Join-Path (
        [System.IO.Path]::GetTempPath()
    ) ("m365-graph-role-{0}.json" -f [guid]::NewGuid().ToString("N"))

    try {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::WriteAllText($bodyFilePath, $body, $utf8NoBom)

        az rest `
            --method POST `
            --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments" `
            --body "@$bodyFilePath" `
            --headers "Content-Type=application/json" `
            --only-show-errors `
            --output none
        Assert-LastExitCode "Could not grant User.Read.All. A tenant administrator is required."
    }
    finally {
        Remove-Item `
            -LiteralPath $bodyFilePath `
            -Force `
            -ErrorAction SilentlyContinue
    }
}

Write-Host "Publishing the Azure Function..."
Push-Location $repositoryRoot
try {
    func azure functionapp publish $functionApp --python
    Assert-LastExitCode "Function deployment failed."
}
finally {
    Pop-Location
}

Write-Host ""
Write-Host "Deployment completed successfully."
Write-Host "Function app: $functionApp"
Write-Host "Storage:     $storageAccount"
Write-Host "Blob:        $containerName/$blobName"
Write-Host "Schedule:    $scheduleUtc UTC"
Write-Host ""
Write-Host "The local client secret remains only in .env and was not deployed."
