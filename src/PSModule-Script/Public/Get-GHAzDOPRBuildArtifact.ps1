
#Requires -Version 7.0 
## Should work downlevel - not tested
## Requires GH CLI (for now) - Could be updated with pure rest/graph ql calls instead of gh cli


function Get-GHAzDOPRBuildArtifact {
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

        [Parameter(Mandatory, ValueFromPipelineByPropertyName, ValueFromPipeline)]
        [string[]]
        $PRNumber,

        [Parameter()]
        # Examples for the PowerShell Repo
        #[ValidateSet('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux', 'PowerShell-CI-macos-daily', 'PowerShell-CI-Windows-daily', 'PowerShell-CI-linux-daily')] # Replace this with any build names you require for youe
        [string[]]
        #$CheckName = @('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux'),
        $CheckName,

        [parameter()]
        #[ValidateSet('build', 'Windows', 'macOS', 'Linux', 'helloworld')] # Replace this with whatever you need
        [string[]]
        #$BuildArtifactName = 'build', # PowerShell builds are using this for the artifact name 
        $BuildArtifactName,
        
        [Parameter()]
        [string]
        $OutPath = "C:\PRBuilds\",
        
        [Parameter()]
        [switch]
        $Start
    )   
    begin {

        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'No GH CLI installed, exiting as this is a pre-req' }
        $defuri = "/repos/$Org/$Repo"
    }
    process {
        if ($PRNumber.Count -gt 1) {
            $Message = "Attempting to download build artifacts for each PRNumber that you provided - $($PRNumber.split(','))" 
        }
        else {
            $Message = "Attempting to download build artifacts PRNumber $PRNumber" 
        }
        Write-Verbose $Message
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

                ## TODO: Issue :here we could remove the need for providing a checkname and have this just download based on all checks or prompt for a specific check as returned from the above 
                Write-Verbose "Checking against provided Checknames - $CheckName"
                $builds = foreach ($check in $CheckName) { 
                    $pullchecks.check_runs 
                    | Where-Object Name -EQ $check 
                    | Where-Object conclusion -NE 'neutral' # This check stops us getting any skipped builds
                    | Select-Object  @{n = 'BuildName'; e = { $_.name } },
                    @{n = 'GHRunID' ; Expression = { $_.id } },
                    @{n = 'PRNumber' ; ex = { $pull.number } }, 
                    @{n = "AzDO_BuildBaseUrl"; ex = { $_.details_url.Split('/_build')[0] } },
                    @{n = "AzDO_BuildID"; ex = { $_.details_url.split('=')[-1] } }, 
                    @{n = 'allDetails' ; e = { $_ } },
                    @{n = "DownloadURL" ; e = { "$($_.details_url.Split('/_build')[0])/_apis/build/builds/$($_.details_url.split('=')[-1])/artifacts?artifactName=$BuildArtifactName&api-version=7.1&%24format=zip" } } 
                }
                If (-not $builds) {
                    Write-Error "No passing Checks matched the $CheckName specified for $PR"
                }
                else {
                    Write-Verbose "Checking for $checkName - was Sucessful - Starting Download process for each as provided"
                    $prPath = "$OutPath$PR"
                    if (-not (Test-Path $prPath) ) { 
                        mkdir "$prPath" -Force  | Out-Null 
                        Write-Verbose "Created path for download"
                    }
                    else {
                        Write-Verbose "Path for download already existed so reusing it"
                    }
                    # Potential Refactor for parallism here especially if downloading multiple PR's at once
                    foreach ($build in $builds ) { 

                        ## TODO: This section needs a CleanUp as I really don't like how this is
                        ## 
                        $downloadPath = "$outpath\$PR\$($build.BuildName)-$($build.AzDO_BuildID)"
                        if (-not (Test-Path "$downloadPath\$BuildArtifactName\$BuildArtifactName\publish")) {
                            Write-Verbose "DownloadUrl: $($build.DownloadURL)"
                            Write-Verbose $downloadPath
                            Write-Verbose "Starting Download of CheckName $($build.BuildName) with Azure Pipeline BuildID $($build.AzDO_BuildID) for $PR to $downloadPath.zip"
                            Invoke-WebRequest $build.DownloadURL -OutFile "$downloadPath.zip" -Verbose:$false
                            # build artifacts are nested in a zip within a zip when  
                            Expand-Archive "$downloadPath.zip" -DestinationPath "$downloadPath\" -Force
                            Expand-Archive "$downloadPath\$BuildArtifactName\$BuildArtifactName.zip" "$downloadPath\$BuildArtifactName\$BuildArtifactName" -Force

                            Move-Item "$downloadPath\$BuildArtifactName\$BuildArtifactName" -Destination $downloadPath -Force
                            Write-Output "Download of Build $($build.AzDO_BuildID) of $($build.BuildName) for PR $PR complete"
                            Remove-Item "$downloadPath.zip" -Force
                            Write-Verbose "Download of Build $($build.AzDO_BuildID) of $($build.BuildName) complete"
                            if ($start) {
                                $Message = "This is the artifact for Build $($build.AzDO_BuildID) of $($build.BuildName) for PR $PR"
                                ### Get any exe from the download path and if pwsh start it with arguments
                                $BuildEXE = Get-ChildItem $downloadPath -Recurse -Include '*.exe'
                                if ($IsWindows) {
                                    if ($Buildexe.BaseName -match 'pwsh') {
                                        Start-Process $BuildEXE.FullName -ArgumentList "-NoProfile -NoExit -Command `"`$host.UI.RawUI.WindowTitle = '$message'`"" -WorkingDirectory $downloadPath
                                    }
                                    else {
                                        Start-Process $BuildEXE.FullName 
                                    }
                                }
                                else {
                                    Start-Process $downloadPath\publish\pwsh -ArgumentList "-NoProfile -NoExit -Command `"`$host.UI.RawUI.WindowTitle = '$message'`"" -WorkingDirectory $downloadPath
                                }
                            }
                        }
                        else {
                            Write-Warning "Build $($build.AzDO_BuildID) of $($build.BuildName) has already been downloaded - Skipping"
                        }
                    }
                }
            }
        }
    }
}
