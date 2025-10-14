#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Source common functions
. $PREFIX/api-scripts/common.sh

echo "============================================"
echo "Aerospike Cloud - Grafana Setup"
echo "============================================"
echo ""

# ============================================
# Validation
# ============================================

# Check if cluster exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "❌ ERROR: No cluster found!"
    echo "Please run './setup.sh' first to create a cluster."
    exit 1
fi

source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Check if cluster is active
if [ "$ACS_CLUSTER_STATUS" != "active" ]; then
    echo "❌ ERROR: Cluster is not active yet!"
    echo "Current status: ${ACS_CLUSTER_STATUS}"
    echo "Please wait for cluster to become active."
    exit 1
fi

# Check if cluster config exists
if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
    echo "❌ ERROR: Cluster configuration not found!"
    echo "Please run './setup.sh' to complete cluster setup."
    exit 1
fi

source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"

echo "Setting up Grafana for cluster: ${ACS_CLUSTER_NAME}"
echo "  Cluster ID: ${ACS_CLUSTER_ID}"
echo "  Cluster Hostname: ${ACS_CLUSTER_HOSTNAME}"
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
        echo "Grafana Dashboard URL: http://${GRAFANA_IP}:3000"
        echo ""
        echo "Default credentials:"
        echo "  Username: admin"
        echo "  Password: admin"
        echo ""
        
        # Get cluster IPs from config if available
        CLUSTER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
        if [ -f "$CLUSTER_CONFIG_FILE" ]; then
            source "$CLUSTER_CONFIG_FILE"
        fi
        
        if [ -n "${CLUSTER_IPS}" ]; then
            CLUSTER_ENDPOINTS="${CLUSTER_IPS}"
        else
            CLUSTER_ENDPOINTS="${ACS_CLUSTER_HOSTNAME}:${PROMETHEUS_PORT}"
        fi
        
        # Save Grafana config
        GRAFANA_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
        cat > "${GRAFANA_CONFIG_FILE}" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
export CLUSTER_METRICS_ENDPOINTS="${CLUSTER_ENDPOINTS}"
EOF
        
        echo "✓ Grafana configuration saved to: ${GRAFANA_CONFIG_FILE}"
        echo ""
        echo "Note: If Prometheus is not configured yet, you can manually configure it:"
        echo "  1. SSH to Grafana: aerolab client attach -n ${GRAFANA_NAME}"
        echo "  2. Edit: /etc/prometheus/prometheus.yml"
        echo "  3. Add job for: ${CLUSTER_ENDPOINTS}"
        echo "  4. Restart: sudo systemctl restart prometheus"
        
        # Open browser
        if command -v open &> /dev/null; then
            open "http://${GRAFANA_IP}:3000"
        fi
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
echo "⚠️  Creating without cluster source - will configure Prometheus after creation"
echo ""

# Create AMS instance WITHOUT cluster source
# We can't use -s flag because aerolab validates connectivity from local machine
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
# Get Grafana IP and display info
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

echo "✓ Grafana instance created successfully"
echo "  Public IP: ${GRAFANA_IP}"
echo "  Private IP: ${GRAFANA_PRIVATE_IP}"
echo ""

# ============================================
# Configure Prometheus to scrape cluster
# ============================================

echo "Configuring Prometheus to scrape Aerospike Cloud cluster..."
echo ""

# Get cluster IPs - try from config first, then resolve via client
CLUSTER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
if [ -f "$CLUSTER_CONFIG_FILE" ]; then
    source "$CLUSTER_CONFIG_FILE"
fi

if [ -z "${CLUSTER_IPS}" ] || [ "${CLUSTER_IPS}" == "null" ]; then
    echo "⚠️  WARNING: Cluster IPs not found in configuration"
    echo "Prometheus configuration will be skipped."
    echo ""
    echo "To configure Prometheus, please run VPC peering setup to resolve IPs:"
    echo "  cd aeropsike-cloud && ./vpc_peering_setup.sh"
    echo ""
    CLUSTER_IPS=""
