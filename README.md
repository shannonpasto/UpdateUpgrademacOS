# UpdateUpgrademacOS
Update or Upgrade macOS

A Jamf shell script that can be used to update or upgrade (including erase) macOS.

This script was written as the Declarative Device Management commands available in Jamf Pro just aren't reliable enough.

In a nutshell this script will...
- use the first caching server if found on the network
- download the latest macOS (full) installer for the Mac
- install (with optional erase) the update or upgrade

Requirements:
- a secure token user
- the password for the secure token user
- the latest su catalog URL from Apple
- optionally set to update or upgrade (update is default)
- optionally set to erase (install is default)

To use:
1) upload the script to Jamf
2) Create a new policy and add the script. Set the following 3 required parameters...
- paramater 4: secureTokenUser
- paramater 5: userPass
- paramater 6: suCatURL

3) Optional:
- paramater 7: installType - minor or major, minor is default if left blank
- paramater 8: eraseInstall - YES to erase or NO. NO is default if left blank

4) Scope in your target devices
5) Set you exection event and save

A user does not need to be logged on.

The suCatURL changes with each major version of the macOS. The current URL for Sequoia is0
>https://swscan.apple.com/content/catalogs/others/index-15-14-13-12-10.16-10.15-10.14-10.13-10.12-10.11-10.10-10.9-mountainlion-lion-snowleopard-leopard.merged-1.sucatalog

The script can be run locally. Add your paramaters in the "variable declarations" section, save and execute `sudo sh ./update_upgrade_macos.sh`. Alternatively, append the paramaters on the coomand line, eg `sudo sh ./update_upgrade_macos.sh 1 2 3 "<securetokenusername>" "<secure token user password>" "<suCatURL>`
