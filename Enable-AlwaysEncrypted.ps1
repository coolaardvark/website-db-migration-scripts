<#
.Synopsis
    Sets up the specified database with Always Encrypted columns
.DESCRIPTION
    Handles all tasks relating to setting up always encrypted for the given database.
    It creates the certificates, sets up the column encryption and finally exports the 
    certificate ready for importing on the client server. 
.EXAMPLE
    The following exmaple overides the default settings for a typical dev set up
    Enable-AlwaysEncrypted -CertStore 'LocalMachine' -DBPrefix 'DEV' -DBServer 'dbserver' -DBName 'dbname' -RandEncryptColumns 'schema.table.column, schema.table.column'
.Parameter CertStore
    The store in which to store the generated certificate, valid values are LocalMachine and CurrentUser.
    This not only sets the path where the certificate is stored locally, but also 'bakes' this path in
    to the database encryption it's self, so you need to pick the path correct for the the final useage
    of the database (a live or dev enviroment) rather that just where you want the certificate to end up
    If LocalMachine is spesified you need to run the script with admin rights and this checked before
    doing anything.
.Parameter CertName
    An optional name for an existing certificate. If this is provided the script will attempt to use this
    for encrypting the column master keys. The certificate is searched for in store indicated by the
    CertStore parameter. The name given here is checked against first the subject (which is
    in x400 notation, so CN=<certName>, this command checks for this prefix and adds it if needed), 
    friendly name of the certificate and then finally the thumbprint. 
    If this parameter is provided the certificate will, not by default, be exported if you want this
    anyway use the -ExportCert switch.
.Parameter ExportCert
    A switch to force the export of an existing certificate if provided (the CertName parameter). Ignored 
    if the  the script generates it's own certificate (if the CertName parameter is not provided). 
    Note failure to export a certifcate will cause prevent the encryption process from starting. 
.Parameter DBServer
    The server running the database, required, assumed to be in the aardman.com domain, the database
    connection will be attempted with integrated security as the user running the script.
.Parameter DBName
    The name of the database to get encrypted columns, required if DBServer is provided.
.Parameter ConnectionString
    If provided this is used in place of the DBServer and DNName parameters (and they are ignored).
    Useful if you need to use a different method of authentication from integrated used with
    DBServer and DBName.
.Parameter AccessUsers
    A commad seperated list of domain users that will be given access to the exported certificate. Users 
    are assumed to be in the aardman.com domain. Required if CertName parameter is not provided or if
    if it is and the -ExportCert switch is used
.Parameter KeySuffix
    The suffix added to the names of the column master key (CMK) and column encryption key (CEK)
    to ensure uniqueness, required
.Parameter RandEncryptColumns
    An optional coma sperated list of column names that are to get the stronger randomized encryption. 
    This would be used for columns that you don't want to query on. The column name must use 
    dotted 3 part names, so <schema name>.<table name>.<column name>. While this is an optional column, 
    you must have at least this parameter or DetermEncryptColumn or likely both
.Parameter DetermEncryptColumns
    An optional list of column names that are to get the weaker deterministic encryption. This would
    be used for columns that you want to query on. The column name must use dotted 3 part
    names, so <schema name>.<table name>.<column name>. While this is an optional column, 
    you must have at least this parameter or RandEncryptColumn or likely both
#>

Param (
    [Parameter(Mandatory)]
    [string]$CertStore,
    [string]$CertName,
    [switch]$ExportCert,
    [string]$AccessUsers,
    [string]$DBServer,
    [string]$DBName,
    [string]$ConnectionString,
    [Parameter(Mandatory)]
    [string]$KeySuffix,
    [string]$RandEncryptColumns,
    [string]$DetermEncryptColumns
)

# Set up
Set-StrictMode -Version Latest
Import-Module SqlServer

