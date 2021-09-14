<#
.Synopsis
    Dumps connection strings found web.config files for all sites hosted by the local IIS server
.DESCRIPTION
   This script dumps any connection strings found in either the connectionStrings 
   or appplicationSettings sections of the web.config files used by all sites hosted by the local
   instance of IIS 
#>
Import-Module WebAdministration

function Get-ConStringsFromSection {
    param ($Config, $Site)
    
    [string] $conStrings = ''
    [string] $returnValue = ''
    Write-Host 'Searching connectionStrings section'  

    $conStringNodes = Select-Xml -Xml $Config -XPath '/configuration/connectionStrings//add'
    if ($conStringNodes -ne $null) {

        $count = 0
        $conStringNodes | Foreach {
            $conStrings += "$($_.Node.Attributes['name'].Value) : $($_.Node.Attributes['connectionString'].Value)`n`r"
            $count ++
        }

        Write-Host "$count connection strings found in $($_.Name) connectionStrings"
    }
    else {
        Write-Host 'Nothing found in connectionStrings'
    }

    if ($conStrings -ne '') {
        $returnValue = "$Site connection strings in connectionStrings section`n`r$conStrings"
    }
    
    $returnValue
}

function Get-ConStringsFromApplicarionSettings {
    param ($Config, $Site)

    [string] $conStrings = ''
    [string] $returnValue = ''
    Write-Host 'Searching applicationSettings section'

    # Application settings are tricky, we have a child node inside of it named with
    # the namespace of the application running, and I have no way of getting that from
    # IIS (it might have nothing to do with site name or URL) so select all children
    # (we could have several namespaces in 1 site) and loop through these
    $applicationSettings = Select-Xml -Xml $Config -XPath '/applicationSettings//*'

    if ($applicationSettings -ne $null) {
        # Iterate over each namespace
        $applicationSettings | Foreach {
            Write-Host "Searching applicationSettings for $($_.Node.ToString())"
            # Now we can use xpath again to look for values with Data Source in them
            # a sure sign we have a connection string on our hands
            $configValues = Select-Xml -Xml $_[0].Node -XPath 'setting/value[text()]'
            $configValues | Foreach {
                # get the node value as string
                $conStrings += $_.Node.InnerText
            }
            
            Write-Host "$count connection strings found in $($_.Name) connectionStrings"
        }
    }

    if ($conStrings -ne '') {
        $returnValue = "$Site connection strings in applicationSettings section`n`r$conStrings"
    }

    $returnValue
}

[string]$output = ''

Get-ChildItem IIS:\Sites | Where { $_.state -eq 'Started'} | Foreach {
    # Get the web.config file for this site
    $configPath = "$($_.PhysicalPath)\web.config"

    if (Test-Path $configPath) { 
        $siteName = $_.Name
        Write-Host "Searching web.config of $siteName"

        # Open and search the file
        # We have to do it this way, none of the 'high level'
        # web or IIS config cmdlets work in an way that I can
        # make sense of
        $configObject = [xml](Get-Content $configPath)
    
        $output += Get-ConStringsFromSection -Config $configObject -Site $siteName 
        $output += Get-ConStringsFromApplicarionSettings -Config $configObject -Site $siteName
    }
    
}

$outputPath = & { Split-Path $MyInvocation.ScriptName }
$outputFile = Join-Path $ConfigPath '.\connectionStrings.txt'
$output | Out-File -FilePath $outputFile