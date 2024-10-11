function Get-GHPRAzDOBuildArtifactDownloadLink {
    <#
    .SYNOPSIS
        Gets specified Build Artifacts from specified Azure Pipeline that was used in building a GitHub PR
    .DESCRIPTION
        As per Synopsis
    .NOTES
        Requires gh cli tool installed and logged in
        Currently assumes accessing a public GitHub Repo hosted on github.com not one that is hosted on a private self hosted Github Enterprise instance
        Azure Pipeline should be openly accessible as well and not require a user access token or login for access.
        
        Gets Pipeline status as reported in GitHub UI using this Rest API - https://docs.github.com/en/rest/checks/runs?apiVersion=2022-11-28#list-check-runs-for-a-git-reference
        Gets Pipeline artifact from Azure Pipeline run using this API - https://learn.microsoft.com/en-us/rest/api/azure/devops/build/artifacts/get-artifact?view=azure-devops-rest-7.2
    .LINK

    .EXAMPLE
        Get-GHAzDOPRBuildArtifact -Org PowerShell -Repo PowerShell -PRNumber 24194 -CheckName 'PowerShell-CI-windows' -BuildArtifactName build 
        
        Gets PR 24194 from the PowerShell/PowerShell repo on GitHub and queries it for the Azure (DevOps) Pipeline called 'PowerShell-CI-windows'and its resulting build artifact which is called 'build' & downloads it to the defaulted folder of C:\PRBuilds\ and then extracts it to the defaulted PRBuilds Folder

    .EXAMPLE
        Get-GHAzDOPRBuildArtifact -Org dsccommunity -Repo ActiveDirectoryDSC -PRNumber  -CheckName 'PowerShell-CI-windows' -BuildArtifactName build 
        
        Gets PR 24194 from the PowerShell/PowerShell repo on GitHub and queries it for the Azure (DevOps) Pipeline called 'PowerShell-CI-windows'and its resulting build artifact which is called 'build' & downloads it to the defaulted folder of C:\PRBuilds\ and then extracts it to the defaulted PRBuilds Folder

        #>
    [CmdletBinding()]
    [Alias('gghazprba')]
    param (
        [Parameter()]
        [string]
        $Org = 'PowerShell',

        [Parameter()]
        [string]
        $Repo = 'PowerShell',

        [Parameter(Mandatory,ValueFromPipelineByPropertyName,ValueFromPipeline)]
        [string[]]
        $PRNumber,

        [Parameter()]
        [ValidateSet('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux', 'PowerShell-CI-macos-daily', 'PowerShell-CI-Windows-daily', 'PowerShell-CI-linux-daily')] # Replace this with any build names you may require 
        [string[]]
        $CheckName = @('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux'),

        [parameter()]
        [ValidateSet('build', 'Windows', 'macOS', 'Linux')] # Replace this with whatever you need
        [string[]]
        $BuildArtifactName = 'build' # PowerShell builds are using this for the artifact name 
    )

    process {
    $defuri = "/repos/$Org/$Repo"

    foreach ($PR in $PRNumber) {
        Write-Verbose "Checking if $PR is a PR or not" 
        $PRCheck = gh pr view $PR --repo $Org/$Repo *>&1 
        If ($PRCheck -match 'GraphQL: Could not resolve to a PullRequest with the number of') {
            Write-Error -Message "PRNumber $PR is not a PR - Please Try again with a PR"
            continue
        }
        else {
            Write-Verbose "$PR is a PR - Gathering required additional PR metadata"
            $pull = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/pulls/$PR" | ConvertFrom-Json
            # $pull has commits_url property we can use to grab all the commits from
            $pullcommits = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" $pull.commits_url | ConvertFrom-Json
            # Get the most recent commit included in a PR and the resulting check runs for that commit using the sha of the commit 
            $pullchecks = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/commits/$($pullcommits[-1].sha)/check-runs" | ConvertFrom-Json
            Write-Verbose "Checking against provided Checknames - $CheckName"
            $builds = foreach ($check in $CheckName) { 
                $pullchecks.check_runs 
                | Where-Object Name -EQ $check 
                | Where-Object conclusion -ne 'neutral' 
                | Select-Object  @{n = 'BuildName'; e = { $_.name } },
                @{n = 'GHRunID' ; Expression = { $_.id } },
                @{n = 'PRNumber' ; ex = { $pull.number } }, 
                @{n = "AzDO_BuildBaseUrl"; ex = { $_.details_url.Split('/_build')[0] } },
                @{n = "AzDO_BuildID"; ex = { $_.details_url.split('=')[-1] } }, 
                @{n = 'allDetails' ; e = { $_ } },
                @{n = "DownloadURL" ; e = { "$($_.details_url.Split('/_build')[0])/_apis/build/builds/$($_.details_url.split('=')[-1])/artifacts?artifactName=build&api-version=7.1&%24format=zip" } } 
            }
            If (-not $builds) {
                Write-Error "No passing Checks matched the $CheckName specified for $PR"
            }
            else {
                foreach ($build in $builds ) { 
                    Write-Output "$($Build.BuildName) DownloadUrl: $($build.DownloadURL)"
                }
            }
        }
    }
}
}

