function Get-PSBuildArtifact {
    [CmdletBinding()]
    [Alias('gpsba')]
    param (
        [Parameter(Mandatory)]
        [int[]]
        $PRNumber,

        [Parameter()]
        [ValidateSet('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux', 'PowerShell-CI-macos-daily', 'PowerShell-CI-Windows-daily', 'PowerShell-CI-linux-daily')] # Replace this with any build names you require for youe
        [string[]]
        $CheckName = @('PowerShell-CI-windows', 'PowerShell-CI-macOS', 'PowerShell-CI-linux'),

        [parameter()]
        [ValidateSet('build', 'Windows', 'macOS', 'Linux')] # Replace this with whatever you need
        [string[]]
        $BuildArtifactName = 'build', # PowerShell builds are using this for the artifact name 

        [Parameter()]
        [string]
        $OutPath = "C:\PS\PR\",
        
        [Parameter()]
        [switch]
        $StartPwsh
    )

    Get-GHAzDOPRBuildArtifact -Org PowerShell -repo PowerShell -PRNumber $PRNumber -CheckName $CheckName -OutPath $OutPath -Start:$StartPwsh -Verbose:$VerbosePreference

}