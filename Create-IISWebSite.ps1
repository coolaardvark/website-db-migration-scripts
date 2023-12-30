<#
 .SYNOPSIS
     .
 .DESCRIPTION
     Creates a web site in ISS.  The script must be run with admin rights.
 .PARAMETER SiteName
     The sites name, will also be used as the hostname if SiteAlais is not set.
 .PARAMETER LiveEnv
    A switch, sets the publishing 'environment' to live, you must pass 1 
    and only 1 of these env parameters.
 .PARAMETER DevEnv
    A switch, sets the publishing 'environment' to dev, you must pass 1 
    and only 1 of these env parameters.
 .PARAMETER StagingEnv
    A switch, sets the publishing 'environment' to staging, you must pass 1 
    and only 1 of these env parameters.
 .PARAMETER SiteAlais
    The Hostname the new web site will respond to.  Optional, if this is not
    passed, the sitename will be used.  If the name is not a full domain name
    the .aardman.com sufix will be added.
 .PARAMETER AppPoolUser
     The username the app pool for this site will run as.  If not spesified
     the default app pool user will be used.
 .PARAMETER AppPoolPassword
     The password for the app pool user, required if the AppPoolUser is
     spesifed.  Shown in clear text if typed on command line.
 .PARAMETER BaseSitePath
     The root of path in the file system for the web site, the the default
     value of C:\Websites will be used if not spesified.  The web site will
     get a folder named for it inside this folder.
 .PARAMETER CertThumbprint
     The thumbprint of the certificate used, defaults to the certificate from
     the JSON config file certificate if not spesified.  Required if you are 
     cerating active on port 443, which is the default action (see NoSSL 
     switch below).
 .PARAMETER NoSSL
     If this switch is present, only port 80 will be bound for the site, otherwise
     a binding for 443 will be set up as well.
 .PARAMETER NoDNS
     If this swtich is present, we don't attempt to add the DNS record for the
     site name.
     
 .EXAMPLE
     Create-IISWebSite -SiteName testsite -NoSSL -DevEnv

     Will create a site that responds to testsite.dev.aardman.com runs as the default
     app pool user and is only accesible on port 80. The site will be published to
     the dev server (as set by the Create-ISSWebSite.json file)

     Create-IISWebSite -SiteName newtest -SiteAlias testing2 -LiveEnv

     Will create a site that responds to newtest.test.com runs as the dedault
     app pool user and is accesible on both port 80 and 443, SSL will use the
     the certificate from the JSON config file if installed.
 
 .NOTES
     Author: Mark Keightley
     Date:   2020-12-17   
 #>

Param(
    [Parameter(Mandatory = $True)]
    [string]$SiteName,
    [Parameter(Mandatory = $False)]
    [switch]$LiveEnv,
    [Parameter(Mandatory = $False)]
    [switch]$DevEnv,
    [Parameter(Mandatory = $False)]
    [switch]$StagingEnv,
    [Parameter(Mandatory = $False)]
    [string]$HostHeader,
    [Parameter(Mandatory = $False)]
    [string]$SiteAppPool,
    [Parameter(Mandatory = $False)]
    [string]$AppPoolUser,
    [Parameter(Mandatory = $False)]
    [string]$AppPoolPassword,
    [Parameter(Mandatory = $False)]
    [string]$BaseSitePath,
    [Parameter(Mandatory = $False)]
    [string]$CertThumbprint,
    [Parameter(Mandatory = $False)]
    [switch]$NoSSL,
    [Parameter(Mandatory = $False)]
    [switch]$NoDNS
)

Set-StrictMode -Version Latest

# Need to do this check before even attempting to load the WebAdminstration module!
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Throw "You do not have Administrator rights to run this script`nPlease re-run this script as an Administrator!"
}

function Get-Config {
    $ConfigPath = & { Split-Path $MyInvocation.ScriptName }
    $ConfigFile = Join-Path $ConfigPath '.\Create-IISWebSite.json'
    Get-Content $ConfigFile | ConvertFrom-Json
}

