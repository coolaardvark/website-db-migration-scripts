<#
.Synopsis
   List all active web sites and the addresses/ports they are bound to on the local IIS server
.DESCRIPTION
   Run locally to get a list of base addresses and ports that each site hosted by the local
   instance of IIS are bound to, only shows sites that are running when the script is run
#>
Import-Module WebAdministration

[string]$output = ''

Get-ChildItem IIS:\Sites | Where { $_.state -eq 'Started'} | Foreach {
    [string]$siteBindings = ''
    
    $_.Bindings.Collection | Foreach {
        $bindingBits = $_.ToString().Split(':')
        $address = $bindingBits[2]

        # I need to check for https first since https does start with http!
        if  ($bindingBits[0].StartsWith('https')) {
            # Lose the sslFlags we have one the end of the ssl config thing
            $siteBindings += "https://$($address.Substring(0,$address.IndexOf(' ')))`n`r" 
        }
        elseif ($bindingBits[0].StartsWith('http')) {
            $siteBindings +=  "http://$address`n`r"
        }
    }
    
    $output += $siteBindings    
}

Write-Host $output