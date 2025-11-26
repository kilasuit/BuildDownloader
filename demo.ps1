Import-Module .\src\psmodule-script\BuildDownloader.psm1

## Demo 1 - Get Download links for the core PowerShell/PowerShell build artficats used by the test pipelines ()
$org = 'kilasuit'
$repo = 'BuildDownloader'


gh pr list --repo "$org/$repo" --limit 3
$testPRs = gh pr list --repo "$org/$repo" --json number --limit 3 | ConvertFrom-Json | Select-Object -expand Number

### Note here the CheckName has 2 different values
### the 1st was the autonamed value, the 2nd the renamed one

Foreach ($pr in $testPRs) { Get-GHAzDOPRBuildArtifact -Org $org -Repo $repo -BuildArtifactName helloworld -CheckName kilasuit.BuildDownloader, AzPipeline -PRNumber $PR -OutPath 'C:\tmp\k\bd\' }
