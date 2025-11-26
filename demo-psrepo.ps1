Import-Module .\src\psmodule-script\BuildDownloader.psm1

## Demo 1 - Get Download links for the core PowerShell/PowerShell build artficats used by the test pipelines ()

gh pr list --repo PowerShell/PowerShell --limit 3
$testPRs = gh pr list --repo PowerShell/PowerShell --json number --limit 3 | ConvertFrom-Json | Select-Object -expand Number
$g  
Get-GHPRAzDOBuildArtifactDownloadLink -PRNumber $testPRs -CheckName PowerShell-CI-windows 

$testPRs | Get-GHPRAzDOBuildArtifactDownloadLink

gh pr list --repo PowerShell/PowerShell --json number --limit 3 | ConvertFrom-Json 


gh pr list --repo PowerShell/PowerShell --json number --limit 3 | ConvertFrom-Json | Select-Object @{name = 'PRNumber' ; e = { $_.Number } } -First 3 | Get-GHPRAzDOBuildArtifactDownloadLink 

Get-GHPRAzDOBuildArtifactDownloadLink -Org PowerShell -Repo PowerShell -PRNumber 24192 -CheckName PowerShell-CI-* #Fail

# CheckName TabCompletion 
Get-GHPRAzDOBuildArtifactDownloadLink -Org PowerShell -Repo PowerShell -PRNumber 24192 -CheckName PowerShell-CI-*



# Demo 2 -- Download and run an instance of 1/more build artifacts (using defaults)

$testPRs | Get-GHAzDOPRBuildArtifact -Start

# Old PR (Build may not)
Get-GHAzDOPRBuildArtifact -Org PowerShell -Repo PowerShell -CheckName PowerShell-CI-windows -PRNumber 24115 -Start -BuildArtifactName build -Verbose



Get-PSBuildArtifact -PRNumber 23905, 24204, 24173 -CheckName PowerShell-CI-windows -StartPwsh