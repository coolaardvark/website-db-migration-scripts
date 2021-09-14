<#
.Synopsis
   Dump all users with memberships and permissions on a given SQL server
.DESCRIPTION
   Dump all users with memberships and permissions on a SQL server to a script file for migration between servers
.EXAMPLE
   The following command scripts out the permissions all users on the server and generates the script at "c:\temp\clone.sql"
   Dump-DBServerUsers -ServerName Server1 -FilePath "c:\temp\clone.sql"
.Parameter ServerName
   Server is the name of the server you wish to dump the users from. (mandatory)
.Parameter FilePath
   The full path name for the generated sql script, if not provided the script is output to the console.
.Parameter SpesificLogins
    A user name or comma seperated list of user names, if spesifed only these users will be dumped, if omitted all users
    (bar system and internal SQL user) will be included in the dump.
.Parameter HideProgress
    Supresses all but the start and complete messages from terminal output.  Useful for when $FilePath is not spesified
    and so the final script will end up on the console as well.
.Parameter ByLogin
    A switch, if this is set, then indivdual script files are generated for each login, with out it a single script
    is generated for all (or selected) users on all databases on the server.  It can't be set if ByDatabase is also set.
    If it is set and a FilePath parameter is provided, the file name (if present) is ignored and the files are generated
    with a name like this user-<user name>.sql
.Parameter ByDatabase
    A switch, if this is set, then indivdual script files are generated for each database, with out it a single script
    is generated for all (or selected) databases on the server.  It can't be set if ByUser is also set.
    If it is set and a FilePath parameter is provided, the file name (if present) is ignored and the files are generated
    with a name like this database-<database name>.sql
.Parameter ScriptLogins
    This switch if set causes only the login and server level permissions details to be dumped, if this or the 
    other Script switch is not given everthing is dumped.  May be combined with either the SpesificLogin 
    and SpesificDatabase parameters.
.Parameter ScriptUsers
    This switch if set causes only the user and database level permissions details to be dumped, if this or the 
    other Script switch is not given everthing is dumped.  May be combined with either the SpesificLogin 
    and SpesificDatabase parameters.
.OUTPUTS
   The script will dump the generated SQL to screen if no FilePath is spesified.  If one is the file or files
   (depending on the options selected) will be saved there.  Also if logins are requested and a FilePath is set,
   a CSV file called password-helper will saved in the same directory as the slq script/s.  This file can be used
   with the Set-SQLPasswords script to set the passwords for SQL users.  The passwords have to be added to the
   CSV file, since this script has no way of getting them!
#>

Param (
    [Parameter(Mandatory = $true)]
    [string]$ServerName,
    [Parameter(Mandatory = $false)]
    [Switch]$ByLogin,
    [Parameter(Mandatory = $false)]
    [Switch]$ByDatabase,
    [Parameter(Mandatory = $false)]
    [string[]]$SpesificLogins,
    [Parameter(Mandatory = $false)]
    [string[]]$SpesificDatabases,
    [Parameter(Mandatory = $false)]
    [string]$FilePath,
    [Parameter(Mandatory = $false)]
    [Switch]$ScriptLogins,
    [Parameter(Mandatory = $false)]
    [Switch]$ScriptUsers,
    [Parameter(Mandatory = $false)]
    [Switch]$HideProgress
)

Set-StrictMode -Version Latest

# To save a lot of awkward typing!
$nl = "`r`n"

