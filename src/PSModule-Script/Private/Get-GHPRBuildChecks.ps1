function Get-GHPRBuildChecks {
    <#
    .SYNOPSIS
        Gets build checks for a GitHub PR with retry logic for in-progress builds
    .DESCRIPTION
        Queries GitHub for check runs associated with a PR's latest commit.
        If builds are in progress, implements backoff and retry logic until 
        builds complete or timeout is reached.
    .PARAMETER Org
        GitHub organization name
    .PARAMETER Repo
        GitHub repository name
    .PARAMETER PRNumber
        The PR number to query
    .PARAMETER CheckName
        The check names to filter for
    .PARAMETER RetryIntervalSeconds
        Seconds to wait between retries when builds are in progress. Default is 30.
    .PARAMETER TimeoutSeconds
        Maximum seconds to wait for builds to complete. Default is 600 (10 minutes).
    .OUTPUTS
        PSCustomObject with check run information
    .NOTES
        This is a private helper function used by Get-GHAzDOPRBuildArtifact and 
        Get-GHPRAzDOBuildArtifactDownloadLink
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
        $CheckName,

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
    $buildsComplete = $false

    Write-Verbose "$PRNumber is a PR - Gathering required additional PR metadata"
    $pull = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/pulls/$PRNumber" | ConvertFrom-Json
    # $pull has commits_url property we can use to grab all the commits from
    $pullcommits = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" $pull.commits_url | ConvertFrom-Json
    $latestCommitSha = $pullcommits[-1].sha

    while (-not $buildsComplete) {
        $attempts++
        $elapsedSeconds = ((Get-Date) - $startTime).TotalSeconds

        Write-Verbose "Attempt $attempts - Querying check runs for commit $latestCommitSha"
        $pullchecks = gh api -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28" "$defuri/commits/$latestCommitSha/check-runs" | ConvertFrom-Json

        # Filter checks based on CheckName if provided
        if ($CheckName) {
            $relevantChecks = $pullchecks.check_runs | Where-Object { $_.name -in $CheckName }
        }
        else {
            $relevantChecks = $pullchecks.check_runs
        }

        # Check if any relevant builds are still in progress
        $inProgressChecks = $relevantChecks | Where-Object { $_.status -ne 'completed' }

        if (-not $inProgressChecks) {
            Write-Verbose "All requested builds have completed"
            $buildsComplete = $true
        }
        else {
            $inProgressNames = ($inProgressChecks | Select-Object -ExpandProperty name) -join ', '
            Write-Verbose "Builds in progress: $inProgressNames. Waiting $RetryIntervalSeconds seconds before retry..."
            Write-Verbose "Elapsed time: $([math]::Round($elapsedSeconds)) seconds of $TimeoutSeconds second timeout"
            
            # Check timeout after the API call to ensure at least one attempt is made
            if ($elapsedSeconds -gt $TimeoutSeconds) {
                Write-Error "Timeout of $TimeoutSeconds seconds exceeded while waiting for builds to complete for PR $PRNumber"
                return $null
            }
            
            Start-Sleep -Seconds $RetryIntervalSeconds
        }
    }

    # Return the check data needed by callers
    return [PSCustomObject]@{
        Pull        = $pull
        PullChecks  = $pullchecks
        Attempts    = $attempts
        ElapsedTime = ((Get-Date) - $startTime).TotalSeconds
    }
}
