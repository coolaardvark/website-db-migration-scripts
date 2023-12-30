<#
.Parameter ServerName
    The Server you want to dump users from
.Parameter OutPath
    The path (no trailing slash please) the logins.txt will be saved to
#>

Param(
    [Parameter(Mandatory = $true)]
    [string] $ServerName,
    [Parameter(Mandatory = $true)]
    [string] $OutPath
)

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null
$serverObject = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $ServerName
if (-not $serverObject.Edition) {
    Throw "Connection to $ServerName failed"
}

$logins = ''

$serverObject.Logins | ForEach-Object({
    $loginName = $_.Name
    $loginType = $_.LoginType

    if ($loginType -eq 'SqlLogin' -and (-not $loginName.StartsWith('##')) -and $loginName -ne 'sa') {
        $logins += "$loginName`r`n"
    } 
})

$logins | Out-File "$OutPath\logins.txt"