Function Add-LoginScriptSection {
    Param ($LoginName, [ref]$SQLLogins)

    $loginType = $serverObject.Logins[$LoginName].LoginType

    Show-ProgressMessage -Message "Scripting login for $LoginName"

    $loginString = "/* Login $LoginName */$nl"
    $loginString += "IF (SELECT COUNT(principal_id) FROM [sys].[server_principals] WHERE name = '$LoginName') = 0$nl"
    $loginString += "CREATE LOGIN [$($LoginName)] "

    if ($loginType -eq 'SqlLogin') {
        $loginString += "WITH PASSWORD=N'$(New-RandomPassword)', CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF;$nl"

        $SQLLogins.Value += $LoginName
    }
    elseif ($loginType -eq 'WindowsUser' -or $loginType -eq 'WindowsGroup') {
        $loginString += "FROM WINDOWS;$nl"
    }
    $loginString += "$($nl)GO$nl"

    Show-ProgressMessage -Message "Scripting adding of server roles for $LoginName"

    [string]$serverRolesString = "/* Server roles */$nl"
    $serverObject.Logins[$LoginName].ListMembers() | ForEach-Object {
        $serverRolesString += "exec sp_addsrvrolemember @loginame = '$($LoginName)', @rolename = '$($_)'; $nl"
    }
    $serverRolesString += "$($nl)GO$nl"

    Show-ProgressMessage -Message "Scripting adding of server permissions for $LoginName"

    [string]$serverPermissionString = "/* Server permssions */$nl"
    $serverObject.EnumObjectPermissions($LoginName) | ForEach-Object { 
        if ($_.PermissionState -eq 'GrantWithGrant') {
            $serverPermissionString += "GRANT $($_.PermissionType) on $($_.ObjectClass)::[$($_.ObjectName)] to [$LoginName] WITH GRANT OPTION;$nl"
        }
        else { 
            $serverPermissionString += "$($_.PermissionState) $($_.PermissionType) on $($_.ObjectClass)::[$($_.ObjectName)] to [$LoginName];$nl"
        }
    }
                                           
    $serverObject.EnumServerPermissions($LoginName) | ForEach-Object { 
        if ($_.PermissionState -eq 'GrantWithGrant') { 
            $serverPermissionString += "GRANT $($_.PermissionType) to [$LoginName] WITH GRANT OPTION;$nl"
        }
        else { 
            $serverPermissionString += "$($_.PermissionState) $($_.PermissionType) to [$LoginName];$nl"
        }
    }
    $serverPermissionString += "$($nl)GO$nl"

    "$($loginString)$($serverRolesString)$($serverPermissionString)"
}

Function New-RandomPassword {
    -join ((48..57) + (65..90) + (97..122) | Get-Random -Count 10 | ForEach-Object {[char]$_})    
}

Function New-UserScriptSectionByUser {
    Param ($UserName)

    Show-ProgressMessage -Message "Scripting adding and database/object permissions for $UserName"
    
    $userScript = '';

    foreach ($object in $serverObject.Logins[$UserName].EnumDatabaseMappings()) {
        $userScript += Get-UserPermissionsByDB -DBName $object.DBName -UserName $UserName -DBObject $object
    }

    $userScript
}

Function New-UserScriptSectionByDatabase {
    Param ($DatabaseName)

    Show-ProgressMessage -Message "Scripting adding users and permissions for $DatabaseName"
    $databaseScript = ''

    $serverObject.Databases[$DatabaseName].Users | Where-Object {($_.LoginType -eq 'SqlLogin') -and ($_.UserType -eq 'SqlUser') -and (-not $_.IsSystemObject)} | ForEach-Object ({
        $userName = $_.Name

        Write-Host $userName

        foreach($object in $serverObject.Logins[$userName].EnumDatabaseMappings()) {
            if ($object.DBName -eq $DatabaseName) {
                $databaseScript += Get-UserPermissionsByDB -DBName $DatabaseName -UserName $userName -DBObject $object
            }
        }

    })

    $databaseScript
}

