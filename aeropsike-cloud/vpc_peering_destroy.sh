#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Source common functions
. $PREFIX/api-scripts/common.sh

echo "====================================="
echo "Aerospike Cloud - VPC Peering Destroy"
echo "====================================="
echo ""

# Check if cluster exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "ERROR: No cluster found!"
    exit 1
fi

source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Check if VPC peering config exists
VPC_PEERING_CONFIG="${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh"

if [ ! -f "$VPC_PEERING_CONFIG" ]; then
    echo "No VPC peering configuration found."
    echo "Checking API for existing peering..."
    
    PEERING_COUNT=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r '.count // 0' 2>/dev/null)
    
    if [[ "$PEERING_COUNT" -eq 0 ]]; then
        echo "No VPC peering found for cluster ${ACS_CLUSTER_NAME}"
        exit 0
    fi
    
    PEERING_ID=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r '.vpcPeerings[0].peeringId // ""')
    echo "Found peering: ${PEERING_ID}"
else
    source "$VPC_PEERING_CONFIG"
    echo "Found VPC peering configuration:"
    echo "  Peering ID: ${PEERING_ID}"
    echo "  Client VPC: ${CLIENT_VPC_ID}"
    echo ""
fi

# Confirm deletion
if [[ "$1" != "--yes" ]] && [[ "$1" != "-y" ]]; then
    read -p "Are you sure you want to delete VPC peering '${PEERING_ID}'? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled."
        exit 0
    fi
fi

echo ""
echo "Deleting VPC peering..."

# Delete via Aerospike Cloud API
HTTP_CODE=$(curl -sX DELETE "$REST_API_URI/${ACS_CLUSTER_ID}/vpc-peerings/${PEERING_ID}" \
    -H "@${ACS_AUTH_HEADER}" \
    -w '%{http_code}' \
    -o /dev/null)

if [[ "${HTTP_CODE}" == "204" ]] || [[ "${HTTP_CODE}" == "200" ]]; then
    echo "✓ VPC peering deleted from Aerospike Cloud"
else
    echo "⚠️  Warning: Failed to delete VPC peering from API (HTTP ${HTTP_CODE})"
    echo "   The peering may have been already deleted or you may need to delete it manually"
fi

# Clean up local configuration
if [ -f "$VPC_PEERING_CONFIG" ]; then
    rm -f "$VPC_PEERING_CONFIG"
    echo "✓ Removed ${VPC_PEERING_CONFIG}"
fi

if [ -f "${ACS_CONFIG_DIR}/vpc_peering_state.sh" ]; then
    rm -f "${ACS_CONFIG_DIR}/vpc_peering_state.sh"
    echo "✓ Removed vpc_peering_state.sh"
fi

echo ""
echo "====================================="
echo "✓ VPC Peering Destroy Complete!"
echo "====================================="
echo ""
echo "Note: The following may need manual cleanup in AWS:"
echo "  1. VPC Peering Connection: ${PEERING_ID}"
echo "  2. Route table entries to ${DEST_CIDR}"
echo "  3. Route53 VPC associations with zone ${ZONE_ID}"
echo ""
echo "To clean up routes, run:"
echo "  aws ec2 delete-route --route-table-id <ROUTE_TABLE_ID> --destination-cidr-block ${DEST_CIDR} --region ${CLIENT_AWS_REGION}"
echo ""

