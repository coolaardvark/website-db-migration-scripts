Import-Module WebAdministration

function Get-ConStringsFromSection {
    param ($Config)
    
    [string] $conStrings = ''
    [string] $returnValue = "no connection strings in connectionStrings section`r`n" 

    $conStringNodes = Select-Xml -Xml $Config -XPath '/configuration/connectionStrings//add'
    if ($conStringNodes -ne $null) {

        $count = 0
        $conStringNodes | Foreach {
            $conStrings += "$($_.Node.Attributes['name'].Value) : $($_.Node.Attributes['connectionString'].Value)`r`n"
            $count ++
        }
    }

    if ($conStrings -ne '') {
        $returnValue = "= connection strings in connectionStrings section =`r`n$conStrings"
    }
    
    $returnValue
}

function Get-ConStringsFromApplicarionSettings {
    param ($Config)

    [string] $conStrings = ''
    [string] $returnValue = "no connection strings in applicationsSettings section`r`n"

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
                $conStrings += "$($_.Node.InnerText)`r`n"
            }
        }
    }

    if ($conStrings -ne '') {
        $returnValue = "= connection strings in applicationSettings section =`r`n$conStrings"
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
    
        $output += "=== Site $($siteName) ===`r`n"
        $output += Get-ConStringsFromSection -Config $configObject
        $output += Get-ConStringsFromApplicarionSettings -Config $configObject
        $output += "`r`n"
    }
    
}

$outputPath = & { Split-Path $MyInvocation.ScriptName }
$outputFile = Join-Path $outputPath '.\connectionStrings.txt'
$output | Out-File -FilePath $outputFile