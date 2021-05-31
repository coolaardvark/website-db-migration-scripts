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
 .PARAMETER SourceServer
    The FQDN of the server containing SiteNme
 .PARAMETER DestinationServer
    The FQDN of the server you want to migrate the SiteName on to, optional, if not provided defaults to localhost
 .EXAMPLE
    Migrate-WebSite -SourceServer raptor.aardman.com -DestinationServer ghost.aardman.com -SiteName adobeccdb
 #>

Param (
    [Parameter(Mandatory = $true)]
    [string] $SourceServer,
    [Parameter(Mandatory = $false)]
    [string] $DestinationServer,
    [Parameter(Mandatory = $true)]
    [string] $SiteName
)

Set-StrictMode -Version Latest
Import-Module WebAdministration
Add-PSSnapin WDeploySnapin3.0

try {
   if (-not $DestinationServer) {
      $DestinationServer = 'localhost'
   }

   # Are we running as admin?
   if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
      Throw 'You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!'
   }

   $windowsCredential = Get-Credential
   $sourcePubSettings = New-WDPublishSettings -Credentials $windowsCredential -Site $SiteName -ComputerName $SourceServer -AgentType 'MSDepSvc'
   $destinationPubSettings = New-WDPublishSettings -Credentials $windowsCredential -Site $SiteName -ComputerName $DestinationServer -AgentType 'MSDepSvc'

   Sync-WDSite -SourcePublishSettings $sourcePubSettings -DestinationPublishSettings $destinationPubSettings -SitePhysicalPath 'd:\Websites\' -IncludeAppPool
}
Catch {
   Write-Error "Sync failed with the following error `n $_"
   Write-Error "Stack trace: $($_.ScriptStackTrace)"  
}