function Add-SiteDNS {
    param ($HostName, $HostServer)

    Wirte-Host "Creating DNS record for $HostName"

    # Check that we have these modules here since creating the DNS entry
    # is optional
    Import-Module DnsServer -ErrorAction Stop
    Import-Module DnsClient -ErrorAction Stop

    # First get our DNS servers (only bother looking for the first one, if that is
    # down it is likely we have bigger problems than publishing a web site!)
    $dnsServer = (Get-DnsClientServerAddress).ServerAddresses[0];
    if ($dnsServer -eq $null) {
        Throw 'Unable to determine DNS server address!'
    }

    $newSiteAddress = (Resolve-DnsName $HostHeader).IPAddress

    # The section below is commented out because of the way our internal
    # DNS is set up, it's highly likely you wont need this, but I've left
    # it here just in case
    ##START block
    # Check if the name already exists, however we have a little problem here
    # our internal DNS is set up to resolve any unknown name to the address
    # of the external site so...
    #$externalSiteAddress = (Resolve-DnsName "domain.com").IPAddress
    #if ($newSiteAddress -eq $externalSiteAddress) {
        # No record exsists so create it
    #    Add-DnsServerResourceRecord -CName -Name $HostName -HostNameAlias $HostServer -ZoneName "domain.com" -ComputerName $dnsServer | Out-Null
    #    Write-Host "DNS record for $HostName created" 
    #}
    #else {
    #    Write-Host "DNS record for $HostName already exists"
    #}
    ##END block

    # This is the code you are likely to need to check for existing hostnames
    # If the above block is uncommented, then this needs to be commented out
    if ($newSiteAddress -eq $null) {
        # No record exsists so create it
        Add-DnsServerResourceRecord -CName -Name $HostName -HostNameAlias $HostServer -ZoneName "domain.com" -ComputerName $dnsServer | Out-Null
        Write-Host "DNS record for $HostName created" 
    }
    else {
        Write-Host "DNS record for $HostName already exists"
    }
}

function Add-SiteAppPool {
    param ($AppPoolName, $AppPoolUser, $AppPoolPassword)

    Write-Host "Creating App pool $AppPoolName"
    $appPool = New-WebAppPool -Name $AppPoolName

    if (-not $appPool) {
        Throw "Failed to create app pool $AppPoolName"
    }

    if ($AppPoolUser) {
        Write-Host "Assigning App Pool user $AppPoolUser"
        $appPool.processModel.username = [string]($AppPoolUser)
        $appPool.processModel.password = [string]($AppPoolPassword)
        $appPool.processModel.identityType = 'SpecificUser'
        
        $appPool | Set-Item
    }
}

function Add-Site {
    param ($SiteName, $SitePath, $SiteAppPool, $HostHeader, $SecureSite)

    $createMessage = "Creating site $SiteName in $SitePath using app pool $SiteAppPool"
    if ($HostHeader -ne $SiteName) {
        $createMessage += " (the site responds to $HostHeader)"
    }
    if (-not $SecureSite) {
        $createMessage += " with no SSL configured"
    }
    Write-Host $createMessage

    if (-not (New-Website -Name $SiteName -PhysicalPath $SitePath -ApplicationPool $SiteAppPool -HostHeader $HostHeader -Port 80)) {
        Throw 'Failed to create web site'
    }
    if ($SecureSite) {
        Write-Host 'Binding SSL port'

        New-WebBinding -Name $SiteName -IPAddress * -Port 443 -Protocol https -HostHeader $HostHeader

        # Certficate binding is by port, not site, so the code below will
        # only trigger on the first binding to 443 on this machine
        if (-not (Test-Path ('IIS:\SSLBindings\0.0.0.0!443'))) {
            Write-Host 'No certificate bound, attempting bind'

            Get-Item "Cert:\LocalMachine\my\$CertThumbprint" | New-Item 'IIS:\SSLBindings\0.0.0.0!443'
        }
    }
}

