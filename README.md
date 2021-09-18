# website-db-migration-scripts

A series of Powershell scripts I put together to help with migrating a large 
number (30+) ASP.NET web apps and their backend databases on to new servers.  
Not all of the scripts where used in the final project, so I can't say they 
are fully functional but all did pass some basic tests.  I'll highlight the
scripts that haven't been used 'in anger' on a live system.

The scripts are resonably well documented and have basic help on the parameters 
they take, plus I hope their names make it reasonably clear what they do

## Backup-IISSite.ps1
wraps the WebAdministration framework and WDeploySnapin3.0 Powershell snapin 
to make it easy to dump a an IIS site to a zip file which can be restored 
using the Web Deploy tools or the matching restore script below.

## Restore-IISSite.ps1
Again a wraper for the WebAdministration tools (which are in turn a wraper
for the web deploy framework!), restores a ziped site file produced either
directly by web deploy or my script above

## Create-IISWebSite.ps1
Automates the creation of an IIS web site, including the adding DNS records
for the site.  Requires DNS AD plugin to be install and needs admin rights
both on the local machine and AD to run.
The script uses a JSON config file (Create-IISWebsite.json) to set default
values for things like paths, domains and certifcates, this will need editing
before use.
The script works, but was never used since I lost my domain admin rights during
a security audit (as I dev I didn't need them and good secuirty policy dicates
all users should have only the rights they actually need).

## Dump-DBServerUsers.ps1
The single most used script here!  It's usefulness far outlived the migration
project!  I can't claim much credit for this script, much of the work was done
in [Jeffery Yao MSSQL tips article](https://www.mssqltips.com/sqlservertip/4572/cloning-a-sql-server-login-with-all-permissions-using-powershell/) 
I tweaked it to work the way I wanted and brought it in to line with our in
house Powershell 'style'

## Dump-Dependencies.ps1
Lists all inter-database links for the given database server, useful for
figuring out which databases had to be moved at the smae time

## Get-ActiveWebSiteConnectionStrings.ps1
This script dumps any connection strings found in either the connectionStrings 
or appplicationSettings sections of the web.config files used by all sites hosted by the local instance of IIS.  
I normally use this for getting a list of sites that will be down 
when writing the change control emails for server updates.
There are methods in the WebAdministration powershell module that in theory can do this, but
I couldn't get them to work a sensible way, so I use Xpath commands to navigate the XML
config file format.

## Migrate-WebSite.ps1
copies arcoss the network the given site from 1 IIS server to another.  
Uses Web Deploy to do this and requires that the web deploy port (8172) 
is allowed in the target server and of course needs admin rights on both 
machines.
I never used this script in production due to differences in the web deploy
versions (I think) between the 2 servers, we had to pacckage the files
copy them by SMB and then restore on the target machine.

## Package-IISSites.ps1
Takes all sites on the local server and packages each one in zip file using
the web deploy framework.  These files can be restored using either the web
deploy tools, the above Restore-IISSite script or, in theory this script with
the -Restore parameter.  I say in theory because I never actual finished that
part of the script.
You might also guess I never used this script on a production system.

## Set-SQLPasswords.ps1
A 'quick and dirty' helper script that I worte to take a simple cvs file 
and sets the listed users with the password from the sheet.  Obviously use
with care, since you need to have passwords in plaintext right next to the
matching username, so delete (completely) the csv file once you are done!