# Check parameters
if ($CertStore -ne 'LocalMachine' -and $CertStore -ne 'CurrentUser') {
    throw "CertStore parameter must be set to either 'LocalMachine' or 'CurrentUser'"    
}
if ($CertStore -eq 'LocalMachine') {
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        throw "You require Administrator rights to run this script on a non-dev database!`nPlease re-run this script as an Administrator"
    }
}
if ($RandEncryptColumns -eq $null -and $DetermEncryptColumns -eq $null) {
    throw "You must specify at least one of either RandEncryptColumns or DetermEncryptColumns.`nLikely you will want to use both"
}

if (($DBName -eq '' -or $DBServer -eq '') -and $ConnectionString -eq '') {
    throw 'You need to provide DBName and DNServer parametes or ConnectionString parameter!'
}

function getCertifcate {
    param(
        [Parameter(Mandatory)]
        [string]$certStore,
        [Parameter(Mandatory)]
        [string]$certName
    )
 
    $cert = $null

    $searchFields = 'subject', 'friendlyname', 'thumbprint'

    $certPath = "Cert:\$certStore\My"
    Write-Host "Looking for $certName in $certPath"

    # The subject name is in X400 format so needs a CN= prefix, add this
    # if not present
    if (-not ($certName.StartsWith('CN='))) {
        $certName = "CN=$certName"
    }

    foreach ($field in $searchFields) {
        Write-Host "Looking at $field"

        $cert = (Get-ChildItem $certPath | Where-Object $field -eq $certName)
        if ($null -ne $cert) {
            break
        } 

        # remove our prefix after searching by subject
        if ($field -eq 'subject' -and $certName.StartsWith('CN=')) {
            $certName = $certName.Substring(3)
        }
    }

    # We will might not have a certificate
    if ($null -eq $cert) {
        throw "The string $certName not found in any of subject, friendly name or thumbprint or any certifcate in $certStore"
    }

    Write-Host "Certificate thumbprint $($cert.Thumbprint)"

    $cert
}

function createCertificate {
    param (
        [Parameter(Mandatory)]
        [string]$certStore,
        [Parameter(Mandatory)]
        [string]$dbName,
        [Parameter(Mandatory)]
        [string]$keySuffix
    )

    # It doesn't matter that certificate names aren't unique, but it makes sense from a
    # person point of view to use the key suffix to make names different 
    $masterKeyDNSName = "CN=$dbName $keySuffix Always Encrypted"
    $masterKeyCertStore = "Cert:\$certStore\My\"

    # Set up certificate
    Write-Host "Creating Self Signed Certificate $masterKeyDNSName"
    $cert = New-SelfSignedCertificate -Subject $masterKeyDNSName -CertStoreLocation $masterKeyCertStore -KeyExportPolicy Exportable -Type DocumentEncryptionCert -KeyUsage DataEncipherment -KeySpec KeyExchange -KeyLength 2048
    Write-Host "Column Master Key Certificate Path: $masterKeyCertStore$($cert.ThumbPrint)"

    $cert
}

function exportCertificate {
    param (
        [Parameter(Mandatory)]
        [string]$dbName,
        [Parameter(Mandatory)]
        [string]$certPath,
        [Parameter(Mandatory)]
        [string]$accessUsers,
        [Parameter(Mandatory)]
        [string]$keySuffix
    )

    $accessUserList = @()
    $accessUsers.Split(',') | ForEach-Object {
        $accessUserList += "AARDMAN\$($_.Trim())"
    }

    Write-Host 'Exporting certificate'
    # include key suffix as well to ensure uniquness in file names
    $exportCertPath = Join-Path $scriptPath "$dbName-$keySuffix-ae.pfx"

    Export-PfxCertificate -Cert $certPath -FilePath $exportCertPath -ProtectTo $accessUserList -ErrorAction Stop
    Write-Host "Certificate exported to $exportCertPath"
}

# Get everything set up
$scriptPath = & { Split-Path $MyInvocation.ScriptName }

