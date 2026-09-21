$domain = "autosilva.onmicrosoft.com"

$users = @(
    @{
        DisplayName = "Ana Martins"
        UserName    = "ana.martins"
        Department  = "IT"
        JobTitle    = "Cloud Analyst"
    },
    @{
        DisplayName = "Carlos Lima"
        UserName    = "carlos.lima"
        Department  = "Finance"
        JobTitle    = "Financial Analyst"
    },
    @{
        DisplayName = "Mariana Souza"
        UserName    = "mariana.souza"
        Department  = "HR"
        JobTitle    = "HR Analyst"
    },
    @{
        DisplayName = "Pedro Santos"
        UserName    = "pedro.santos"
        Department  = "Operations"
        JobTitle    = "Operations Analyst"
    },
    @{
        DisplayName = "Lucas Oliveira"
        UserName    = "lucas.oliveira"
        Department  = "IT"
        JobTitle    = "Systems Analyst"
    },
    @{
        DisplayName = "Camila Alves"
        UserName    = "camila.alves"
        Department  = "Sales"
        JobTitle    = "Sales Analyst"
    }
)

$securePassword = Read-Host "Enter the initial password for the lab users" -AsSecureString

$ptr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($securePassword)

try {

    $plainPassword = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($ptr)

    foreach ($user in $users) {

        $upn = "$($user.UserName)@$domain"

        try {

            $existingUser = Get-MgUser `
                -Filter "userPrincipalName eq '$upn'" `
                -ErrorAction Stop

            if ($existingUser) {
                Write-Host "SKIPPED: $upn already exists."
                continue
            }

            $params = @{
                AccountEnabled    = $true
                DisplayName       = $user.DisplayName
                MailNickname      = $user.UserName
                UserPrincipalName = $upn
                Department        = $user.Department
                JobTitle          = $user.JobTitle
                UsageLocation     = "BR"

                PasswordProfile = @{
                    ForceChangePasswordNextSignIn = $true
                    Password                      = $plainPassword
                }
            }

            $createdUser = New-MgUser `
                -BodyParameter $params `
                -ErrorAction Stop

            Write-Host "CREATED: $($createdUser.UserPrincipalName)"
        }
        catch {
            Write-Host "ERROR: $upn"
            Write-Host $_.Exception.Message
        }
    }
}
finally {

    if ($ptr -ne [IntPtr]::Zero) {
        [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ptr)
    }

    $plainPassword = $null
}