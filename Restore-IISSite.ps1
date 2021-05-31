<#
 .SYNOPSIS
    Restores a packaged web site and settings to a zip file after backup on a different server
 .DESCRIPTION
    Takes the InputFile and restores the site settings and files in the file on to the local
    copy of IIS.
    Needs to be run as a user with admin rights on the server.
 .PARAMETER InputPath
    The packaged file for restoring to IIS.
 .PARAMETER EncrytpPassword
    A password used to encrypt the senstive site config, will be needed at the restore end.
 .PARAMETER PhysicalPath
    The physical path you want the restored web site to be served from, optional, if omitied
    the hardwired default of d:\websites\ is used
 .EXAMPLE
    Restore-IISSite -EncryptPassword 3r9u0jw0jfe -InputPath c:\site-backup\Addobeccdb.zip
 #>

 Param(
    [Parameter(Mandatory = $True)]
    [string]$InputPath,
    [Parameter(Mandatory = $True)]
    [string]$EncryptPassword,
    [Parameter(Mandatory = $False)]
    [string]$PhysicalPath
)

Set-StrictMode -Version Latest
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

    if (-not (Test-Path $InputPath)) {
        Throw "$InputPath not found"
    }
    else {
        if (-not (Test-Path -Path $InputPath -PathType leaf)) {
            Throw "$InputPath is not a file"
        }    
    }
    if ($InputPath.StartsWith('.')) {
        # We need an absoulte path to pass to the scripts/exe's
        $currentPath = (Get-Location).Path
        $InputPath = $currentPath + $InputPath.Substring(1)  
    }

    if (-not $PhysicalPath) {
        $PhysicalPath = 'D:\Websites\'
    }
    if (-not (Test-Path $PhysicalPath)) {
        Throw "$PhysicalPath doesn't exist"
    }
    if (-not $PhysicalPath.EndsWith('\')) {
        $PhysicalPath += '\'
    }

    $siteFileName = $InputPath.Substring($InputPath.LastIndexOf('\'))
    $siteFileParts = $siteFileName.Split('_')
    # if we have a file whose name ends in archive.zip, then this is an uncompressed
    # zip archive that just contains the contents of the site directory.  This
    # format is used when the total size of the site is larger than 2Gb
    if ($siteFileName.EndsWith('archive.zip')) {
        Write-Host "$siteFileName is an archive of a large (2Gb+) site, restoring with MSDeploy.exe"

        # The site name is in the file name, this time right before the archive.zip part
        $siteName = $siteFileParts[0]
        $MSDeployCmdLine = "& '$($deployExe)' '-verb=sync' '-dest=archivedir=$InputFile' '-source=apphostconfig=$SiteName'"
        Invoke-Expression $MSDeployCmdLine -OutVariable MSDeployOutput

        Write-Host 'MSDeploy.exe output'
        $MSDeployOutput.Split('`r`n') | ForEach-Object {
            Write-Host $_
        }
    }
    else {
        Write-Host "Restoring $siteFileName"
        # Get the final directory in the physical path from the filename (which 
        # handily contains the name as seen in the IIS management console)
        $siteName = $siteFileParts[2]

        $PhysicalPath += $siteName
        Restore-WDSite $InputPath -DestinationSettings @{ 'encryptPassword' = $EncryptPassword } -Parameters @{ 'Web Application Physical Path Parameter' = $PhysicalPath }
    }
}
Catch {
    Write-Error "Restore failed with the following error `n $_"
}