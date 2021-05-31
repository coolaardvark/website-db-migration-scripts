Param(
    [Parameter(Mandatory = $True)]
    [string]$action,
    [Parameter(Mandatory = $True)]
    [string]$encryptPassword,
    [Parameter(Mandatory = $False)]
    [string]$skipSites,
    [Parameter(Mandatory = $False)]
    [string]$skipFiles,
    [Parameter(Mandatory = $False)]
    [string]$outputDirectory,
    [Parameter(Mandatory = $False)]
    [string]$restorePath,
    [Parameter(Mandatory = $False)]
    [string]$restoreSites
)

Set-StrictMode -Version Latest
Import-Module WebAdministration
Add-PSSnapin WDeploySnapin3.0

function Pack-ServerSites {
    param($skipList, $outputDirectory, $encryptPassword, $MSDeploy)

    # Create our package directory
    if (Test-Path "$outputDirectory\$env:COMPUTERNAME-sites") {
        Throw "$outputDirectory\$env:COMPUTERNAME-sites already exists, aborting"
    }

    New-Item -Path $outputDirectory -ItemType Directory -Name "$env:COMPUTERNAME-sites"
    $outputDirectory += "\$env:COMPUTERNAME-sites"
    # Paths could well have spaces in them, so now we have done everything
    # we need to do it, double quote the string to protect the spaces
    # when passing as a parameter
    $ouputDirectory = '"' + $outputDirectory + '"'

    # Get server config
    # Setting the error action to stop for this because if we can't backup
    # the server config, then there isn't much point in working on the
    # sites in it!
    Write-Host 'Backing up server config'
    Backup-WDServer -ConfigOnly -Output $outputDirectory -SourceSettings @{ 'encryptPassword' = $encryptPassword } -ErrorAction Stop -WarningVariable serverWarning -WarningAction SilentlyContinue

    $doneText = 'Packaging server config complete' 
    if ($serverWarning -ne $null) {
        $doneText += " but I encountered this warning`n$serverWarning"
    }
    Write-Host $doneText

    # Loop through sites backing each to it's own file
    Get-ChildItem "IIS:\Sites\" | ForEach-Object {
        $siteName = $_.Name
        $sitePath = $_.PhysicalPath

        # Skip ftp sites and those on the skip list
        if (-not ($skipList.ContainsKey($siteName))) {
            Write-Host "Packaging $siteName..."

            # Sites larger than 2Gb are a problem, the inbuilt archive library
            # can't cope with them, so I have to call msdeploy direct and use
            # the archivedir (which doesn't actually compress the files)
            $siteSize = (Get-ChildItem $sitePath -Recurse | Measure-Object -Property Length -sum).Sum
            # I know this ia bit short of 2Gb!
            if ($siteSize -gt 200000000) {
                Write-Host 'Large site using msdeploy.exe directly'
                # Have to create the directory for this my self, but remember I've double
                # quoted this string, so need to strip them off then add the site name
                $archiveDirectory = $outputDirectory.Trim('"') + "\$($siteName)_archive"

                # Building the command line is very difficult
                $MSDeployCmdLine = "& '$($MSDeploy)' '-verb=sync' '-source=apphostconfig=$siteName' '-dest=archivedir=$archiveDirectory'"
                Invoke-Expression $MSDeployCmdLine -OutVariable MSDeployOutput

                Write-Host 'MSDeploy.exe output'
                $MSDeployOutput.Split('`r`n') | ForEach-Object {
                    Write-Host $_
                } 
            }
            else {
                Backup-WDSite -Site $siteName -SourceSettings @{ 'encryptPassword' = $encryptPassword } -IncludeAppPool -Output $outputDirectory -ErrorVariable siteError -ErrorAction SilentlyContinue -WarningVariable siteWarning -WarningAction SilentlyContinue
            
                if ($siteError) {
                    Write-Host "Packaging failed with error`n$siteError"
                }
                else {
                    $doneText = "Packaging complete"
                    if ($siteWarning) {
                        $doneText += " but I encountered this warning`n$siteWarning"
                    }
                
                    Write-Host $doneText
                }
            }
        }
    }
}

