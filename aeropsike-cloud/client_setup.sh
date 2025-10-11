#!/bin/bash

if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

echo "====================================="
echo "Aerospike Cloud - Client Setup"
echo "====================================="
echo ""

# Check if cluster exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "ERROR: No Aerospike Cloud cluster found!"
    echo "Please run './setup.sh' first to create a cluster."
    exit 1
fi

# Load cluster info
source "${ACS_CONFIG_DIR}/current_cluster.sh"
echo "Setting up client for cluster: ${ACS_CLUSTER_NAME}"
echo "  Cluster ID: ${ACS_CLUSTER_ID}"
echo ""

# Create client config directory
mkdir -p "${CLIENT_CONFIG_DIR}"

# Check if client already exists
echo "Checking if client '${CLIENT_NAME}' already exists..."
CLIENT_EXISTS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${CLIENT_NAME}\") | .ClientName" | head -1)

if [ -n "$CLIENT_EXISTS" ]; then
    echo "✓ Client '${CLIENT_NAME}' already exists"
    echo ""
    echo "Extracting client details..."
else
    echo "Creating new client..."
    echo ""
    
    # Configure aerolab backend
    echo "Configuring aerolab for AWS region: ${CLIENT_AWS_REGION}"
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" || exit 1
    
    # Create VPC for client (aerolab will create a new VPC if not specified)
    echo ""
    echo "Creating client instance(s)..."
    echo "  Name: ${CLIENT_NAME}"
    echo "  Instance Type: ${CLIENT_INSTANCE_TYPE}"
    echo "  Number of Nodes: ${CLIENT_NUMBER_OF_NODES}"
    echo "  Region: ${CLIENT_AWS_REGION}"
    echo "  VPC CIDR: ${CLIENT_VPC_CIDR} (new VPC will be created)"
    echo ""
    
    # Create client with aerolab - it will create a new VPC automatically
    aerolab client create base \
        -c "${CLIENT_NUMBER_OF_NODES}" \
        -n "${CLIENT_NAME}" \
        --instance-type "${CLIENT_INSTANCE_TYPE}" \
        --ebs=50 \
        --aws-expire="${CLIENT_AWS_EXPIRE}" || exit 1
    
    echo ""
    echo "✓ Client created successfully!"
fi

echo ""
echo "====================================="
echo "Extracting Client Details"
echo "====================================="
echo ""

# Get client details from aerolab
CLIENT_INFO=$(aerolab client list -j 2>/dev/null | jq "[.[] | select(.ClientName == \"${CLIENT_NAME}\")]")

if [ -z "$CLIENT_INFO" ] || [ "$CLIENT_INFO" == "[]" ]; then
    echo "ERROR: Failed to get client details from aerolab"
    exit 1
fi

# Extract instance IDs (each node is a separate object in the array)
CLIENT_INSTANCE_IDS=$(echo "$CLIENT_INFO" | jq -r '.[].InstanceId' | tr '\n' ',' | sed 's/,$//')
echo "Instance IDs: ${CLIENT_INSTANCE_IDS}"

# Get VPC details using AWS CLI
echo ""
echo "Querying AWS for VPC and network details..."

# Get the first instance ID to query VPC details
FIRST_INSTANCE_ID=$(echo "$CLIENT_INFO" | jq -r '.[0].InstanceId')

# Query VPC ID from instance
CLIENT_VPC_ID=$(aws ec2 describe-instances \
    --instance-ids "${FIRST_INSTANCE_ID}" \
    --region "${CLIENT_AWS_REGION}" \
    --query 'Reservations[0].Instances[0].VpcId' \
    --output text 2>/dev/null)

if [ -z "$CLIENT_VPC_ID" ] || [ "$CLIENT_VPC_ID" == "None" ]; then
    echo "WARNING: Could not retrieve VPC ID from AWS"
    CLIENT_VPC_ID="unknown"
else
    echo "VPC ID: ${CLIENT_VPC_ID}"
fi