Function Get-UserPermissionsByDB {
    Param($DBName, $UserName, $DBObject)

    $userPermissionsString = ''

    $userPermissions = @();
    [hashtable[]] $objectPermissionsLines = @();

    # Skip off line and any not normal databases
    $status = $serverObject.Databases[$DBName].Status
    if ($status -ne 'Normal') {
        Show-ProgressMessage -Message "Skipping $DBName because it is $status"
        return $userPermissionsString
    }

    Show-ProgressMessage -Message "Scripting user for login $UserName in $DBName db"
    # We are dumping these users for migration to a new server, so will be working
    # from db backups on that server, hence we need to drop the 'backed up' user
    # from each db and add the login (of the same name) from the new server
    $dropUserSQL = ''
    # There are additonal complexties.  We need to change the ownership of any
    # of the system schemas, that this user might own, before we can delete the user
    $roles = $serverObject.Databases[$DBName].Users[$DBObject.UserName].EnumRoles()
    
    if ($roles) { 
        $roles | ForEach-Object { 
            $dropUserSQL += "ALTER AUTHORIZATION ON SCHEMA::$_ TO dbo;$nl"
        }
    }
    $dropUserSQL += "DROP USER [$userName];$($nl)CREATE USER [$userName] FOR LOGIN [$userName];$nl"
    $objectPermissionsLines += @{DBName = $DBName; sqlcmd = $dropUserSQL;}

    if ($roles) {
        Show-ProgressMessage -Message "Scripting adding roles for $($DBObject.UserName) in $DBName db" 
        $roles | ForEach-Object { 
            $objectPermissionsLines += @{DBName = $DBName; sqlcmd = "exec sp_addrolemember @rolename='$_', @memberName='$($UserName)';$nl";}
        }
    }

    Show-ProgressMessage -Message "Getting permissions for user $($DBObject.UserName) in $DBName"
    $permissionsFound = 0

    $permissions = $serverObject.Databases[$DBName].EnumDatabasePermissions($DBObject.UserName)
    if ($permissions) { 
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].EnumObjectPermissions($DBObject.UserName)
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].Certificates | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].AsymmetricKeys | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].SymmetricKeys | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].XMLSchemaCollections | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].ServiceBroker.MessageTypes | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].ServiceBroker.Routes | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].ServiceBroker.ServiceContracts | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].ServiceBroker.Services | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].FullTextCatalogs | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++ 
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    $permissions = $serverObject.Databases[$DBName].FullTextStopLists | ForEach-Object {
        $_.EnumObjectPermissions($DBObject.UserName)
    } 
    if ($permissions) {
        $permissionsFound++
        $userPermissions += @{DBName = $DBName; Permission = $permissions;}
    }

    Show-ProgressMessage -Message "$permissionsFound Permissions found for user $($DBObject.UserName) in $DBName"

    foreach ($up in $userPermissions) {
        $objectPermissionLine = @{DBName=$($up.DBName); sqlcmd='';}
        $scriptString = ''

        foreach ($p in $up.Permission) {
            $schema = ''
            if ($p.ObjectSchema) {
                $schema = "$($p.ObjectSchema)."
            }

            $op_state = $p.PermissionState
            $objectName = $p.ObjectName

            if ($op_state -eq 'GRANTwithGrant') {
                $op_state = 'Grant'
                $option = ' WITH GRANT OPTION'
            }
            else {
                $option = ''
            }

            if ($p.ObjectClass -ne 'ObjectOrColumn') {   
                Switch ($p.ObjectClass)  {  
                    'Database'         { $scriptString += "$op_state $($p.PermissionType) to [$UserName]$option;"} 
                    'SqlAssembly'      { $scriptString += "$op_state $($p.PermissionType) ON Assembly::$($schema)$($objectName) to [$UserName]$option;"}
                    'Schema'           { $scriptString += "$op_state $($p.PermissionType) ON SCHEMA::$($schema)$($objectName) to [$UserName]$option;"}
                    'UserDefinedType'  { $scriptString += "$op_state $($p.PermissionType) ON TYPE::$($schema)$($objectName) to [$UserName]$option;"}
                    'AsymmetricKey'    { $scriptString += "$op_state $($p.PermissionType) ON ASYMMETRIC KEY::$($schema)$($objectName) to [$UserName]$option;"}
                    'SymmetricKey'     { $scriptString += "$op_state $($p.PermissionType) ON SYMMETRIC KEY::$($schema)$($objectName) to [$UserName]$option;"}
                    'Certificate'      { $scriptString += "$op_state $($p.PermissionType) ON Certificate::$($schema)$($objectName) to [$UserName]$option;"}
                    'XmlNamespace'     { $scriptString += "$op_state $($p.PermissionType) ON XML SCHEMA COLLECTION::$($schema)$($objectName) to [$UserName]$option;"}
                    'FullTextCatalog'  { $scriptString += "$op_state $($p.PermissionType) ON FullText Catalog::$($schema)[$($objectName)] to [$UserName]$option;"}
                    'FullTextStopList' { $scriptString += "$op_state $($p.PermissionType) ON FullText Stoplist::$($schema)[$($objectName)] to [$UserName]$option;"}
                    'MessageType'      { $scriptString += "$op_state $($p.PermissionType) ON Message Type::$($schema)[$($objectName)] to [$UserName]$option;"}
                    'ServiceContract'  { $scriptString += "$op_state $($p.PermissionType) ON Contract::$($schema)[$($objectName)] to [$UserName]$option;"}
                    'ServiceRoute'     { $scriptString += "$op_state $($p.PermissionType) ON Route::$($schema)[$($objectName)] to [$UserName]$option;"}
                    'Service'          { $scriptString += "$op_state $($p.PermissionType) ON Service::$($schema)[$($objectName)] to [$UserName]$option;"}
                }
            }
            else {
                $scriptString += "$op_state $($p.PermissionType) ON Object::$($schema)$($objectName) "

                # Column permissions (if they exist)
                if ($p.ColumnName) { 
                    $scriptString += "($($p.ColumnName)) "
                }
                    
                $scriptString += "to [$UserName];"
            }

            $scriptString += $nl
        }

        $objectPermissionLine.sqlcmd = $scriptString
        $objectPermissionsLines += $objectPermissionLine
    }

    # Finally build the text file from our objectPermissionsLines...object
    # We might have nothing at this point
    if ($objectPermissionsLines.Count -gt 0) {
        $userPermissionsString = "/* User permissions */$nl"
        # limit the number of USE [db] we output!
        $prevDBName = ''
        foreach ($line in $objectPermissionsLines) {
            $useCMD = ''
            if ($prevDBName -eq '' -or ($prevDBName -ne $line.DBName)) {
                $useCMD = "USE [$($line.DBName)]$($nl)GO$nl"
                $prevDBName = $line.DBName
            }

            $userPermissionsString += "$($useCMD)$($line.sqlcmd)GO$nl"   
        }
    }

    $userPermissionsString
}

