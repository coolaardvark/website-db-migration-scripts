Import-Module WebAdministration

Get-ChildItem IIS:\AppPools | Where { $_.state -eq 'Started'} | Select-Object name, managedRuntimeVersion, managedPipelineMode, @{e={$_.processModel.username};l="username"}, @{e={$_.processModel.identityType};l="identityType"} | Format-Table -AutoSize