function Unpack-ServerSites {
    param ($encryptPassword, $restorePath, $restoreList, $MSDeploy)

    # A working example of a command line with WDSite-Restore
    #Restore-WDSite "C:\Users\Mark.Keightley\Desktop\OAKRIDGE_AppHostConfig_toolboxdev_20210114165842.zip" -DestinationSettings @{ 'encryptPassword' = 'hel4of9x' } -Parameters @{ 'Web Application Physical Path Parameter' = 'C:\Websites\toolboxdev' }
}

try {
    # Get parameters and decide if we are backing up or restoring?
    if (-not $action.ToLower() -eq 'pack' -and -not $action.ToLower() -eq 'unpack') {
        Throw 'action parameter needs to be either pack or unpack'
    }

    # The msdeploy.exe is what is called by the backup-wd<something> cmdlets,
    # they are just wrapers for it, but they limit what can be done so for 'advanced'
    # tasks I need to go direct to it, which first means finding it!
    if (Test-Path 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy') {
        $MSDeploy = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\IIS Extensions\MSDeploy\3').InstallPath
       
        if ($MSDeploy -eq '') {
            Throw "I cant find msdeploy to archive $siteName"
        }

        # Make the path point to the actual exe
        $MSDeploy += "msdeploy.exe"
    }

    # Are we running as admin?
    if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] “Administrator”)) {
        Throw 'You do not have Administrator rights to run this script!`nPlease re-run this script as an Administrator!'
    }

    # Start logging if the host supports it
    if ($host.Name -eq 'ConsoleHost') {
        $scriptPath = & { Split-Path $MyInvocation.ScriptName }
        $logPath = Join-Path $scriptPath "Package-IISSites.log"
        Start-Transcript -Append -Path $logPath
    }

    # Different parameters required for different actions!
    if ($action.ToLower() -eq 'pack') {
        if ($outputDirectory -ne '') {
            if (-not (Test-Path $outputDirectory)) {
                Throw "$outputDirectory doesn't exist!"
            }

            $outputDirectory = $outputDirectory.TrimEnd('\')
        }
        else {
            $outputDirectory = "$env:HOMEDRIVE$env:HOMEPATH\Desktop"
        } 

        $skipList = @{}
        # We will always want to skip the default site
        $skipList.Add('Default Web Site', 1)
        if ($skipSites -ne '') {
            # Use a hash table for it's speedy lookups
            $skipSites.Split(',') | ForEach-Object {
                $skipList.Add($_.Trim(), 1)
            }
        }

        Pack-ServerSites -skipList $skipList -outputDirectory $outputDirectory -encryptPassword $encryptPassword -MSDeploy $MSDeploy
    }
    elseif ($action.ToLower() -eq 'unpack') {
        # We need to know where the sites are going to be restored to
        if ($restorePath -eq $null) {
            Throw 'The restorePath parameter needs to be set with the restore action'
        }
        
        if (-not (Test-Path $restorePath)) { 
            Throw "$restorePath doesn't exist, please create it before running me"
        }

        if ((Get-ChildItem -Path $restorePath -File -Filter "*_AppHostConfig_*.zip").Count -eq 0) {
            Throw "No web site files found in $restorePath"
        }

        $restoreList = @{}
        if ($restoreSites -ne '') {
            # If we don't have anything in the restoreSite variable we restore
            # everything, otherwise just restore what is listed there
            $restoreSites.Split(',') | ForEach-Object {
                $restoreList.Add($_.Trim(), 1)
            }
        }
        
        Unpack-ServerSites -encryptPassword $encryptPassword -restorePath $restorePath -restoreList $restoreList -MSDeploy $MSDeploy
    }
}
Catch {
    Write-Error "Action $action failed with the following error `n $_"
}
Finally {
    if ($host.Name -eq 'ConsoleHost') {
        Stop-Transcript
    }
}