Function New-ScriptByServer {
    Param ($ScriptWhat)
    $serverScript = "USE [master]$($nl)GO$nl"

    $SQLLogins = @()

    $serverObject.Logins | ForEach-Object({
        $loginName = $_.Name

        if ((Script-ThisUser -User $_ -LoginsToScript $logins) -eq [ScriptUser]::Yes) {
            if ($ScriptWhat -eq [ScriptObjects]::Logins -or $ScriptWhat -eq [ScriptObjects]::Everything) {
                $serverScript += Add-LoginScriptSection -LoginName $loginName -SQLLogins ([ref]$SQLLogins)
            }
            if ($ScriptWhat -eq [ScriptObjects]::Users -or $ScriptWhat -eq [ScriptObjects]::Everything) {
                $serverScript += New-UserScriptSectionByUser -UserName $loginName
            }
        }
    })

    # Only dump this 'helper file' if we have any SQL users
    if ($SQLLogins.Count -gt 0) {
        Dump-PasswordHelperFile($SQLLogins)
    } 

    $serverScript
}

Function New-ScriptByDatabase {
    Param ($DatabaseName, $ScriptWhat)
    $databaseScript = "USE [master]$($nl)GO$nl"

    # We are now working at a db level so get the list of logins we need to create
    # from the database/s
    $serverObject.Databases[$DatabaseName].Users | ForEach-Object ({
        $userName = $_.Name

        if ((Script-ThisUser -User $_ -LoginsToScript $logins) -eq [ScriptUser]::Yes) {
            if ($ScriptWhat -eq [ScriptObjects]::Logins -or $ScriptWhat -eq [ScriptObjects]::Everything) {
                $databaseScript += Add-LoginScriptSection -LoginName $userName
            }
        }
    })

    # Permissions have their own internal loops so we just call this once
    if ($ScriptWhat -eq [ScriptObjects]::Users -or $ScriptWhat -eq [ScriptObjects]::Everything) {
        $databaseScript += New-UserScriptSectionByDatabase -DatabaseName $DatabaseName
    }

    $databaseScript
}

