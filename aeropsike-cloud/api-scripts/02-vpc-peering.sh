#!/bin/bash

set -e

source $(dirname $0)/common.sh

# Sanity checks
if [[ -z "${ACS_CLUSTER_ID}" ]]; then
  echo "ACS_CLUSTER_ID is not set. Re-run 01-create-db.sh and reload the environment."
  exit 1
fi

if ! [[ -d "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}" ]]; then
  echo "cluster config directory ${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID} not found, exiting..."
  exit 1
fi

if [[ -z "${VPC_ID}" ]]; then
  echo "VPC_ID is not set"
  exit 1
fi

if [[ -z "${VPC_CIDR}" ]]; then
  echo "VPC_CIDR is not set"
  exit 1
fi

if [[ -z "${VPC_REGION}" ]]; then
  echo "VPC_REGION is not set"
  exit 1
fi

if [[ -z "${AWS_ACCT_ID}" ]]; then
  echo "AWS_ACCT_ID is not set"
  exit 1
fi

if [[ -z "${ACS_AUTH_HEADER}" ]]; then
  echo "ACS_AUTH_HEADER is not set. Re-auth and try again."
  echo "Reloading the environment..."
  direnv allow
  exit 1
fi

VPC_DETAILS=$(cat - <<EOJSON
{
  "vpcId": "${VPC_ID}",
  "cidrBlock": "${VPC_CIDR}",
  "accountId": "${AWS_ACCT_ID}",
  "region": "${VPC_REGION}",
  "secureConnection": true
}
EOJSON
)


echo "REST_API_URI = $REST_API_URI"
echo "VPC_DETAILS = $VPC_DETAILS"

if [[ $(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".count" ) -eq 0 ]]; then
echo "Initiating Peering request"
   HTTP_CODE=$(curl -sX POST "$REST_API_URI/${ACS_CLUSTER_ID}/vpc-peerings" \
    -H "@${ACS_AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "${VPC_DETAILS}" \
    -o /tmp/api.log \
    -w '%{http_code}')

  if [[ ${HTTP_CODE} != "201" ]]; then
    echo "Failed to initiate peering request. Response code:"
    echo $HTTP_CODE
    exit 1
  fi

  sleep 10
else
  echo "VPC peering already exists, skipping peering request"
fi

## Accept request
echo -n "Waiting for Peering status to change from initiating-request to pending-acceptance..."
while [[ $(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".vpcPeerings[0].status" ) == "initiating-request"  ]]; do
	echo -n "."
	sleep 10
done

echo ""

## Get PEERING_ID and ZONE_ID
PEERING_ID=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".vpcPeerings[0].peeringId")
ZONE_ID=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".vpcPeerings[0].privateHostedZoneId")

cat << EOF > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_config.sh"
export PEERING_ID="${PEERING_ID}"
export ZONE_ID="${ZONE_ID}"
EOF

## Force an update of the .envrc file
direnv allow

# Check if the route already exists for a different peering connection
if aws ec2 describe-route-tables \
   --region "${VPC_REGION}" \
   --route-table-id "${ROUTE_TABLE_ID}" \
   --query "RouteTables[0].Routes[?DestinationCidrBlock=='${DEST_CIDR}' && VpcPeeringConnectionId!='${PEERING_ID}']" \
   --output text | grep -q "${DEST_CIDR}"; then
  echo -e "Route to ${DEST_CIDR} already exists, pick a new destination CIDR in .envrc"
  exit 1
fi

# Accept the peering request
if [[ $(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".vpcPeerings[0].status" ) == "pending-acceptance" ]]; then
  echo "Accepting request in PAR AWS account..."
  aws ec2 accept-vpc-peering-connection \
  --vpc-peering-connection-id "${PEERING_ID}" \
  --region "${VPC_REGION}" \
  --no-cli-pager
else
  echo "VPC peering already accepted, skipping acceptance..."
fi

## Create route
echo -n "Waiting for Peering status to change from pending-acceptance to active..."
while [[ $(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r ".vpcPeerings[0].status" ) == "pending-acceptance"  ]]; do
        echo -n "."
        sleep 10
done

echo ""
## Peering status should now be active
acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" > "${ACS_CONFIG_DIR}/vpc-peering.json"
cat "${ACS_CONFIG_DIR}/vpc-peering.json" | jq

echo "Creating route table entry and associating the VPC with the hosted zone"
# Check if route already exists
if aws ec2 describe-route-tables \
   --region "${VPC_REGION}" \
   --route-table-id "${ROUTE_TABLE_ID}" \
   --query "RouteTables[0].Routes[?DestinationCidrBlock=='${DEST_CIDR}' && VpcPeeringConnectionId=='${PEERING_ID}']" \
   --output text | grep -q "${PEERING_ID}"; then
  echo "Route to ${DEST_CIDR} via peering connection ${PEERING_ID} already exists"
else
  echo "Creating route table entry for ${DEST_CIDR} via peering connection ${PEERING_ID}"
  aws ec2 create-route \
    --region "${VPC_REGION}" \
    --route-table-id "${ROUTE_TABLE_ID}" \
    --destination-cidr-block "${DEST_CIDR}" \
    --vpc-peering-connection-id "${PEERING_ID}"
fi

echo "Attempting to associate VPC ${VPC_ID} with hosted zone ${ZONE_ID}"
aws route53 associate-vpc-with-hosted-zone \
  --hosted-zone-id "${ZONE_ID}" \
  --vpc VPCRegion="${VPC_REGION}",VPCId="${VPC_ID}" || echo "VPC association failed, but continuing"

echo "Run this command to resolve DNS for the cluster nodes:"
echo "  dig +short ${ACS_CLUSTER_HOSTNAME}"
echo "---"
dig +short ${ACS_CLUSTER_HOSTNAME}