# Query Subnet IDs
CLIENT_SUBNET_IDS=$(aws ec2 describe-instances \
    --instance-ids ${CLIENT_INSTANCE_IDS//,/ } \
    --region "${CLIENT_AWS_REGION}" \
    --query 'Reservations[].Instances[].SubnetId' \
    --output text 2>/dev/null | tr '\t' ',' | tr ' ' ',')

echo "Subnet IDs: ${CLIENT_SUBNET_IDS}"

# Query Security Group IDs
CLIENT_SECURITY_GROUPS=$(aws ec2 describe-instances \
    --instance-ids "${FIRST_INSTANCE_ID}" \
    --region "${CLIENT_AWS_REGION}" \
    --query 'Reservations[0].Instances[0].SecurityGroups[].GroupId' \
    --output text 2>/dev/null | tr '\t' ',' | tr ' ' ',')

echo "Security Group IDs: ${CLIENT_SECURITY_GROUPS}"

# Get VPC CIDR from AWS
if [ "$CLIENT_VPC_ID" != "unknown" ]; then
    ACTUAL_VPC_CIDR=$(aws ec2 describe-vpcs \
        --vpc-ids "${CLIENT_VPC_ID}" \
        --region "${CLIENT_AWS_REGION}" \
        --query 'Vpcs[0].CidrBlock' \
        --output text 2>/dev/null)
    echo "VPC CIDR: ${ACTUAL_VPC_CIDR}"
else
    ACTUAL_VPC_CIDR="unknown"
fi

# Get instance IPs (each node is a separate object)
CLIENT_PRIVATE_IPS=$(echo "$CLIENT_INFO" | jq -r '.[].PrivateIp' | tr '\n' ',' | sed 's/,$//')
CLIENT_PUBLIC_IPS=$(echo "$CLIENT_INFO" | jq -r '.[].PublicIp' | tr '\n' ',' | sed 's/,$//')

echo "Private IPs: ${CLIENT_PRIVATE_IPS}"
echo "Public IPs: ${CLIENT_PUBLIC_IPS}"

echo ""
echo "====================================="
echo "Saving Client Configuration"
echo "====================================="
echo ""

# Save client configuration to tracking file
cat > "${CLIENT_CONFIG_DIR}/client_config.sh" <<EOF
# Aerospike Cloud - Client Configuration
# Generated on: $(date)

# Cluster Association
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"

# Client Basic Info
export CLIENT_NAME="${CLIENT_NAME}"
export CLIENT_NUMBER_OF_NODES="${CLIENT_NUMBER_OF_NODES}"
export CLIENT_INSTANCE_TYPE="${CLIENT_INSTANCE_TYPE}"
export CLIENT_AWS_REGION="${CLIENT_AWS_REGION}"

# AWS Instance Details
export CLIENT_INSTANCE_IDS="${CLIENT_INSTANCE_IDS}"
export CLIENT_PRIVATE_IPS="${CLIENT_PRIVATE_IPS}"
export CLIENT_PUBLIC_IPS="${CLIENT_PUBLIC_IPS}"

# AWS Network Details
export CLIENT_VPC_ID="${CLIENT_VPC_ID}"
export CLIENT_VPC_CIDR="${ACTUAL_VPC_CIDR}"
export CLIENT_SUBNET_IDS="${CLIENT_SUBNET_IDS}"
export CLIENT_SECURITY_GROUPS="${CLIENT_SECURITY_GROUPS}"
EOF

echo "✓ Client configuration saved to:"
echo "  ${CLIENT_CONFIG_DIR}/client_config.sh"

# Also save JSON format for easier parsing
echo "$CLIENT_INFO" > "${CLIENT_CONFIG_DIR}/client_info.json"
echo "✓ Client details saved to:"
echo "  ${CLIENT_CONFIG_DIR}/client_info.json"

echo ""
echo "====================================="
echo "✓ Client Setup Complete!"
echo "====================================="
echo ""
echo "Client Details:"
echo "  Name: ${CLIENT_NAME}"
echo "  VPC ID: ${CLIENT_VPC_ID}"
echo "  VPC CIDR: ${ACTUAL_VPC_CIDR}"
echo "  Instance IDs: ${CLIENT_INSTANCE_IDS}"
echo "  Public IPs: ${CLIENT_PUBLIC_IPS}"
echo ""
echo "Next Steps:"
echo "  1. Run VPC peering setup to connect client to cluster"
echo "  2. Build and deploy Perseus workload"
echo ""

# Continue with Perseus build (if requested)
# Skip Perseus by default during parallel setup to save time
if [[ "$1" == "--build-perseus" ]] || [[ "$BUILD_PERSEUS" == "true" ]]; then
    echo "Continuing with Perseus build..."
    . $PREFIX/../client/buildPerseus.sh
else
    echo "Skipping Perseus build (run './client/buildPerseus.sh' manually later)"
fi