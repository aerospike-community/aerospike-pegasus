#!/bin/bash

set -e

source $(dirname $0)/common.sh

# Sanity checks
if [[ -z "${ACS_CLUSTER_NAME}" ]]; then
  echo "ACS_CLUSTER_NAME is not set"
  exit 1
fi

if [[ -z "${DEST_CIDR}" ]]; then
  echo "DEST_CIDR is not set"
  exit 1
fi

if [[ "${DEST_CIDR}" == "10.129.0.0/19" ]]; then
  echo "DEST_CIDR cannot be ${DEST_CIDR} because this is used for the ACS communication to the core services"
  exit 1
fi

if [[ -z "${ACS_AUTH_HEADER}" ]]; then
  echo "ACS_AUTH_HEADER is not set. Re-auth and try again."
  echo "Reloading the environment..."
  direnv allow
  exit 1
fi

# TODO: This is a hack to get the cluster ID, we should use the name instead
ACS_CLUSTER_ID=$(acs_get_cluster_id "${ACS_CLUSTER_NAME}")

if [[ $ACS_CLUSTER_ID == "" ]]; then
  echo "Creating cluster"
  pushd "${CURRENT_PROJECT_ROOT}/project-scripts"

# TODO: This API response includes the cluster ID, so we can use that to set the cluster ID rather than using the name
  HTTP_CODE=$(
    curl "$REST_API_URI" \
         -sX POST \
         -H 'content-type: application/json' \
         -H "@${ACS_AUTH_HEADER}" \
         --data "$(envsubst < ../project-config/acs_cluster_config.json)" \
         -o /dev/null \
         -w '%{http_code}'
  )
  popd

  echo "HTTP code: ${HTTP_CODE}"

  if [[ "${HTTP_CODE}" -ne "202" ]]; then
    echo "Failed to create cluster. Response code:"
    echo $HTTP_CODE
    exit 1
  fi
else
  echo "Cluster already exists"
fi

ACS_CLUSTER_ID=$(acs_get_cluster_id "${ACS_CLUSTER_NAME}")

if [[ $ACS_CLUSTER_ID == "" ]]; then
 echo "Cluster ID was not found. Exiting."
 exit 1
fi

ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}")
ACS_CLUSTER_TLSNAME=$(acs_get_cluster_tls_name "${ACS_CLUSTER_ID}")

mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"

cat << EOF > "${ACS_CONFIG_DIR}/current_cluster.sh"
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
EOF

# Save config for this database
cat << EOF > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
export ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_HOSTNAME}"
export ACS_CLUSTER_TLSNAME="${ACS_CLUSTER_TLSNAME}"
export SERVICE_PORT=4000
EOF

# Force an update of the .envrc file
direnv allow

# Cluster status
echo -n "Waiting for cluster to be provisioned..."
set +e
while [[ $(acs_get_cluster_status "${ACS_CLUSTER_ID}") == "provisioning" ]]; do
	echo -n "."
	sleep 10
done
set -e
echo -e "\n ===== Cluster status changed to "$(acs_get_cluster_status "${ACS_CLUSTER_ID}")" ===== "
