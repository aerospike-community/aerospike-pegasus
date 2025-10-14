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
    echo "⚠️  No cluster found in tracker (may already be deleted)"
    return 0
fi

source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Check if VPC peering config exists
VPC_PEERING_CONFIG="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh"

if [ ! -f "$VPC_PEERING_CONFIG" ]; then
    echo "No VPC peering configuration found."
    echo "Checking API for existing peering..."
    
    PEERING_JSON=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}")
    PEERING_COUNT=$(echo "$PEERING_JSON" | jq -r '.count // 0' 2>/dev/null)
    
    if [[ "$PEERING_COUNT" -eq 0 ]]; then
        echo "No VPC peering found for cluster ${ACS_CLUSTER_NAME}"
        return 0
    fi
    
    # Extract details from API response
    PEERING_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].peeringId // ""')
    CLIENT_VPC_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].vpcId // ""')
    DEST_CIDR=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].cidrBlock // ""')
    ZONE_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].hostedZoneId // ""')
    
    echo "Found peering from API:"
    echo "  Peering ID: ${PEERING_ID}"
    echo "  Client VPC: ${CLIENT_VPC_ID}"
    echo "  Cluster CIDR: ${DEST_CIDR}"
    echo "  Zone ID: ${ZONE_ID}"
    echo ""
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
        return 0
    fi
fi

echo ""
echo "Deleting VPC peering..."

# Step 1: Clean up route table entries
echo ""
echo "Cleaning up route table entries..."
if [ -n "$CLIENT_VPC_ID" ] && [ -n "$DEST_CIDR" ]; then
    # Get route tables for client VPC
    ROUTE_TABLES=$(aws ec2 describe-route-tables \
        --region "${CLIENT_AWS_REGION}" \
        --filters "Name=vpc-id,Values=${CLIENT_VPC_ID}" \
        --query 'RouteTables[*].RouteTableId' \
        --output text 2>/dev/null)
    
    if [ -n "$ROUTE_TABLES" ]; then
        for RT_ID in $ROUTE_TABLES; do
            echo "  Checking route table: ${RT_ID}"
            # Delete route to cluster CIDR if it exists
            aws ec2 delete-route \
                --region "${CLIENT_AWS_REGION}" \
                --route-table-id "${RT_ID}" \
                --destination-cidr-block "${DEST_CIDR}" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                echo "    ✓ Deleted route to ${DEST_CIDR}"
            else
                echo "    ℹ️  No route to ${DEST_CIDR} (may already be deleted)"
            fi
        done
    else
        echo "  ℹ️  No route tables found for VPC ${CLIENT_VPC_ID}"
    fi
else
    echo "  ⚠️  Skipping route cleanup (missing VPC or CIDR info)"
fi

# Step 2: Disassociate Route53 hosted zone from VPC
echo ""
echo "Disassociating Route53 hosted zone..."
if [ -n "$ZONE_ID" ] && [ -n "$CLIENT_VPC_ID" ]; then
    aws route53 disassociate-vpc-from-hosted-zone \
        --hosted-zone-id "${ZONE_ID}" \
        --vpc VPCRegion="${CLIENT_AWS_REGION}",VPCId="${CLIENT_VPC_ID}" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Disassociated VPC ${CLIENT_VPC_ID} from hosted zone ${ZONE_ID}"
    else
        echo "  ℹ️  VPC association not found or already removed"
    fi
else
    echo "  ⚠️  Skipping Route53 cleanup (missing zone or VPC info)"
fi

# Step 3: Delete VPC peering connection from AWS (accepter side)
echo ""
echo "Deleting VPC peering connection from AWS..."
if [ -n "$PEERING_ID" ]; then
    aws ec2 delete-vpc-peering-connection \
        --region "${CLIENT_AWS_REGION}" \
        --vpc-peering-connection-id "${PEERING_ID}" > /dev/null 2>&1
    
    if [ $? -eq 0 ]; then
        echo "  ✓ Deleted VPC peering connection ${PEERING_ID} from AWS"
    else
        echo "  ℹ️  VPC peering connection not found in AWS (may already be deleted)"
    fi
fi

# Step 4: Delete via Aerospike Cloud API
echo ""
echo "Deleting VPC peering from Aerospike Cloud..."
HTTP_CODE=$(curl -sX DELETE "$REST_API_URI/${ACS_CLUSTER_ID}/vpc-peerings/${PEERING_ID}" \
    -H "@${ACS_AUTH_HEADER}" \
    -w '%{http_code}' \
    -o /dev/null)

if [[ "${HTTP_CODE}" == "204" ]] || [[ "${HTTP_CODE}" == "200" ]]; then
    echo "  ✓ VPC peering deleted from Aerospike Cloud"
else
    echo "  ⚠️  Warning: Failed to delete VPC peering from API (HTTP ${HTTP_CODE})"
    echo "     The peering may have been already deleted"
fi

# Step 5: Clean up local configuration files
echo ""
echo "Cleaning up local configuration files..."
if [ -f "$VPC_PEERING_CONFIG" ]; then
    rm -f "$VPC_PEERING_CONFIG"
    echo "  ✓ Removed ${VPC_PEERING_CONFIG}"
fi

if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/vpc_peering_state.sh" ]; then
    rm -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/vpc_peering_state.sh"
    echo "  ✓ Removed vpc_peering_state.sh"
fi

echo ""
echo "====================================="
echo "✓ VPC Peering Destroy Complete!"
echo "====================================="
echo ""
echo "All VPC peering resources have been cleaned up:"
echo "  ✓ Route table entries removed"
echo "  ✓ Route53 VPC association removed"
echo "  ✓ AWS VPC peering connection deleted"
echo "  ✓ Aerospike Cloud peering deleted"
echo "  ✓ Local configuration files removed"
echo ""

