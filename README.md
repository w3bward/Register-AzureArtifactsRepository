# Register-AzureArtifactsRepository
Registers an Azure Artifacts feed as a PS repository using the Artifacts Credential Provider with a PAT for authentication

## Why did I write this script?
Some people who read the [dev blog post](https://devblogs.microsoft.com/powershell/using-powershellget-with-azure-artifacts/) announcing the ability to use Azure Artifacts as a private Powershell Repository may have noticed that the authentication is incredibly buggy. The most reliable way that I have found to authenticate without providing credentials every time I try to find or install a module is to store a PAT as an environment variable, but this approach has a number of prerequisites that aren't well documented in any one place. This script handles the prerequisites, creates the environment variable, and registers the PS Repository.

I have tried to make this script easy to use, but it doesn't have much in the way of guard rails. Please understand what this script does, and that you assume responsibility for any problems that may arise from running it. **You will probably have a bad time if you try to name your new repo "PSGallery" or "nuget.org," I have not tried it and you probably shouldn't either.** This script stores an access token as a persistent user environment variable on the machine it runs on, this may not be appropriate for the security requirements of some environments.

## What does this script do?
1. Checks for compatible versions of PowershellGet, and PackageManagement. It will install them if a compatible version isn't installed.
2. Installs the [Artifacts Credential Provider](https://github.com/microsoft/artifacts-credprovider).
3. Appends a line to the current user's Powershell profile to set the NUGET_PLUGIN_PATHS environment variable in all future Powershell sessions.
4. Sets the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable for the current user, this allows for the repository to be accessed in the future without providing credentials.
5. Looks for existing repositories and package sources with the specified name, **and removes them**
6. Registers a new NuGet package source, and new PS repository with the specifed name and URL

## How to use this script.
Please note that this script is only designed to work on Windows at the moment. 

I have also not yet tested this on Core versions of Powershell, I suspect that I may need to add some logic around the value of NUGET_PLUGIN_PATHS for Core.

1. [Get a PAT](https://docs.microsoft.com/en-us/azure/devops/organizations/accounts/use-personal-access-tokens-to-authenticate?view=azure-devops&tabs=preview-page#create-a-pat) that has Packaging permissions. I recommend setting the expiration to the max (1 year), you will need to run this script again or update the VSS_NUGET_EXTERNAL_FEED_ENDPOINTS environment variable manually when the token expires.
2. Find the URI for your Azure Artifacts feed. Note: you must use the v2 endpoint, PowershellGet does not work with v3. It should look something like `https://pkgs.dev.azure.com/{organization}/_packaging/{feedname}/nuget/v2` or `https://{organization}.pkgs.visualstudio.com/_packaging/{feedname}/nuget/v2` depending on which URL scheme your organization uses.
3. Run the script:
```
$PAT = '{PAT from step 1}'
$URI = '{URI from step 2}'
$Name = '{The name that you want to call your repo}' #NOTE: existing repos with this name will be replaced!
.\Register-AzureArtifactsRepository.ps1 -RepositoryName $Name -RepositoryUrl $URI -PAT $PAT
```