Function Script-ThisUser {
    Param($User, $LoginsToScript)

    $userName = $User.Name

    # We can be passed either a Login or User object here, they have the same
    # name field, but a Login lacks the UserType (makes sence, it's not a user!)
    $objectType = $User.GetType().Name

    $scriptUser = [ScriptUser]::NotDecided

    # Skip system and internal SQL users that will already exist
    if ($userName.StartsWith('##') -or $userName.StartsWith('NT ') -or $userName -eq 'sa' -or $_.IsSystemObject -eq $true) {
        $scriptUser = [ScriptUser]::No
        Show-ProgressMessage -Message "Skipping $userName (system or internal SQL user)"
    }

    # Windows groups are odd, they don't appear in the EnumDatabaseMappings call, we don't have
    # any groups mapped direct to databases anyway, so I'll just skip these
    if (($scriptUser -eq [ScriptUser]::NotDecided) -and ($User.LoginType -eq 'WindowsGroup')) {
        $scriptUser = [ScriptUser]::No
        Show-ProgressMessage -message "Skipping Windows group $userName"
    }

    # Only User objects have a UserType
    if ($objectType -eq 'User') {
        if (($scriptUser -eq [ScriptUser]::NotDecided) -and ($User.UserType -ne 'SqlLogin')) {
            $scriptUser = [ScriptUser]::No
            Show-ProgressMessage -message "Skipping non-loginable user $userName"
        }
    }

    # Filter out users not on our spesific users list, this overides any of the
    # other choices made so needs to come right after the default skipped users above 
    if ($scriptUser -eq [ScriptUser]::NotDecided) {
            if (($LoginsToScript[$userName] -eq 1) -or ($LoginsToScript['__all'] -eq 1)) {
                $scriptUser = [ScriptUser]::Yes
        }
        else {
            Show-ProgressMessage -Message "Skipping $userName (not on the SpesificUser list)"
        }
    }

    if ($scriptUser -eq [ScriptUser]::NotDecided) {
        # The default bail out for anything we don't know about
        Show-ProgressMessage -Message "Skipping $userName (not sure what they are)"
        $scriptUser = [ScripUser]::No
    }

    $scriptUser
}

Function Dump-PasswordHelperFile {
    Param ($SQLLogins)

    # It only makes sense for us to output anything when the script is
    # saving its output to a file
    if ($FilePath -ne '') {
        Show-ProgressMessage -message "SQL users found, saving password helper file"

        $SQLPasswordHelperContents = "Username,Password $nl"

        $SQLLogins.ForEach({
            $SQLPasswordHelperContents += "$_,$nl"
        })

        # Extract just the path from our output file 
        $PasswordHelperFile = "$($FilePath.Substring(0, $FilePath.LastIndexOf('\') +1 ))password-helper.csv"
        $SQLPasswordHelperContents | Out-File -FilePath $PasswordHelperFile
    }
}

Function Show-ProgressMessage {
    Param ($message)

    if ($HideProgress -eq $false) {
        Write-Host $message
    }
}

enum ScriptUser {
    NotDecided
    Yes
    No
}

enum ScriptByType {
    Login
    Database
    Server
}

enum ScriptObjects {
    Everything
    Logins
    Users
}

