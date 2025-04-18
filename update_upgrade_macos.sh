#!/bin/sh

###################
# update_upgrade_macos.sh - update or upgrade macOS
# Shannon Pasto https://github.com/shannonpasto/UpdateUpgrademacOS
#
# https://www.jamf.com/blog/reinstall-a-clean-macos-with-one-button/
#
# v1.1.1 (18/04/2025)
###################
## uncomment the next line to output debugging to stdout
#set -x

###############################################################################
## variable declarations
# shellcheck disable=SC2034
ME=$(basename "$0")
# shellcheck disable=SC2034
BINPATH=$(dirname "$0")
archType=$(uname -m)
secureTokenUser=""  # can not blank
userPass=""  # set variable here overrides passed parameter
suCatURL=""  # set variable here overrides passed parameter
installType=""  # major for upgrade, minor for update. minor is default
eraseInstall=""  # YES to erase/install, NO for in-place. default is NO
suCatFILE="/tmp/sucat.plist"
currentOS=$(/usr/bin/sw_vers -productVersion)
startOSLog="/var/log/startosinstall.log"
maxAttempts=3

###############################################################################
## function declarations

clean_up() {

  /bin/rm "${suCatFILE}" >/dev/null 2>&1
  /bin/rm /tmp/prodID.txt >/dev/null 2>&1
  /bin/rm /tmp/*.English.dist >/dev/null 2>&1
  /bin/cat "${startOSLog}" >/dev/null 2>&1
  /bin/rm "${startOSLog}" >/dev/null 2>&1
  /bin/rm /tmp/list.csv >/dev/null 2>&1
  /bin/rm /private/tmp/Install-*.pkg >/dev/null 2>&1

}

###############################################################################
## start the script here
# trap clean_up EXIT

# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 4 AND, IF SO, ASSIGN TO "secureTokenUser"
if [ "${4}" != "" ] && [ "${secureTokenUser}" = "" ]; then
  /bin/echo "Parameter 4 configured"
  secureTokenUser="${4}"
elif [ "${4}" != "" ] || [ "${secureTokenUser}" != "" ]; then
  /bin/echo "Parameter 4 overwritten by script variable"
elif [ "${4}" = "" ] && [ "${secureTokenUser}" = "" ]; then
  /bin/echo "Required parameter 4 not set. Exiting"
  exit 1
fi

# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 5 AND, IF SO, ASSIGN TO "userPass"
if [ "${5}" != "" ] && [ "${userPass}" = "" ]; then
  /bin/echo "Parameter 5 configured"
  userPass="${5}"
elif [ "${5}" != "" ] || [ "${userPass}" != "" ]; then
  /bin/echo "Parameter 5 overwritten by script variable"
elif [ "${5}" = "" ] && [ "${userPass}" = "" ]; then
  /bin/echo "Required parameter 5 not set. Exiting"
  exit 1
fi

# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 6 AND, IF SO, ASSIGN TO "suCatURL"
if [ "${6}" != "" ] && [ "${suCatURL}" = "" ]; then
  /bin/echo "Parameter 6 configured"
  suCatURL="${6}"
elif [ "${6}" != "" ] || [ "${suCatURL}" != "" ]; then
  /bin/echo "Parameter 6 overwritten by script variable"
elif [ "${6}" = "" ] && [ "${suCatURL}" = "" ]; then
  /bin/echo "Required parameter 7 not set. Exiting"
  exit 1
fi

# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 7 AND, IF SO, ASSIGN TO "installType"
if [ "${7}" != "" ] && [ "${installType}" = "" ]; then
  installType="${7}"
else
  installType="minor"
fi

# CHECK TO SEE IF A VALUE WAS PASSED IN PARAMETER 8 AND, IF SO, ASSIGN TO "eraseInstall"
if [ "${8}" != "" ] && [ "${eraseInstall}" = "" ]; then
  eraseInstall="${8}"
else
  eraseInstall="NO"
fi

# a cleanup just in case something happened last time
clean_up

/bin/echo "Current macOS is ${currentOS}"

# take a double shot espresso
/usr/bin/caffeinate -dims &

suResult=$(/usr/sbin/softwareupdate -l 2>&1)
case "${suResult}" in
  *NSURLErrorDomain*)
    /bin/echo "Error checking for updates"
    exit 1
    ;;

  *)
    /bin/echo "Software Update check successful"
    ;;
esac

versToInstall=$(/usr/bin/defaults read /Library/Preferences/com.apple.SoftwareUpdate.plist | /usr/bin/grep "${installType}" | /usr/bin/tail -n 1 | /usr/bin/awk -F \" '{print $4}' | /usr/bin/rev | /usr/bin/cut -d "_" -f 2 - | /usr/bin/rev)

if [ "${versToInstall}" = "" ]; then
  /bin/echo "Mac already at latest version"
  exit 0
fi

case "${versToInstall}" in
  15*)
    macOS="Sequoia"
    ;;
    
  14*)
    macOS="Sonoma"
    ;;
    
  13*)
    macOS="Ventura"
    ;;
    
  12*)
    macOS="Monterey"
    ;;

  *)
    /bin/echo "No upgrade or update found"
    exit 0
    ;;
esac

if [ "${installType}" = "minor" ]; then
  /bin/echo "Updating this Mac to ${versToInstall}"
else
  /bin/echo "Upgrading this Mac to ${versToInstall}"
fi

# find the lastest macOS from the catalog file
/usr/bin/curl -s "${suCatURL}" -o "${suCatFILE}"

/usr/bin/grep InstallAssistant.pkg "${suCatFILE}" | /usr/bin/awk -F / '{print $8}' | /usr/bin/cut -d - -f 1-2 - | /usr/bin/uniq > /tmp/prodID.txt

while read -r theProdID; do
  /usr/bin/curl -s "$(/usr/libexec/PlistBuddy -c "Print :Products:${theProdID}:Distributions:English" "${suCatFILE}")" -o /tmp/"${theProdID}".English.dist
  if /usr/bin/grep -q "${macOS}" /tmp/"${theProdID}".English.dist; then
    macOSVER=$(/usr/bin/xmllint --xpath '//installer-gui-script/auxinfo/dict/key[text()="VERSION"]/following-sibling::string[position()=1]/text()' /tmp/"${theProdID}".English.dist)
    /bin/echo "${theProdID},${macOSVER}" >> /tmp/list.csv
  fi
done </tmp/prodID.txt

if [ ! -f /tmp/list.csv ]; then
  /bin/echo "No macOS ${macOS} found"
  exit 0
fi

latestVerProdID=$(grep "${versToInstall}" /tmp/list.csv | /usr/bin/awk -F "," '{print $1}')
downloadURL=$(/usr/libexec/PlistBuddy -c "Print :Products:${latestVerProdID}" "${suCatFILE}" | /usr/bin/grep InstallAssistant.pkg$ | /usr/bin/awk '{print $3}')

macOSInstallApp="/Applications/Install macOS ${macOS}.app"
if [ -d "${macOSInstallApp}" ]; then
  /bin/echo "Deleting an old macOS installer"
  /bin/rm -rf "${macOSInstallApp}"
fi

# see if we have a caching server on the network. pick the first one
if [ "$(/usr/bin/sw_vers -buildVersion | /usr/bin/cut -c 1-2 -)" -ge 24 ]; then
  /bin/echo "macOS Sequoia or later installed. Using jq to extract the data"
  cacheSrvrCount=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/jq '.results.reachability | length')
  case "${cacheSrvrCount}" in
    ''|0)
      /bin/echo "No cache server(s) found"
      ;;

    1)
      /bin/echo "${cacheSrvrCount} server(s) found"
      cacheSrvrURL=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/jq -r ".results.reachability[0]")
      ;;

    *)
      /bin/echo "${cacheSrvrCount} server found"
      cacheSrvrCount=$((cacheSrvrCount-1))
      cacheSrvrSelect=$(jot -r 1 0 "${cacheSrvrCount}")
      cacheSrvrURL=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/jq -r ".results.reachability[${cacheSrvrSelect}]")
      ;;
  esac
else
  /bin/echo "macOS Sonoma or older installed. Using plutil to extract the data"
  cacheSrvrCount=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/plutil -extract results.reachability raw -o - -)
  case "${cacheSrvrCount}" in
    ''|0)
      /bin/echo "No cache server(s) found"
      ;;

    1)
      /bin/echo "${cacheSrvrCount} server(s) found"
      cacheSrvrURL=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/plutil -extract results.reachability.0 raw -o - -)
      ;;

    *)
      /bin/echo "${cacheSrvrCount} server(s) found"
      cacheSrvrCount=$((cacheSrvrCount-1))
      cacheSrvrSelect=$(jot -r 1 0 "${cacheSrvrCount}")
      cacheSrvrURL=$(/usr/bin/AssetCacheLocatorUtil -j 2>/dev/null | /usr/bin/plutil -extract results.reachability."${cacheSrvrSelect}" raw -o - -)
      ;;
  esac
fi
if [ "${cacheSrvrURL}" ]; then
  /bin/echo "Cache server selected. Testing for availablility"
  /usr/bin/curl --telnet-option 'BOGUS=1' --connect-timeout 2 -s telnet://"${cacheSrvrURL}"
  if [ $? = 48 ]; then
    /bin/echo "Cache server reachable"
    baseURL=$(printf '%s' "${downloadURL}" | /usr/bin/cut -d "/" -f 4- -)
    baseURLOpt="?source=swcdn.apple.com&sourceScheme=https"
    downloadURL="http://${cacheSrvrURL}/${baseURL}${baseURLOpt}"
  fi
else
  /bin/echo "Cache Server not found or not reachable"
fi

/bin/echo "Download URL is ${downloadURL}"

/bin/echo "Downloading ${macOS} installer pkg..."
if ! /usr/bin/curl --retry 3 --retry-delay 0 -s "${downloadURL}" -o /private/tmp/Install-macOS-"${macOS}".pkg -C -; then
  /bin/echo "All attempts to download the installer have failed. Exiting"
  exit 1
fi

/bin/echo "Installing the pkg..."
if ! /usr/sbin/installer -pkg /private/tmp/Install-macOS-${macOS}.pkg -target /; then
  /bin/echo "An error occurred installing the pkg. Exiting"
  exit 1
fi

/bin/echo "eraseInstall is ${eraseInstall}"

i=0
startOSInstallCMD="${macOSInstallApp}/Contents/Resources/startosinstall"
until /usr/bin/pgrep startosinstall >/dev/null 2>&1 || [ "$i" -ge "${maxAttempts}" ]; do
  case "${archType}" in
    x86_64)
      /bin/echo "Running attempt $((i + 1)) startosinstall for Intel..."
      if [ "${eraseInstall}" = "YES" ]; then
        "${startOSInstallCMD}" --agreetolicense --forcequitapps --eraseinstall --newvolumename "Macintosh HD" > "${startOSLog}" 2>&1 &
      else
        "${startOSInstallCMD}" --agreetolicense --forcequitapps > "${startOSLog}" 2>&1 &
      fi
      ;;
      
    arm64)
      /bin/echo "Running attempt $((i + 1)) startosinstall for Apple Silicon..."
      if [ "${eraseInstall}" = "YES" ]; then
        su -l "${secureTokenUser}" -c "/bin/echo ${userPass}" | "${startOSInstallCMD}" --agreetolicense --forcequitapps --eraseinstall --newvolumename "Macintosh HD" --user "${secureTokenUser}" --stdinpass > "${startOSLog}" 2>&1 &
      else
        su -l "${secureTokenUser}" -c "/bin/echo ${userPass}" | "${startOSInstallCMD}" --agreetolicense --forcequitapps --user "${secureTokenUser}" --stdinpass > "${startOSLog}" 2>&1 &
      fi
      ;;
  esac
  i=$((i + 1))
  sleep 10
done
if [ "$i" -ge "${maxAttempts}" ]; then
  /bin/echo "startosinstall did not launch. max attempts reached"
  exit 1
fi
