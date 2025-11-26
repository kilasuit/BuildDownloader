
#Requires -Version 7.0 
## Should work downlevel - not tested
## Requires GH CLI (for now) - Could be updated with pure rest/graph ql calls instead of gh cli


function Get-GHWorkflowBuildArtifact {
    <#
    .SYNOPSIS
        Gets specified Build Artifacts from GitHub Actions workflows that were used in building a GitHub PR
    .DESCRIPTION
        Downloads artifacts from GitHub Actions workflow runs associated with a pull request.
        The function queries the PR for workflow runs, retrieves the artifacts, and downloads them.
    .NOTES
        Requires gh cli tool installed and logged in
        Currently assumes accessing a public GitHub Repo hosted on github.com not one that is hosted on a private self hosted Github Enterprise instance
        
        Gets workflow runs using this Rest API - https://docs.github.com/en/rest/actions/workflow-runs
        Gets artifacts using this Rest API - https://docs.github.com/en/rest/actions/artifacts
    .LINK
        https://docs.github.com/en/rest/actions/artifacts
    .EXAMPLE
        Get-GHWorkflowBuildArtifact -Org microsoft -Repo vscode -PRNumber 12345 -WorkflowName 'CI' -ArtifactName 'build-output'
        
        Gets PR 12345 from the microsoft/vscode repo on GitHub and queries it for the GitHub Actions workflow called 'CI' and its resulting artifact called 'build-output' & downloads it to the defaulted folder of C:\PRBuilds\

    .EXAMPLE
        Get-GHWorkflowBuildArtifact -Org PowerShell -Repo PowerShell -PRNumber 24194 -WorkflowName 'Build' -OutPath '/tmp/builds/'
        
        Gets PR 24194 from the PowerShell/PowerShell repo on GitHub, downloads all artifacts from the 'Build' workflow to /tmp/builds/
    #>
    [CmdletBinding()]
    [Alias('gghwfba')]
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
        [string[]]
        $WorkflowName,

        [Parameter()]
        [string[]]
        $ArtifactName,
        
        [Parameter()]
        [string]
        $OutPath = "C:\PRBuilds\",
        
        [Parameter()]
        [switch]
        $Start,

        [Parameter()]
        [int]
        $RetryIntervalSeconds = 30,

        [Parameter()]
        [int]
        $TimeoutSeconds = 600
    )   
    begin {

        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'No GH CLI installed, exiting as this is a pre-req' }
        $defuri = "/repos/$Org/$Repo"
    }
    process {
        if ($PRNumber.Count -gt 1) {
            $Message = "Attempting to download workflow artifacts for each PRNumber that you provided - $($PRNumber -join ', ')" 
        }
        else {
            $Message = "Attempting to download workflow artifacts for PRNumber $PRNumber" 
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
                # Use helper function with retry logic to get workflow runs
                $checkResult = Get-GHPRWorkflowChecks -Org $Org -Repo $Repo -PRNumber $PR -WorkflowName $WorkflowName -RetryIntervalSeconds $RetryIntervalSeconds -TimeoutSeconds $TimeoutSeconds
                if ($null -eq $checkResult) {
                    Write-Error "Failed to get workflow runs for PR $PR (timeout or error occurred)"
                    continue
                }
                $pull = $checkResult.Pull
                $workflowRuns = $checkResult.WorkflowRuns

                if (-not $workflowRuns) {
                    Write-Error "No workflow runs found for PR $PR"
                    continue
                }

                Write-Verbose "Found $($workflowRuns.Count) workflow run(s) for PR $PR"
                
                $prPath = Join-Path -Path $OutPath -ChildPath $PR
                if (-not (Test-Path $prPath) ) { 
                    New-Item -ItemType Directory -Path $prPath -Force | Out-Null 
                    Write-Verbose "Created path for download"
                }
                else {
                    Write-Verbose "Path for download already existed so reusing it"
                }

                foreach ($run in $workflowRuns) {
                    # Get artifacts for this workflow run
                    $artifacts = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/actions/runs/$($run.id)/artifacts" | ConvertFrom-Json
                    
                    if ($artifacts.total_count -eq 0) {
                        Write-Verbose "No artifacts found for workflow run $($run.id) ($($run.name))"
                        continue
                    }
                    
                    $artifactList = $artifacts.artifacts
                    
                    # Filter by artifact name if specified
                    if ($ArtifactName) {
                        $artifactList = $artifactList | Where-Object { $_.name -in $ArtifactName }
                    }
                    
                    # Filter out expired artifacts
                    $artifactList = $artifactList | Where-Object { -not $_.expired }
                    
                    if (-not $artifactList) {
                        Write-Warning "No valid artifacts found for workflow $($run.name) (Run ID: $($run.id))"
                        continue
                    }

                    foreach ($artifact in $artifactList) {
                        $downloadPath = Join-Path -Path $OutPath -ChildPath $PR | Join-Path -ChildPath "$($run.name)-$($run.id)"
                        $artifactDownloadPath = Join-Path -Path $downloadPath -ChildPath $artifact.name
                        
                        if (-not (Test-Path $artifactDownloadPath)) {
                            Write-Verbose "DownloadPath: $artifactDownloadPath"
                            Write-Verbose "Starting Download of artifact $($artifact.name) from workflow $($run.name) (Run ID: $($run.id)) for PR $PR"
                            
                            # Create the download directory
                            if (-not (Test-Path $downloadPath)) {
                                New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
                            }
                            
                            # Download the artifact using gh api
                            $zipPath = "$artifactDownloadPath.zip"
                            try {
                                # Use gh api to download the artifact (handles authentication)
                                gh api "$defuri/actions/artifacts/$($artifact.id)/zip" > $zipPath
                                
                                # Extract the artifact
                                Expand-Archive $zipPath -DestinationPath $artifactDownloadPath -Force
                                
                                # Clean up zip file
                                Remove-Item $zipPath -Force
                                
                                Write-Output "Download of artifact $($artifact.name) from workflow $($run.name) for PR $PR complete"
                                Write-Verbose "Download of artifact $($artifact.name) from workflow run $($run.id) complete"
                                
                                if ($Start) {
                                    $Message = "This is the artifact $($artifact.name) from workflow $($run.name) for PR $PR"
                                    # Get any exe from the download path and if pwsh start it with arguments
                                    $BuildEXE = Get-ChildItem $artifactDownloadPath -Recurse -Include '*.exe' -ErrorAction SilentlyContinue
                                    if ($BuildEXE) {
                                        if ($IsWindows) {
                                            if ($BuildEXE.BaseName -match 'pwsh') {
                                                Start-Process $BuildEXE.FullName -ArgumentList "-NoProfile -NoExit -Command `"`$host.UI.RawUI.WindowTitle = '$Message'`"" -WorkingDirectory $artifactDownloadPath
                                            }
                                            else {
                                                Start-Process $BuildEXE.FullName 
                                            }
                                        }
                                        else {
                                            Start-Process "$artifactDownloadPath/pwsh" -ArgumentList "-NoProfile -NoExit -Command `"`$host.UI.RawUI.WindowTitle = '$Message'`"" -WorkingDirectory $artifactDownloadPath -ErrorAction SilentlyContinue
                                        }
                                    }
                                }
                            }
                            catch {
                                Write-Error "Failed to download artifact $($artifact.name): $_"
                                # Clean up partial download
                                if (Test-Path $zipPath) {
                                    Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
                                }
                            }
                        }
                        else {
                            Write-Warning "Artifact $($artifact.name) from workflow $($run.name) (Run ID: $($run.id)) has already been downloaded - Skipping"
                        }
                    }
                }
            }
        }
    }
}