try {
    Write-Host "Working on dump of DB users from $ServerName, please wait"

    # Prep
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMO') | Out-Null

    $serverObject = New-Object 'Microsoft.SqlServer.Management.Smo.Server' $ServerName;
    if (-not $serverObject.Edition) {
        Throw "Connection to $ServerName failed"
    }

    if ($FilePath -ne '') {
        # Does $FilePath point to a directory or file?
        if (($SpesificLogins -or $SpesificDatabases) -and (Test-Path -Path $FilePath -PathType leaf)) {
            # It's a file, make it just a directory when dumping by user or database
            $FilePath = $FilePath.Substring(0, $FilePath.LastIndexOf('\')+1)
        }
    }

    $byObjectType = [ScriptByType]::Server

    $logins = @{}
    $databases = @{}
    # Put any lists in to a hash for easy look ups
    # By selecting spesifics to script we are automatically going
    # to script by the type of that spesific
    if ($SpesificLogins) {
        $SpesificLogins.ForEach({$logins.Add($_, 1)})
        if (-not $SpesificDatabases) {
            $byObjectType = [ScriptByType]::Login
        }
    }
    else {
        # If no one is spesified we do everyone
        $logins.Add('__all', 1)
    }
    if ($SpesificDatabases) {
        $SpesificDatabases.ForEach({
            $databases.Add($_, 1)

            # Include all users that are in this database unless we are only
            # getting spesific ones
            # This will catch odd users like dbo, but they will be filtered
            # out later on
            if ($SpesificLogins) {
                $serverObject.Databases[$_].Users | ForEach-Object ({
                    $logins.Add($_, 1)
                })
            }
        })
        
        $byObjectType = [ScriptByType]::Database
    }
    else {
        # Again if no db sepsified we do them all
        $databases.Add('__all', 1)
    }
 
    # We can also script by a type when not selecting spesifics of that type
    if ($byObjectType -eq [ScriptByType]::Server) {
        if ($ByLogin) {
            $byObjectType = [ScriptByType]::Login
        }
        if ($ByDatabase) {
            $byObjectType = [ScriptByType]::Database
        }
    }

    if ($ScriptLogins -and $ScriptUsers) {
        Throw "You can't pass both ScriptUsers and ScriptLogins, to get both don't pass either of these switches!"
    }

    $scriptObjects = [ScriptObjects]::Everything
    if ($ScriptLogins) {
        $scriptObjects = [ScriptObjects]::Logins
    }
    if ($ScriptUsers) {
        $scriptObjects = [ScriptObjects]::Users
    }

    # Generate the script
    switch($byObjectType) {
        ([ScriptByType]::Database) {
            Show-ProgressMessage -message "Scripting by Database"
            
            $SpesificDatabases.ForEach({
                if ($serverObject.Databases[$_]) {
                    Show-ProgressMessage -message "Working on database $_"

                    $databaseScript = New-ScriptByDatabase -DatabaseName $_ -ScriptWhat $scriptObjects

                    if ($FilePath -ne '') {
                        $databaseScript | Out-File -FilePath "$($FilePath)database-$($_).sql"
                        Show-ProgressMessage -message "Permissions for db $_ dumped to $($FilePath)database-$($_).sql"
                    }
                    else {
                        "Database $($_)$($nl)$databaseScript$($nl)"
                    }
                }
                else {
                    Write-Warning "Database $_ not found on $ServerName"
                }
            }) 
            
            break
        }
        ([ScriptByType]::Login) { 
            Show-ProgressMessage -message "Scripting by login"

            $SQLLogins = @()

            $SpesificLogins.ForEach({
                Show-ProgressMessage -message "Working on login $_"

                $userScript = "USE [master]$($nl)GO$nl"

                if ($ScriptObjects -eq [ScriptObjects]::Logins -or $ScriptObjects -eq [ScriptObjects]::Everything) {
                    # We get our user script back and flag showing if the user is an SQL user
                    # this should be any array, but I just can't get the function to return one of the dam things
                    $scriptTemp = Add-LoginScriptSection -LoginName $_
                    
                    $userScript += $scriptTemp.substring(0, $scriptTemp.indexof('|'))

                    if ($scriptTemp.subscript($scriptTemp.indexof('|')) -eq '1') {
                        $SQLLogins += $_
                    }
                }
                if ($ScriptObjects -eq [ScriptObjects]::Users -or $ScriptObjects -eq [ScriptObjects]::Everything) {
                    $userScript += New-UserScriptSectionByUser -UserName $_
                }

                if ($FilePath -ne '') {
                    # We can't allow full domain user names here, the slash will mess
                    # up the path, so strip domain components for the file name
                    $stripedUserName = ''
                    if ($_.contains('\')) {
                        $stripedUserName = $_.substring($_.indexof('\') + 1)
                    }
                    else {
                        $stripedUserName = $_
                    }

                    $userScript | Out-File -FilePath "$($FilePath)user-$($stripedUserName).sql"
                    Show-ProgressMessage -message "Permissions for user $stripedUserName dumped to $($FilePath)user-$($stripedUserName).sql"
                }
                else {
                    "User $($_)$($nl)$userScript$($nl)"
                }

                # Only dump this 'helper file' if we have any SQL users
                if ($SQLLogins.Count -gt 0) {
                    Dump-PasswordHelperFile($SQLLogins)
                }
            })

            break
        }
        ([ScriptByType]::Server) { 
            Show-ProgressMessage -message "Scripting by server"

            $scriptString = New-ScriptByServer -ScriptWhat $scriptObjects

            if ($FilePath -ne '') {
                $scriptString | Out-File -FilePath $FilePath
                Show-ProgressMessage -message "Permissions for $serverName dumpped to $FilePath"
            }
            else {
                "Script for Server $serverName$($nl)$scriptString"
            }

            break 
        }
    }
    
    Write-Host "Finished user dump of $ServerName"
}
Catch {
    Write-Error "Failed with error $_"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"  
}
