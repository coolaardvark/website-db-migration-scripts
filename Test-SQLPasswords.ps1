<#
.Synopsis
    Tests imported users against the csv sheet used to set the passwords.
.DESCRIPTION
    Takes a CSV file with username and password columns and sets tests both that the users have imported correctly
    and that security policies on the new server don't require password changes or an increase in password
    complexity
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
Import-Module SqlServer

try {
    if (-not (Test-Path -Path $UserFile)) {
        Throw "$UserFile not found"
    }

    $usersAndPasswords = Import-Csv -Delimiter ',' -Path $UserFile

    Write-Host "Testing SQL login passwords on $ServerName"
    $usersAndPasswords | ForEach-Object ({
        $connectionString = 'Data Source={0};Initial Catalog={1};User ID={2};Password={3}' -f $ServerName, $_.Database, $_.Username, $_.Password

        $loginGood  = $false

        try {
            $sqlConnection = New-Object System.Data.SqlClient.SqlConnection $connectionString
            $sqlConnection.Open()

            $loginGood = $true
        }
        catch {
            # Ignore the error, apprently I need a catch even if it does nothing?
        }
        finally {
            $sqlConnection.Close();
        }

        if ($loginGood) {
            Write-Host "Login suceeded for $($_.Username)"
        }
        else {
            Write-Host "Login failed for $($_.Username)"
        } 
    })
}
Catch {
    Write-Error "Failed with error $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"  
}