$certificate = $null
$export = $false

$conString = ''
if ($ConnectionString -ne '') {
    $conString = $ConnectionString
    
    # We still need to break out the database name for various tasks below
    # Could do this with regular expressions, but...garah regualr expressions!
    foreach ($part in $ConnectionString.Split(';')) {
        if ($part.ToLower().StartsWith('database')) {
            $DBName = $part.Substring(9)
            break
        }
    }
}
else {
    $conString = "Server=$DBServer.aardman.com;Database=$DBName;Trusted_Connection=true"
}

# Lets get to it
if ($CertName -ne '') {
    $certificate = getCertifcate -CertStore $CertStore -CertName $CertName

    if ($ExportCert) {
        # We need a AccessUsers for any export
        if ($AccessUsers -eq '') {
            throw "You need to provide a list of users if you want to export the certificate"
        }

        $export = $true
    }
}
else {
    # We need a AccessUsers for any export
    # Yes this block is duplicated above, but there is no neat way not do this!
    if ($AccessUsers -eq '') {
        throw "You need to provide a list of users if you want to export the certificate"
    }

    # We always export newly created certificates
    $export = $true

    $certificate = createCertificate -CertStore $CertStore -DBName $DBName -KeySuffix $KeySuffix
} 

# We can't get to this point without a certificate, so no need to check
$certThumbprint = $certificate.Thumbprint
if ($export) {
    exportCertificate -DBName $DBName -CertPath "Cert:\$CertStore\My\$certThumbprint" -AccessUsers $AccessUsers -KeySuffix $KeySuffix
}

$RandEncryptColumnList = @()
$DetermEncryptColumnList = @()

if ($RandEncryptColumns -ne '') {
    foreach ($col in $RandEncryptColumns.Split(',')) {
        $RandEncryptColumnList += $col.Trim()
    }
}   

if ($DetermEncryptColumns -ne '') {
    foreach ($col in $DetermEncryptColumns.Split(',')) {
        $DetermEncryptColumnList += $col.Trim()
    }   
}

# use private key to generate column master and encryption keys
$database = Get-SqlDatabase -ConnectionString $conString
$cmkSettings = New-SqlCertificateStoreColumnMasterKeySettings -CertificateStoreLocation $CertStore -Thumbprint $certThumbprint

$columnMasterKeyName = "CMK_$KeySuffix"
$columnEncryptionKeyName = "CEK_$KeySuffix"
New-SqlColumnMasterKey -InputObject $database -Name $columnMasterKeyName -ColumnMasterKeySettings $cmkSettings
New-SqlColumnEncryptionKey -InputObject $database -ColumnMasterKey $columnMasterKeyName -Name $columnEncryptionKeyName

# Change encryption schema
$encryptionChanges = @()

if ($RandEncryptColumnList.Length -gt 0) {
    foreach($column in $RandEncryptColumnList) {
        Write-Host "Adding Randomized encryption to column $column"
        $encryptionChanges += New-SqlColumnEncryptionSettings -ColumnName $column -EncryptionType Randomized -EncryptionKey $columnEncryptionKeyName
    }
}

if ($DetermEncryptColumnList.Length -gt 0) {
    foreach($column in $DetermEncryptColumnList) {
        Write-Host "Adding Deterministic encryption to column $column"
        $encryptionChanges += New-SqlColumnEncryptionSettings -ColumnName $column -EncryptionType Deterministic -EncryptionKey $columnEncryptionKeyName
    }
}

Write-Host 'Applying changes to database'
Set-SqlColumnEncryption -InputObject $database -ColumnEncryptionSettings $encryptionChanges -LogFileDirectory $scriptPath

# So this command can been chained together in a script and use different column encryption certificates with the 
# same master encryption certificate, return the newly created certificate thumbprint, the next script 
# in line can use this for it's CertName parameter 
if ($CertName -eq '') {
    Write-Output $certThumbprint
}