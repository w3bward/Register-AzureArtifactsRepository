[CmdletBinding()]
param (
    # A name for the repository on the local system
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$RepositoryName,

    # The url of the Artifacts Repo, e.g. "https://pkgs.dev.azure.com/'yourorganizationname'/_packaging/'yourfeedname'/nuget/v2"
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$RepositoryUrl,

    # An Azure DevOps PAT with at least Packaging (Read) permissions. If you plan to publish modules, make sure the token has Read & Write
    [Parameter(Mandatory = $true, Position = 2, HelpMessage='Please enter an Azure DevOps PAT with Packaging permissions')]
    [string]$PAT
)

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$MinimumPSGetVersion             = [System.Version]::new(2, 2, 4, 1)
$MinimumPackageManagementVersion = [System.Version]::new(1, 4, 7)

# Line to add to current users Powershell profile to set NUGET_PLUGIN_PATHS environment variable when using Powershell
$PSProfileAddition = '$Env:NUGET_PLUGIN_PATHS = "$home\.nuget\plugins\netfx\CredentialProvider.Microsoft\CredentialProvider.Microsoft.exe"'

# URL for the Azure Artifacts Credential Provider setup script. More info: https://github.com/microsoft/artifacts-credprovider
$ArtifactsCredentialProviderScriptUrl = 'https://aka.ms/install-artifacts-credprovider.ps1'

function Install-RequiredModuleVersion {
    [CmdletBinding()]
    param (
        # Name of the required module
        [Parameter(Mandatory = $true, Position = 0)]
        [string]$ModuleName,

        # Minimum required version of the module, if -RequireExactVersion is used, then this is the required version
        [Parameter(Mandatory = $true, Position = 1)]
        [System.Version]$ModuleVersion,

        # If used, the Module version must be an exact match, otherwise installed versions newer than ModuleVersion will be considered as meeting the requirement
        [Parameter(Mandatory = $false)]
        [switch]$RequireExactVersion
    )
    
    if ($RequireExactVersion) {
        $InstalledVersion = Get-Module $ModuleName -ListAvailable | Where-Object Version -eq $ModuleVersion
    }
    else {
        $InstalledVersion = Get-Module $ModuleName -ListAvailable | 
            Where-Object Version -ge $ModuleVersion |
            Sort-Object Version -Descending |
            Select-Object -First 1
    }

    if ($InstalledVersion) {
        $ModuleVersion = $InstalledVersion.Version
        Write-Host "$ModuleName version $($InstalledVersion.Version) is already installed."
    }
    else {
        Write-Host "A version of $ModuleName meeting the requirements could not be found, version $ModuleVersion will be installed"
        Install-Module $ModuleName -RequiredVersion $ModuleVersion -Force -AllowClobber -Confirm:$false
    }

    Write-Host "Removing previously imported versions of $ModuleName from the current session"
    Get-Module $ModuleVersion | Remove-Module

    Write-Host "Importing $ModuleName version $ModuleVersion"
    Import-Module $ModuleName -RequiredVersion $ModuleVersion -Force
}

# Ensure that a minimum required version of PowershellGet is installed
Install-RequiredModuleVersion -ModuleName PowershellGet -ModuleVersion $MinimumPSGetVersion

# Ensure that a minimum required version of PackageManagement is installed
Install-RequiredModuleVersion -ModuleName PackageManagement -ModuleVersion $MinimumPackageManagementVersion

# Download/run the install script for the Artifacts Credential Provider: https://github.com/microsoft/artifacts-credprovider
Write-Host "Downloading the Artifacts Credential Provider installation script"
$ArtifactsInstallScript = Invoke-RestMethod $ArtifactsCredentialProviderScriptUrl -ErrorAction Stop

Write-Host "Installing the Artifacts Credential Provider"
Invoke-Expression "& {$ArtifactsInstallScript} -AddNetfx"

# If not set: Append a line to the Powershell profile to set the NUGET_PLUGIN_PATHS environment variable in future Powershell sessions
$AppendProfile = $true
if (Test-Path $Profile.CurrentUserAllHosts -PathType Leaf) {
    $Content = Get-Content $Profile.CurrentUserAllHosts
    
    if ($Content -contains $PSProfileAddition) {
        $AppendProfile = $false
    }
}

if ($AppendProfile) {
    Write-Host "Adding the environment variable NUGET_PLUGIN_PATHS to the current user's Powershell profile"
    $PSProfileAddition | Out-File $profile.CurrentUserAllHosts -Append
}

# Make sure NUGET_PLUGIN_PATHS is set in the current session
Write-Host "Setting the environment variable NUGET_PLUGIN_PATHS in the current session"
$Env:NUGET_PLUGIN_PATHS = "$home\.nuget\plugins\netfx\CredentialProvider.Microsoft\CredentialProvider.Microsoft.exe"

# Set the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable for the current user
# TODO: check if there's existing, guard overwrite with ShouldProcess
$EndpointCredentials = [PSCustomObject]@{
    endpointCredentials = @(
        @{
            endpoint = $RepositoryUrl
            username = 'username'
            password = $PAT
        }
    )
} | ConvertTo-Json -Compress
Write-Host "Adding VSS_NUGET_EXTERNAL_FEED_ENDPOINTS to the current user's environment variables"
[System.Environment]::SetEnvironmentVariable('VSS_NUGET_EXTERNAL_FEED_ENDPOINTS',$EndpointCredentials,[System.EnvironmentVariableTarget]::User)

# Unregister any existing package sources/repositories with the $RepositoryName, and register the new repository
# TODO: Guard this step with a ShouldProcess block.
Write-Host "Unregistering any previous instances of PSRepository $RepositoryName"
Get-PSRepository | Where-Object Name -eq $RepositoryName | Unregister-PSRepository -WarningAction SilentlyContinue

Write-Host "Unregistering any previous instances of Package Source $RepositoryName"
Get-PackageSource | Where-Object Name -eq $RepositoryName | Unregister-PackageSource -WarningAction SilentlyContinue

Write-Host "Registering $RepositoryUrl as a package source"
Register-PackageSource -Name $RepositoryName -Location $RepositoryUrl -ProviderName NuGet -SkipValidate -ErrorAction Stop | Out-Null

Write-Host "Registering $RepositoryUrl as a Powershell Repository"

$Password = ConvertTo-SecureString $PAT -AsPlainText -Force
$Credential = New-Object System.Management.Automation.PSCredential "user", $Password

$PsRepositorySplat = @{
    Name            = $RepositoryName
    SourceLocation  = $RepositoryUrl
    PublishLocation = $RepositoryUrl
    Credential      = $Credential
}

Register-PSRepository @PsRepositorySplat
