#!/bin/bash

echo "Generating access token (auth.header) for API calls."
echo "Token is valid for 8 hours."

mkdir -p "${ACS_CONFIG_DIR}"

AUTH_STRING=$(cat - <<EOJSON
{
  "client_id":"${ACS_CLIENT_ID}",
  "client_secret":"${ACS_CLIENT_SECRET}",
  "grant_type":"client_credentials"
}
EOJSON
)

curl -s --request POST \
     --url "${AUTH_API_URI}" \
     --header 'content-type: application/json' \
     --data "${AUTH_STRING}" > "${ACS_CONFIG_DIR}/token.json"

echo "Authorization: Bearer $(jq -r ."access_token" "${ACS_CONFIG_DIR}/token.json")" > "${ACS_CONFIG_DIR}/auth.header"
