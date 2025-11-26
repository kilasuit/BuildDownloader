function Get-GHWorkflowBuildArtifactDownloadLink {
    <#
    .SYNOPSIS
        Gets download links for build artifacts from GitHub Actions workflows for a GitHub PR
    .DESCRIPTION
        Queries GitHub for workflow runs associated with a PR and returns download links for specified artifacts.
        Unlike Azure DevOps artifacts, GitHub Actions artifacts require authentication via the gh CLI to download.
    .NOTES
        Requires gh cli tool installed and logged in
        Currently assumes accessing a public GitHub Repo hosted on github.com not one that is hosted on a private self hosted Github Enterprise instance
        
        Gets workflow runs using this Rest API - https://docs.github.com/en/rest/actions/workflow-runs
        Gets artifacts using this Rest API - https://docs.github.com/en/rest/actions/artifacts
    .LINK
        https://docs.github.com/en/rest/actions/artifacts
    .EXAMPLE
        Get-GHWorkflowBuildArtifactDownloadLink -Org microsoft -Repo vscode -PRNumber 12345 -WorkflowName 'CI'
        
        Gets the download links for artifacts from the 'CI' workflow for PR 12345 in the microsoft/vscode repo

    .EXAMPLE
        Get-GHWorkflowBuildArtifactDownloadLink -Org PowerShell -Repo PowerShell -PRNumber 24194 -WorkflowName 'Build' -ArtifactName 'build-output'
        
        Gets the download link for the specific artifact 'build-output' from the 'Build' workflow for PR 24194
    #>
    [CmdletBinding()]
    [Alias('gghwfbadl')]
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
        [int]
        $RetryIntervalSeconds = 30,

        [Parameter()]
        [int]
        $TimeoutSeconds = 600
    )

    begin {
        if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { throw 'No GH CLI installed, exiting as this is a pre-req' }
    }

    process {
        foreach ($PR in $PRNumber) {
            Write-Verbose "Checking if $PR is a PR or not" 
            $PRCheck = gh pr view $PR --repo $Org/$Repo *>&1 
            If ($PRCheck -match 'GraphQL: Could not resolve to a PullRequest with the number of') {
                Write-Error -Message "PRNumber $PR is not a PR - Please Try again with a PR"
                continue
            }
            
            # Get workflow run checks for this PR
            $checkResult = Get-GHPRWorkflowChecks -Org $Org -Repo $Repo -PRNumber $PR -WorkflowName $WorkflowName -RetryIntervalSeconds $RetryIntervalSeconds -TimeoutSeconds $TimeoutSeconds
            if ($null -eq $checkResult) {
                Write-Error "Failed to get workflow checks for PR $PR (timeout or error occurred)"
                continue
            }
            
            $pull = $checkResult.Pull
            $workflowRuns = $checkResult.WorkflowRuns
            
            if (-not $workflowRuns) {
                Write-Error "No workflow runs found for PR $PR"
                continue
            }
            
            Write-Verbose "Found $($workflowRuns.Count) workflow run(s) for PR $PR"
            
            foreach ($run in $workflowRuns) {
                # Get artifacts for this workflow run
                $defuri = "/repos/$Org/$Repo"
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
                
                foreach ($artifact in $artifactList) {
                    [PSCustomObject]@{
                        PRNumber          = $pull.number
                        WorkflowName      = $run.name
                        WorkflowRunId     = $run.id
                        WorkflowConclusion = $run.conclusion
                        ArtifactName      = $artifact.name
                        ArtifactId        = $artifact.id
                        SizeInBytes       = $artifact.size_in_bytes
                        Expired           = $artifact.expired
                        DownloadCommand   = "gh api $defuri/actions/artifacts/$($artifact.id)/zip > $($artifact.name).zip"
                        DownloadURL       = $artifact.archive_download_url
                    }
                }
            }
        }
    }
}
