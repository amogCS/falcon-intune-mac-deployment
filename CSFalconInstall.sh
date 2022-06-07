#!/bin/bash

# Configuration - Add this before uploading to Intune - It's a shame that Intune doesn't have secrets support... :(
# Both CLIENT_ID, CLIENT_SECRET, and BASE_URL are generated/found when creating a new API Key within the Falcon Platform.
# Base_URL is different in each Falcon Cloud. US-1, US-2, EU, and GovCloud. 
    #US-1: https://api.crowdstrike.com
    #US-2: https://api.us-2.crowdstrike.com
    #EU: https://api.eu-1.crowdstrike.com
    #GovCloud: https://api.laggar.gcw.crowdstrike.com
# FILE_NAME is the name of the Falcon Sensor file. This can be found by downloading the Falcon Sensor from the your Falcon Instance and noting the name of the file. 
# CS_CCID: Customer ID + Checksum. Found at the top of the Sensor Downloads page within the Falcon Console
# CS_INSTALL_TOKEN: This is optional, Leave blank if you do not have Installation Tokens configured.

CLIENT_ID=
CLIENT_SECRET=
BASE_URL=
FILE_NAME=
CS_CCID=
CS_INSTALL_TOKEN=

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

get_access_token() {
    json=$(curl -s -X POST -d "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}" ${BASE_URL}/oauth2/token)
    echo "function run() { let result = JSON.parse(\`$json\`); return result.access_token; }" | osascript -l JavaScript
}

get_sha256() {
    json=$(curl -s -H "Authorization: Bearer ${1}" ${BASE_URL}/sensors/combined/installers/v1\?filter=platform%3A%22mac%22)
    echo "function run() { let result = JSON.parse(\`$json\`); return result.resources[0].sha256; }" | osascript -l JavaScript
}

if [ ! -x "/Applications/Falcon.app/Contents/Resources/falconctl" ] || [ -z "$(/Applications/Falcon.app/Contents/Resources/falconctl stats | grep 'Sensor operational: true')" ]; then
    APITOKEN=$(get_access_token)
    FALCON_LATEST_SHA256=$(get_sha256 "${APITOKEN}")
    curl -o /tmp/${FILE_NAME} -s -H "Authorization: Bearer ${APITOKEN}" ${BASE_URL}/sensors/entities/download-installer/v1?id=${FALCON_LATEST_SHA256}
    installer -verboseR -package /tmp/${FILE_NAME} -target /
    rm /tmp/${FILE_NAME}
    /Applications/Falcon.app/Contents/Resources/falconctl license ${CS_CCID} ${CS_INSTALL_TOKEN} || true # Don't fail if the app is already licensed, but still needs a reinstall
else
    echo "Crowdstrike Falcon is installed and operational"
fi
