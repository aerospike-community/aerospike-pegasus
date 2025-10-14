#!/bin/bash

# Load configuration
if [ -z "$PREFIX" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PREFIX="${SCRIPT_DIR}/../aeropsike-cloud"
    . $PREFIX/configure.sh
fi

echo "Uploading the Perseus Setup File"

# Configure aerolab backend
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null

aerolab files upload -c -n ${CLIENT_NAME} "${SCRIPT_DIR}/templates/perseus_setup.sh" /root/perseus_setup.sh || exit 1

echo "Building Perseus"
aerolab client attach -n ${CLIENT_NAME} -l all --parallel -- bash /root/perseus_setup.sh