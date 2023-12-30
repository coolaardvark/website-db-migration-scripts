<#
.Synopsis
   List all internal or external dependencies by database on a given SQL server.
.DESCRIPTION
   This script takes a server name and scans all non-system databases on it and lists any references to tables outside the current
   database.  The listed depedencies are grouped by database.  It requires a version of server management objects SMO to be installed
   on the machine.
.EXAMPLE
   The following command lists all dependencies on oakridge
   Dump-Dependencies -ServerName oakridge
.Parameter ServerName
   Server is the name of the server you wish to list dependencies on. (mandatory).
.Parameter FilePath
    The path to a file that gets the script output, optional.  If this parameter is missing the output is sent the the console
.Parameter Internal
    Only list dependencies internal to the current database. If missing, both internal and external dependencies are dumped
    can't be used with External
.Parameter External
    Only list dependencies external to the current database. If missing, both internal and external dependencies are dumped
    can't be used with Internal
.Parameter DatabaseList
    Only dump dependencies for the database or databases specified in this parameter (comma seperated list). If missing all
    online database on the spesifed server are dumped
#>

Param(
    [Parameter(Mandatory=$true)]
    [string]$ServerName,
    [Parameter(Mandatory=$false)]
    [string]$FilePath,
    [Parameter(Mandatory=$false)]
    [Switch]$Internal,
    [Parameter(Mandatory=$false)]
    [Switch]$External,
    [Parameter(Mandatory=$false)]
    [string]$DatabaseList
)

if ($External -eq $true -and $Internal -eq $true) {
    Throw "To dump both internal and external depencies don't use ether internal or external switches"
}

[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null

$serverObject = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $ServerName;
if (-not $serverObject.Edition) {
    Throw "Connection to $ServerName failed"
}

$databases = New-Object System.Collections.ArrayList

if ($DatabaseList -eq '') {
    # 1 status = online
    $serverObject.Databases | Where-Object { $_.IsSystemObject -eq $false  -and $_.Status -eq 1 } | ForEach-Object ({
        $databases.Add($_) | Out-Null
    })
}
else {
    foreach ($db in $DatabaseList.Split(',')) {
        $databases.Add($serverObject.Databases.Where({ $_.Name -eq $db })) | Out-Null
    }
}

$allDetails = ''
$queries = New-Object System.Collections.ArrayList

$internalQuery = "SELECT OBJECT_NAME(referencing_id) AS ReferencingObject, 
	    referenced_schema_name + '.' + referenced_entity_name AS ReferencedObject
    FROM sys.sql_expression_dependencies
        WHERE referenced_schema_name IS NOT NULL
        AND referenced_database_name IS NULL"
# We insert a place holder here to stop string format from erroring. For
# internal queries it just adds a comment (makes the script simpler)
$externalQuery = "SELECT OBJECT_NAME(referencing_id) AS ReferencingObject, 
	    referenced_database_name AS ReferencedDatabase,
	    referenced_schema_name + '.' + referenced_entity_name AS ReferencedObject
    FROM sys.sql_expression_dependencies
        WHERE referenced_database_name IS NOT NULL"

$queries = New-Object System.Collections.ArrayList
$refType = ""
if ($External) {
    $queries.Add($externalQuery) | Out-Null
    $refType = "external"
}
elseif ($Internal) {
    $queries.Add($internalQuery) | Out-Null
    $refType = "internal"
}
else {
    $queries.Add($externalQuery) | Out-Null
    $queries.Add($internalQuery) | Out-Null
    $refType = "internal and external"
}

$databases.ForEach({
    $dbName = $_.Name
    $db = $_

    Write-Host "Checking for dependenices in $dbName"
    
    $queries.ForEach({
        $query = $_
        $resultSet = $db.ExecuteWithResults($query)
    
        if ($resultSet.Tables[0].Rows.Count -gt 0) {
            $dbDetails = "=== $($dbName) has $($refType) references ===`r`n"

            $resultSet.Tables[0].Rows | ForEach-Object {
                 $refDbName = ""
                if ($_.ReferencedDatabase -ne $null) {
                    $refDBName = "[$($_.ReferencedDatabase)]."
                }

                $dbDetails += "$($_.ReferencingObject) => $($refDBName)$($_.ReferencedObject)`r`n"
            }

            $allDetails += "`r`n$dbDetails"
        }
    })
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