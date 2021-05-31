<#
.Synopsis
    Sets up passwords for SQL users on server
.DESCRIPTION
    Takes a CSV file with username and password columns and sets the passwords for SQL users found on the given server
.EXAMPLE
    The following command sets passwords for SQL users found on oakridge that are listed in the c:\users.csv file
    Set-SQLPasswords -ServerName oakridge -UserFile c:\users.csv
.Parameter ServerName
    The server you want to set the SQL user passwords on. Required
.Parameter UserFile
    A path to the csv containing username password pairs, there should be only 2 colums with a header row, the columns
    should be username and password (case insensative) and the order is not important.  The seperator is a comma.
    Required
.OUTPUTS
   none
#>

Param (
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    [Parameter(Mandatory = $true)]
    [string]$UserFile
)

Set-StrictMode -Version Latest

try {
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null
    $serverObject = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $ServerName;
    
    if (-not $serverObject.Edition) {
        Throw "Connection to $ServerName failed"
    }
    if (-not (Test-Path -Path $UserFile)) {
        Throw "$UserFile not found"
    }

    $masterDB = $serverObject.Databases['master']
    $usersAndPasswords = Import-Csv -Delimiter ',' -Path $UserFile

    Write-Host "Setting SQL login passwords on $ServerName"
    $usersAndPasswords | ForEach-Object ({
        if ($serverObject.Logins[$_.Username]) {
            # Only attempt to set SQL Login passwords (we can't do windows ones anyway!)
            if ($serverObject.Logins[$_.Username].LoginType -eq 'SqlLogin') {
                $masterDB.ExecuteNonQuery("ALTER LOGIN $($_.Username) WITH PASSWORD = '$($_.Password)';")

                Write-Host "Password set for SQL login $($_.Username)"
            }
            else {
                Write-Host "Skipping Windows user $($_.Username)"
            }
        }
        else {
            Write-Host "SQL Login $($_.Username) not found, skipping"
        }
    })
}
Catch {
    Write-Error "Failed with error $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"  
}