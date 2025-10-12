#!/bin/bash
source ${CURRENT_PROJECT_ROOT}/project-scripts/common.sh

set -e

echo "Updating cluster in ${ACS_ENV} environment..."

if [ $ACS_ENV == "staging"  ]; then
  echo "THIS WORKBENCH DOES NOT SUPPORT STAGE"
  exit 1
fi

# Change the cluster size (horizontal scaling), instance type (vertical scaling), 
# or any modifiable config parameters
echo "There are currenly no guard-rails, so cowardly refusing to run, edit me."
exit 1
CLUSTER_CONFIG=$(envsubst < ../project-config/acs_cluster_config.json)

#TODO: Sanity check the cluster size requested against current size?
#      Same for instance type?

echo "Sending update request at $(date -u)"
echo "cluster config: ${CLUSTER_CONFIG}"

HTTP_CODE=$(curl -X PATCH "$REST_API_URI/$ACS_CLUSTER_ID" \
  -H "@${ACS_AUTH_HEADER}" \
  -H "Content-Type: application/merge-patch+json" \
  -d "${CLUSTER_CONFIG}" \
  -o /dev/null
  -w '%{http_code}')

if [[ ${HTTP_CODE} != "202" ]]; then
  echo "Failed to submit scaling request. Response code:"
  echo $HTTP_CODE
  exit 1
fi
