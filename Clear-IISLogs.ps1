<#
.Synopsis
    Clears the all site directories in the given iis log directory of log files older than the given date 
.EXAMPLE
    Remove-OldIISLogs -date 2023-01-20 -LogDir "E:\IIS_logs\" -LogFolderBaseName w3svc -LogFileBaseName u_ex
.Parameter DaysOld
    The age threshold in days, any file with the date part more than this many days old will be deleted.
.Parameter LogFolderBaseName
    The prefix for each sites own log directory, IIS adds the site id id to make each folder name unique.
    Optional, defaults to svc if not supplied
.Parameter LogFileBaseName
    The prefix added to the date to make each file in the site directory unique.
    Optional, defaults to u_ex if not supplied
.Parameter ArchiveLog
    A switch, if this is set the log file will be ziped and, optionally moved to a directory set by ArchivePath.
.Parameter ArchivePath
    An optional path that the archived logs are moved to, is ignored if the ArchiveLog switch is not set.
    If the ArchiveLog flag is set and this isn't provided, the logs are zipped in place.
#>

Param (
    [Parameter(Mandatory = $true)]
    [int]$DaysOld,
    [Parameter(Mandatory = $false)]
    [string]$LogFolderBaseName,
    [Parameter(Mandatory = $false)]
    [string]$LogFileBaseName,
    [switch]$ArchiveLog,
    [Parameter(Mandatory = $false)]
    [string]$ArchivePath
)

Import-Module IISAdministration

if ([String]::IsNullOrEmpty($LogFolderBaseName)) {
    $LogFolderBaseName = 'w3svc'
}
if ([String]::IsNullOrEmpty($LogFileBaseName)) {
    $LogFileBaseName = 'u_ex'
}

# Convert our YYDDMM fromated date to an int, then we can do simple
# comparisons to work out if the file is older or newer that our
# threshold date
# Get threhsold date...
$today = Get-Date
$thresholdDate = Get-Date -Date $today.AddDays(-$DaysOld)
# ...convert to a string...
$thresholdDateStr = "{0:yy}{0:MM}{0:dd}" -f $thresholdDate
# ...then to an int
$thresholdDateInt = [Int]::Parse($thresholdDateStr);

Get-IISSite | ForEach-Object {
    $logPath = "$($_.LogFile.Directory)\$($LogFolderBaseName)$($_.Id)\"
    
    # Sites don't create their log folder until they are accessed
    # so an on-existent folder is possibility
    if (Test-Path -Path $logPath) {
        Get-ChildItem $logPath -File -Filter "$($LogFileBaseName)*.log" | ForEach-Object {
            # Get files datestampt and convert this to an int
            $logFileName = $_.BaseName

            $logFileDateInt = [int]::Parse($logFileName.Substring(4, 6))

            if ($logFileDateInt -le $thresholdDateInt) {
                $fullLogFilePath = "$($logPath)$($logFileName).log"

                if ($ArchiveLog) {
                    $thisArchivePath = ''

                    if ($ArchivePath.Length -eq 0) {
                        $thisArchivePath = $logPath
                    }
                    else {
                        $thisArchivePath = $ArchivePath
                    }

                    $thisArchivePath += "\$($logFileName).zip"

                    Compress-Archive -Path $fullLogFilePath -DestinationPath $thisArchivePath
                    # Make sure the archive has been produced
                    if (Test-Path $thisArchivePath) {
                        Write-Output "Log $($logFileName).log archived to $($thisArchivePath)"
                        Remove-Item $fullLogFilePath
                    }
                }
                else {
                    Remove-Item $fullLogFilePath
                    Write-Output "Log $($fullLogFilePath) deleted"
                }
            }
        }
    }    
}