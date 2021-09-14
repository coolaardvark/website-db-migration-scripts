<#
.Synopsis
   List all external dependencies by database on a given SQL server.
.DESCRIPTION
   This script takes a server name and scans all non-system databases on it and lists any references to tables outside the current
   database.  The listed depedencies are grouped by database.  It requires a version of server management objects SMO to be installed
   on the machine.
.EXAMPLE
   The following command lists all dependencies on server2
   Dump-Dependencies -ServerName server2
.Parameter ServerName
   Server is the name of the server you wish to list dependencies on. (mandatory).
.Parameter FilePath
    The path to a file that gets the script output, optional.  If this parameter is missing the output is sent the the console
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$ServerName,
    [Parameter(Mandatory=$false)]
    [string]$FilePath
)

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null

$serverObject = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $ServerName;
if (-not $serverObject.Edition) {
    Throw "Connection to $ServerName failed"
}

$allDetails = ''
$serverObject.Databases | Where-Object { $_.IsSystemObject -eq $false } | ForEach-Object ({
    $dbName = $_.Name

    Write-Host "Checking for dependenices in $dbName"
    $resultSet = $_.ExecuteWithResults("SELECT OBJECT_NAME(referencing_id) AS ReferencingObject, 
	    referenced_database_name AS ReferencedDatabase,
	    referenced_schema_name + '.' + referenced_entity_name AS ReferencedObject
    FROM sys.sql_expression_dependencies
        WHERE referenced_database_name IS NOT NULL 
            AND referenced_database_name <> '$dbName'")
    
    if ($resultSet.Tables[0].Rows.Count -gt 0) {
        $dbDetails = "=== $($dbName) has external references ===`r`n"
        $resultSet.Tables[0].Rows | ForEach-Object { 
            $dbDetails += "$($_.ReferencingObject) => [$($_.ReferencedDatabase)].$($_.ReferencedObject)`r`n"
        }

        $allDetails += "`r`n$dbDetails"
    }
})

if ($FilePath -ne '') {
    if (Test-Path -Path $FilePath) { 
        Remove-Item -Path $FilePath
    }

    $allDetails | Out-File -FilePath $FilePath 
}
else {
    Write-Host $allDetails
}