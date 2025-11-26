function Get-GHPRWorkflowChecks {
    <#
    .SYNOPSIS
        Gets GitHub Actions workflow runs for a GitHub PR with retry logic for in-progress workflows
    .DESCRIPTION
        Queries GitHub for workflow runs associated with a PR's latest commit.
        If workflows are in progress, implements backoff and retry logic until 
        workflows complete or timeout is reached.
    .PARAMETER Org
        GitHub organization name
    .PARAMETER Repo
        GitHub repository name
    .PARAMETER PRNumber
        The PR number to query
    .PARAMETER WorkflowName
        The workflow names to filter for (optional)
    .PARAMETER RetryIntervalSeconds
        Seconds to wait between retries when workflows are in progress. Default is 30.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for workflows to complete. Default is 600 (10 minutes).
    .OUTPUTS
        PSCustomObject with workflow run information
    .NOTES
        This is a private helper function used by Get-GHWorkflowBuildArtifact and 
        Get-GHWorkflowBuildArtifactDownloadLink
    #>
    [CmdletBinding()]
    param (
        [Parameter(Mandatory)]
        [string]
        $Org,

        [Parameter(Mandatory)]
        [string]
        $Repo,

        [Parameter(Mandatory)]
        [string]
        $PRNumber,

        [Parameter()]
        [string[]]
        $WorkflowName,

        [Parameter()]
        [int]
        $RetryIntervalSeconds = 30,

        [Parameter()]
        [int]
        $TimeoutSeconds = 600
    )

    if (-not (Get-Command gh -ErrorAction SilentlyContinue)) { 
        throw 'No GH CLI installed, exiting as this is a pre-req' 
    }

    $defuri = "/repos/$Org/$Repo"
    $startTime = Get-Date
    $attempts = 0
    $workflowsComplete = $false

    Write-Verbose "$PRNumber is a PR - Gathering required additional PR metadata"
    $pull = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/pulls/$PRNumber" | ConvertFrom-Json
    
    # Get commits from the PR
    $pullcommits = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" $pull.commits_url | ConvertFrom-Json
    $latestCommitSha = $pullcommits[-1].sha
    $headBranch = $pull.head.ref

    while (-not $workflowsComplete) {
        $attempts++
        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds

        Write-Verbose "Attempt $attempts - Querying workflow runs for branch $headBranch and commit $latestCommitSha"
        
        # Get workflow runs for this PR's head branch and commit
        $workflowRunsResponse = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/actions/runs?head_sha=$latestCommitSha" | ConvertFrom-Json
        $workflowRuns = $workflowRunsResponse.workflow_runs

        # Filter by workflow name if provided
        if ($WorkflowName) {
            $relevantRuns = $workflowRuns | Where-Object { $_.name -in $WorkflowName }
        }
        else {
            $relevantRuns = $workflowRuns
        }

        # Check if any relevant workflows are still in progress
        $inProgressRuns = $relevantRuns | Where-Object { $_.status -ne 'completed' }

        if (-not $inProgressRuns) {
            Write-Verbose "All requested workflows have completed"
            $workflowsComplete = $true
        }
        else {
            $inProgressNames = ($inProgressRuns | Select-Object -ExpandProperty name) -join ', '
            Write-Verbose "Workflows in progress: $inProgressNames. Waiting $RetryIntervalSeconds seconds before retry..."
            Write-Verbose "Elapsed time: $([math]::Round($elapsedSeconds)) seconds of $TimeoutSeconds second timeout"
            
            # Check timeout after the API call to ensure at least one attempt is made
            if ($elapsedSeconds -gt $TimeoutSeconds) {
                Write-Error "Timeout of $TimeoutSeconds seconds exceeded while waiting for workflows to complete for PR $PRNumber"
                return $null
            }
            
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
    }

    # Filter to only include successful/completed runs (not failures, unless user specifically wants them)
    $completedRuns = $relevantRuns | Where-Object { $_.status -eq 'completed' -and $_.conclusion -ne 'cancelled' }

    # Return the workflow data needed by callers
    return [PSCustomObject]@{
        Pull         = $pull
        WorkflowRuns = $completedRuns
        Attempts     = $attempts
        ElapsedTime  = ((Get-Date) - $startTime).TotalSeconds
    }
}
