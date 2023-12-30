<#
 .SYNOPSIS
    Migrates web site and settings from one server to another
 .DESCRIPTION
    Takes the SiteName on SourceServer and copies it to the DestinationServer.
    Needs to be run as a user with admin rights on the source server.  Uses the MSDepSvc service
    and web deploy to handle the migration.  You will be promted for your windows credientals 
    when running this command
 .PARAMETER SiteName
    The sites name as presented in the ISS management plugin on the SourceServer.
 .PARAMETER SiteUrl
    The full ULR of the site, if not provided https://<SiteName>.aardman.com is assumed
 .PARAMETER SourceServer
    The FQDN of the server containing SiteNme
 .PARAMETER DestinationServer
    The FQDN of the server you want to migrate the SiteName on to, optional, if not provided defaults to localhost
 .PARAMETER DestinationRootPath
    The root path on the destination server for web site folders e.g D:/websites/
 .EXAMPLE
    Migrate-WebSite -SourceServer raptor.aardman.com -DestinationServer ghost.aardman.com -SiteName adobeccdb
 #>

[CmdletBinding()]  
Param ( 
    [Parameter(Mandatory = $true)][string] $SourceServer,
    [Parameter(Mandatory = $true)][string] $ServerRootPath,
    [Parameter(Mandatory = $true)][string] $SiteName,
    [Parameter(Mandatory = $false)][string] $DestinationServer,
    [Parameter(Mandatory = $false)][string] $SiteUrl
)

Set-StrictMode -Version Latest
Import-Module WebAdministration
Add-PSSnapin WDeploySnapin3.0

$sourceSettingsFile = ''
$destinationSettingsFile = ''

try {
    # Set default values for non mandatory parameters
    if (-not $DestinationServer) {
        $DestinationServer = 'localhost'
    }

    if (-not $SiteUrl) {
        $SiteUrl = 'https://' + $SiteName + '.aardman.com'
    }

    if (-not $ServerRootPath.EndsWith('\')) {
        $ServerRootPath += '\'
    }

   # Are we running as admin?
   if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
      Throw "You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!"
   }

   # Set up credential and config objects
   Write-host '*** Enter credentials for source server ***'
   $sourceCredentials = Get-Credential -Message 'Source server credentials'
   Write-Host '*** Enter credentials for destination server ***'
   $destinationCredentials = Get-Credential -Message 'Destination server credentials'

   $configDirectory = (Get-Location -PSProvider 'FileSystem').Path
   $sourceSettingsFile = $configDirectory + '\source.publishsettings'
   $destinationSettingsFile = $configDirectory + '\destination.publishsettings'

   New-WDPublishSettings -Credentials $sourceCredentials -Site $SiteName -SiteUrl $SiteUrl -ComputerName $SourceServer -AgentType MSDepSvc -EncryptPassword -FileName $sourceSettingsFile
   New-WDPublishSettings -Credentials $destinationCredentials -Site $SiteName -SiteUrl $SiteUrl -ComputerName $DestinationServer -AgentType MSDepSvc -EncryptPassword -FileName $destinationSettingsFile

   # Sync site!
   Sync-WDSite $SiteName $SiteName -SourcePublishSettings $sourceSettingsFile -DestinationPublishSettings $destinationSettingsFile -SitePhysicalPath "$ServerRootPath$SiteName" -IncludeAppPool
}
Catch {
   Write-Error "Sync failed with the following error `n $_"
   Write-Error "Stack trace: $($_.ScriptStackTrace)"  
}
finally {
    # Even with encryped passwords, I don't want these left laying around!
    if (($sourceSettingsFile -ne '') -and ((Test-Path -Path $sourceSettingsFile) -eq $true)) {
        Remove-Item -Path $sourceSettingsFile
    }
    if (($destinationSettingsFile -ne '') -and ((Test-Path -Path $destinationSettingsFile) -eq $true)) {
        Remove-Item -Path $destinationSettingsFile
    }
}