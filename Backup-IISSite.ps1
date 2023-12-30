<#
 .SYNOPSIS
    Dumps web site files and settings to a zip file for restoring on a different server
 .DESCRIPTION
    Takes the SiteName and dumps the site settings and files to zip file for transport to
    a new server, where the Restore-IISSite command can restore it
    Needs to be run as a user with admin rights on the server.
 .PARAMETER SiteName
    The sites name as presented in the ISS management plugin on the SourceServer.
 .PARAMETER EncrytpPassword
    A password used to encrypt the senstive site config, will be needed at the restore end
 .PARAMETER OutputPath
    The path where the packaged site will be saved
 .EXAMPLE
    Backup-IISSite -SiteName adobeccdb -EncryptPassword 3r9u0jw0jfe -OutputPath c:\site-backup\
 #>

Param(
    [Parameter(Mandatory = $True)]
    [string]$SiteName,
    [Parameter(Mandatory = $True)]
    [string]$EncryptPassword,
    [Parameter(Mandatory = $False)]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
Import-Module WebAdministration
Add-PSSnapin WDeploySnapin3.0

try {
    # The msdeploy.exe is what is called by the backup-wd<something> cmdlets,
    # they are just wrapers for it, but they limit what can be done so for 'advanced'
    # tasks I need to go direct to it, which first means finding it!
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy') {
        $MSDeploy = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy\3').InstallPath
       
        if ($MSDeploy -eq '') {
            Throw "I cant find msdeploy to archive $SiteName"
        }

        # Make the path point to the actual exe
        $MSDeploy += "msdeploy.exe"
    }

    # Are we running as admin?
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] 'Administrator')) {
        Throw 'You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!'
    }

    if ($OutputPath.Length -gt 0) {
        if (-not (Test-Path $OutputPath)) {
            Throw "$OutputPath doesn't exist!"
        }

        $OutputPath = $OutputPath.TrimEnd('\')
    }
    else {
        $OutputPath = "$env:HOMEDRIVE$env:HOMEPATH\Desktop"
    }

    $siteObject = Get-Item -Path "IIS:\Sites\$($SiteName)"
    $sitePath = $siteObject.PhysicalPath

    Write-Host "Packaging $SiteName..."

    # Sites larger than 2Gb are a problem, the inbuilt archive library
    # can't cope with them, so I have to call msdeploy direct and use
    # the archivedir (which doesn't actually compress the files)
    $siteSize = (Get-ChildItem $sitePath -Recurse | Measure-Object -Property Length -sum).Sum
    # I know this ia bit short of 2Gb!
    if ($siteSize -gt 200000000) {
        Write-Host 'Large site using msdeploy.exe directly'
        # Have to create the directory for this my self
        $archivePath = "$OutputPath\$SiteName-archive"

        # Building the command line is very difficult, spaces need to
        # be protected in paths, but I'm using both single and double quoted
        # strings here, nightmare!
        $MSDeployCmdLine = "& '$($deployExe)' '-verb=sync' '-source=apphostconfig=$SiteName' '-dest=archivedir=$("$archivePath")'"
        Invoke-Expression $MSDeployCmdLine -OutVariable MSDeployOutput

        Write-Host 'MSDeploy.exe output'
        $MSDeployOutput.Split('`r`n') | ForEach-Object {
            Write-Host $_
        } 
    }
    else {
        # Quote path to protect possilbe spaces in the path
        Backup-WDSite -Site $SiteName -SourceSettings @{ 'encryptPassword' = $encryptPassword } -IncludeAppPool -Output "$OutputPath"
    }
}
Catch {
    Write-Error "Backup failed with the following error `n $_"
}