else
    echo "✓ Using cluster IPs from config: ${CLUSTER_IPS}"
fi

# Configure Prometheus if we have IPs
if [ -n "$CLUSTER_IPS" ]; then
    echo ""
    echo "Adding Aerospike cluster to Prometheus scrape config..."
    
    # Wait for Grafana instance to be fully ready
    echo "Waiting for Grafana instance to be ready (30 seconds)..."
    sleep 30
    
    # Build scrape targets (each on its own line to avoid spacing issues)
    SCRAPE_TARGETS=""
    IFS=',' read -ra IPS <<< "$CLUSTER_IPS"
    for ip in "${IPS[@]}"; do
        SCRAPE_TARGETS="${SCRAPE_TARGETS}
        - ${ip}:${PROMETHEUS_PORT}"
    done
    
    # Create the scrape config with proper YAML formatting
    SCRAPE_CONFIG="  - job_name: aerospike-cloud
    static_configs:
      - targets:${SCRAPE_TARGETS}"
    
    # Add to Prometheus config via SSH
    echo "Updating Prometheus configuration..."
    aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "echo '${SCRAPE_CONFIG}' | sudo tee -a /etc/prometheus/prometheus.yml > /dev/null" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        # Restart Prometheus to apply changes
        echo "Restarting Prometheus..."
        aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "sudo systemctl restart prometheus" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            echo "✓ Prometheus configured successfully"
            CLUSTER_ENDPOINTS="${CLUSTER_IPS}"
        else
            echo "⚠️  WARNING: Failed to restart Prometheus"
            echo "You may need to manually restart it: sudo systemctl restart prometheus"
            CLUSTER_ENDPOINTS="${CLUSTER_IPS}"
        fi
    else
        echo "⚠️  WARNING: Failed to update Prometheus config"
        echo "You can manually add this to /etc/prometheus/prometheus.yml on the Grafana instance:"
        echo "${SCRAPE_CONFIG}"
        CLUSTER_ENDPOINTS="${ACS_CLUSTER_HOSTNAME}:${PROMETHEUS_PORT}"
    fi
else
    echo "⚠️  Skipping Prometheus configuration - no cluster IPs available"
    echo "You can manually configure it later by:"
    echo "  1. SSH to Grafana: aerolab client attach -n ${GRAFANA_NAME}"
    echo "  2. Edit: /etc/prometheus/prometheus.yml"
    echo "  3. Add targets: ${ACS_CLUSTER_HOSTNAME}:${PROMETHEUS_PORT}"
    echo "  4. Restart: sudo systemctl restart prometheus"
    CLUSTER_ENDPOINTS="${ACS_CLUSTER_HOSTNAME}:${PROMETHEUS_PORT}"
fi

echo ""

# Save Grafana configuration
GRAFANA_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
mkdir -p "$(dirname "$GRAFANA_CONFIG_FILE")"

cat > "${GRAFANA_CONFIG_FILE}" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_PRIVATE_IP="${GRAFANA_PRIVATE_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
export CLUSTER_METRICS_ENDPOINTS="${CLUSTER_ENDPOINTS}"
EOF

echo "✓ Grafana configuration saved to: ${GRAFANA_CONFIG_FILE}"
echo ""

# ============================================
# Display connection information
# ============================================

echo "============================================"
echo "✓ Grafana Setup Complete!"
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
echo "Monitoring:"
echo "  Cluster: ${ACS_CLUSTER_NAME}"
echo "  Metrics Endpoints: ${CLUSTER_ENDPOINTS}"
echo ""
echo "Note: It may take a few minutes for Grafana to fully initialize."
echo "      The dashboard will be available shortly at the URL above."
echo ""

# Open browser automatically
if command -v open &> /dev/null; then
    echo "Opening Grafana in browser..."
    open "http://${GRAFANA_IP}:3000"
fi
