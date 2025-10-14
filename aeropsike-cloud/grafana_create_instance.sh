#!/bin/bash

# Load common configurations
PREFIX=$(pwd "$0")"/"$(dirname "$0")
. $PREFIX/configure.sh

# Ensure cluster ID is available (for naming)
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "❌ ERROR: Cluster configuration not found!"
    echo "Please run './setup.sh' to complete cluster setup."
    exit 1
fi
source "${ACS_CONFIG_DIR}/current_cluster.sh"

echo "============================================"
echo "Aerospike Cloud - Grafana Instance Creation"
echo "============================================"
echo ""

echo "Creating Grafana instance for cluster: ${ACS_CLUSTER_NAME}"
echo "  Cluster ID: ${ACS_CLUSTER_ID}"
echo ""

# ============================================
# Check if Grafana already exists
# ============================================

echo "Checking if Grafana '${GRAFANA_NAME}' already exists..."

# Configure aerolab backend
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null

EXISTING_GRAFANA=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${GRAFANA_NAME}\") | .ClientName" | head -1)

if [ -n "$EXISTING_GRAFANA" ]; then
    echo "✓ Grafana instance '${GRAFANA_NAME}' already exists"
    echo ""
    
    # Get Grafana details
    GRAFANA_INFO=$(aerolab client list -j 2>/dev/null | jq ".[] | select(.ClientName == \"${GRAFANA_NAME}\")")
    GRAFANA_IP=$(echo "$GRAFANA_INFO" | jq -r '.PublicIp')
    GRAFANA_INSTANCE_ID=$(echo "$GRAFANA_INFO" | jq -r '.InstanceId')
    
    if [ -n "$GRAFANA_IP" ]; then
        echo "Grafana Details:"
        echo "  Public IP: ${GRAFANA_IP}"
        echo "  Instance ID: ${GRAFANA_INSTANCE_ID}"
        echo "  Dashboard URL: http://${GRAFANA_IP}:3000"
        echo ""
        
        # Save basic Grafana config (without Prometheus endpoints yet)
        GRAFANA_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
        mkdir -p "$(dirname "$GRAFANA_CONFIG_FILE")"
        cat > "${GRAFANA_CONFIG_FILE}" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
EOF
        
        echo "✓ Grafana configuration saved to: ${GRAFANA_CONFIG_FILE}"
        echo ""
        echo "Note: Prometheus configuration will be done after VPC peering is complete."
    fi
    
    exit 0
fi

echo "Grafana instance does not exist, creating..."
echo ""

# ============================================
# Create Grafana AMS instance
# ============================================

echo "Creating Aerospike Monitoring Stack (AMS)..."
echo "  Name: ${GRAFANA_NAME}"
echo "  Instance Type: ${GRAFANA_INSTANCE_TYPE}"
echo "  Region: ${CLIENT_AWS_REGION}"
echo ""

# Need to get client VPC details to create Grafana in same VPC
if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
    echo "❌ ERROR: Client configuration not found!"
    echo "Grafana needs to be in the same VPC as the client to access cluster metrics."
    exit 1
fi

source "${CLIENT_CONFIG_DIR}/client_config.sh"

echo "Note: Grafana will be created in the same VPC as the client to access cluster metrics."
echo "  VPC ID: ${CLIENT_VPC_ID}"
echo ""

# Create AMS instance WITHOUT cluster source
# We'll configure Prometheus later after VPC peering is done
aerolab client create ams \
    -n "${GRAFANA_NAME}" \
    --instance-type "${GRAFANA_INSTANCE_TYPE}" \
    --ebs=40 \
    --aws-expire="${GRAFANA_AWS_EXPIRE}"

if [ $? -ne 0 ]; then
    echo ""
    echo "❌ ERROR: Failed to create Grafana instance!"
    exit 1
fi

echo ""
echo "✓ Grafana instance created successfully!"
echo ""

# ============================================
# Get Grafana IP and save config
# ============================================

echo "Retrieving Grafana connection details..."

# Wait a moment for aerolab to register the instance
sleep 2

GRAFANA_INFO=$(aerolab client list -j 2>/dev/null | jq ".[] | select(.ClientName == \"${GRAFANA_NAME}\")")

if [ -z "$GRAFANA_INFO" ]; then
    echo "⚠️  WARNING: Could not retrieve Grafana details immediately"
    echo "Run 'aerolab client list' to get the Grafana IP"
    exit 0
fi

GRAFANA_IP=$(echo "$GRAFANA_INFO" | jq -r '.PublicIp')
GRAFANA_PRIVATE_IP=$(echo "$GRAFANA_INFO" | jq -r '.PrivateIp')
GRAFANA_INSTANCE_ID=$(echo "$GRAFANA_INFO" | jq -r '.InstanceId')

echo "✓ Grafana instance details retrieved"
echo "  Public IP: ${GRAFANA_IP}"
echo "  Private IP: ${GRAFANA_PRIVATE_IP}"
echo ""

# Save Grafana configuration (without Prometheus endpoints - will be added later)
GRAFANA_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
mkdir -p "$(dirname "$GRAFANA_CONFIG_FILE")"

cat > "${GRAFANA_CONFIG_FILE}" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_PRIVATE_IP="${GRAFANA_PRIVATE_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
EOF

echo "✓ Grafana configuration saved to: ${GRAFANA_CONFIG_FILE}"
echo ""

# ============================================
# Display connection information
# ============================================

echo "============================================"
echo "✓ Grafana Instance Creation Complete!"
echo "============================================"
echo ""
echo "Grafana Dashboard URL: http://${GRAFANA_IP}:3000"
echo ""
echo "Default credentials:"
echo "  Username: admin"
echo "  Password: admin"
echo ""
echo "Instance Details:"
echo "  Name: ${GRAFANA_NAME}"
echo "  Public IP: ${GRAFANA_IP}"
echo "  Private IP: ${GRAFANA_PRIVATE_IP}"
echo "  Instance ID: ${GRAFANA_INSTANCE_ID}"
echo ""
echo "⚠️  Note: Prometheus is not yet configured to scrape the Aerospike cluster."
echo "   This will be done automatically after VPC peering is complete."
echo ""

