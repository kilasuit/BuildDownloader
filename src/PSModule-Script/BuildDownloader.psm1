$Here = Split-Path -Parent $MyInvocation.MyCommand.Path
$Public = Get-ChildItem "$here\Public" -Filter '*.ps1' -Recurse 
$Private = Get-ChildItem "$here\Private" -Filter '*.ps1' -Recurse 

foreach($Function in $Public) { . $Function.FullName  }
foreach($Function in $Private) { . $Function.fullname}

Export-ModuleMember -Function $Public.BaseName