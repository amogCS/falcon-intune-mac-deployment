#!/bin/bash

set -e

# Configuration - Add this before uploading - It's a shame that Intune doesn't
# have secrets support... :(

# Copy these three values from the OAuth2 API Clients page
# (Support > API Clients and Keys). If BASE_URL is not provided,
# then the script will try to determine it automatically.
CLIENT_ID=
CLIENT_SECRET=
BASE_URL=

# Copy this value from the Sensor Downloads (Hosts > Sensor Downloads) page.
CS_CCID=

# Copy this value from the Installation Tokens (Hosts > Installation Tokens)
# page.
CS_INSTALL_TOKEN=

export PATH=/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin
FALCONCTL=/Applications/Falcon.app/Contents/Resources/falconctl
PKG_FILE="${TMPDIR:-/tmp}/FalconSensorMacOS.pkg"

if (( EUID )); then
    echo "This script must be run as root"
    exit 1
fi

function fetch_json_path() {
    local field_str=''
    for i in "$@"; do
        if [[ $i =~ ^[[:digit:]]*$ ]]; then
            field_str="${field_str}->[${i}]"
        else
            field_str="${field_str}->{'${i}'}"
        fi
    done
    json_xs -t none -e "print \$_${field_str}"
}

function get_access_token() {
    if [[ -z $BASE_URL ]]; then
        # If BASE_URL isn't provided, then look for a redirect from the oauth2
        # token request.
        default_base_url='https://api.crowdstrike.com'
        BASE_URL=$(curl -s -v -X POST -d "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}" "${default_base_url}/oauth2/token" 2>&1 | awk '($2 == "location:") {print $3}')
        if [[ -n $BASE_URL ]]; then
            # We got a redirect, so strip the path portion and that's the
            # BASE_URL
            BASE_URL=$(echo "${BASE_URL}" | cut -d/ -f1-3)
        else
            # No redirect, so the BASE_URL is the default.
            BASE_URL="${default_base_url}"
        fi
    fi
    curl -s -X POST -d "client_id=${CLIENT_ID}&client_secret=${CLIENT_SECRET}" "${BASE_URL}/oauth2/token" | \
        fetch_json_path access_token
}

function get_sha256() {
    curl -s -H "Authorization: Bearer ${1}" "${BASE_URL}/sensors/combined/installers/v1?filter=platform%3A%22mac%22" | \
        fetch_json_path resources 0 sha256
}

if [[ -x $FALCONCTL ]] && "${FALCONCTL}" stats 2>&1 | grep -F 'Sensor operational: true' > /dev/null; then
    echo 'Crowdstrike Falcon is installed and operational'
else
    APITOKEN=$(get_access_token)
    FALCON_LATEST_SHA256=$(get_sha256 "${APITOKEN}")
    rm -f "${PKG_FILE}"
    curl -o "${PKG_FILE}" -s -H "Authorization: Bearer ${APITOKEN}" "${BASE_URL}/sensors/entities/download-installer/v1?id=${FALCON_LATEST_SHA256}"
    installer -verboseR -package "${PKG_FILE}" -target /
    rm -f "${PKG_FILE}"
    "${FALCONCTL}" license "${CS_CCID}" "${CS_INSTALL_TOKEN}" || true # Don't fail if the app is already licensed, but still needs a reinstall
fi

exit 0