try {
    # Loading of this module is not optional
    Import-Module WebAdministration -ErrorAction Stop

    $ConfigObject = Get-Config

    Write-Host "Setting up site $SiteName"

    # Parse parameters
    $Environment = ''
    $Server = ''

    # We need one and only one of the env switches to be set
    $EnvCount = 0

    if ($LiveEnv) {
        $EnvCount ++
        $Environment = 'live'
        $Server = $ConfigObject.LiveServer
    }
    elseif ($DevEnv) {
        $EnvCount ++
        $Environment = 'dev'
        $Server = $ConfigObject.DevServer
    }
    elseif ($StagingEnv) {
        $EnvCount ++
        $Environment = 'staging'
        $Server = $ConfigObject.StagingServer
    }

    if ($EnvCount -eq 0) {
        Throw 'You *must* pass one of the environment switches (-LiveEnv, -DevEnv or -StagingEnv)'
    }
    if ($EnvCount -gt 1) {
        Throw 'You can *only* pass one of the environment switches (-LiveEnv, -DevEnv or -StagingEnv)'
    }

    if ($AppPoolUser -and !$AppPoolPassword) {
        Throw "The user $AppPoolUser needs a password!"
    }

    # Set host header up, we have permutations to deal with
    # using default name or setting one and with the
    # enviroment plus we need the host name and environment 
    # on their own (no domain name) for DNS set up
    if (-not $HostHeader) {
        # The live environment has no sufix of course
        if ($LiveEnv) {
            $HostHeader = $SiteName
        }
        else {
            $HostHeader = "$SiteName.$Environment"
        }
    }
    else {
        $HostHeader = "$HostHeader.$Environment"
    }
    $HostAndEnviroment = $HostHeader

    # We will have a host header set by now
    if (-not $HostHeader.endswith('domain.com')) {
        $HostHeader = "$HostHeader.domain.com"
    }

    if (-not $SiteAppPool) {
        $SiteAppPool = $SiteName
    }

    if ($NoSSL) {
        $SecureSite = $False
    }
    else {
        $SecureSite = $True
    }

    if (-not $BaseSitePath) {
        $BaseSitePath = $ConfigObject.BaseSitePath
    }

    if ($SecureSite -and -not $CertThumbprint) {
        $CertThumbprint = $ConfigObject.CertThumbPrint
    }

    # We don't want the live suffix for live sites even in the app pool name
    if (-not $LiveEnv) {
        # Have to do the string concat here old school
        # otherwise the underscore becomes part of the variable name 
        $SiteAppPool = $Environment + '_' + $SiteAppPool
    }

    $SitePath = $BaseSitePath + $SiteName

    # Run precreation checks
    if (-not $NoDNS) {
        Add-SiteDNS -HostName $HostHeader -HostServer $Server
    }

    if (Test-Path ("IIS:\Sites\$SiteName")) {
        Throw 'The Site already exists'
    }

    # Directory
    $FolderExists = $False
    if (Test-path $SitePath) {
        # The directory exists and is empty, that's fine, but I can't go
        # creating a web site pointing at directory with stuff in it!

        # Yeah, that's what you need to do in PS to find anything in directory including
        # an empty directory!
        $items = Get-ChildItem $SitePath -Directory -Recurse | Where-Object -FilterScript {($_.GetFiles().Count -eq 0) -and $_.GetDirectories().Count -eq 0}
        if ($items) {
            Throw "The folder $SitePath already exists and has contents!"
        }

        Write-Host "$SitePath Folder already exists, but is empty, so I will use it"
        $FolderExists = $True
    }

    # App pool
    if (Test-Path ("IIS:\AppPools\$SiteAppPool")) {
        Throw "The App Pool $SiteAppPool already exists"
    }

    # SSL certificate (if required)
    if ($SecureSite -and -not (Test-Path ("Cert:\LocalMachine\My\$CertThumbprint"))) {
        Throw "Certficate with thumbprint $CertThumbprint not found in LocalMachine My certificate store"
    }

    # Great! We are good to go
    if (!$FolderExists) {
        Write-Host "Creating folder $SitePath";
        #if (-not (New-Item -ItemType directory -Path $SitePath -Force)) {
        #    Throw "Failed to create folder $SitePath"
        #}
    }

    Add-SiteAppPool -AppPoolName $SiteAppPool -AppPoolUser $AppPoolUser -AppPoolPassword $AppPoolPassword
    Add-Site -SiteName $SiteName -SiteAppPool $SiteAppPool -SitePath $SitePath -HostHeader $HostHeader -SecureSite $SecureSite
}
Catch {
    Write-Error "Site creation failed with the error: $_"
}