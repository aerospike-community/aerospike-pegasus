#!/bin/bash

# Load common configurations
PREFIX=$(pwd "$0")"/"$(dirname "$0")
. $PREFIX/configure.sh

# Ensure cluster ID is available
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "❌ ERROR: Cluster configuration not found!"
    echo "Please run './setup.sh' to complete cluster setup."
    exit 1
fi
source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Ensure Grafana exists
if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
    echo "❌ ERROR: Grafana configuration not found!"
    echo "Please run Grafana setup first."
    exit 1
fi
source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"

# Load cluster connection details
if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
    echo "❌ ERROR: Cluster connection details not found!"
    echo "Please run './setup.sh' to complete cluster setup."
    exit 1
fi
source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"

# Load client config
if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
    echo "❌ ERROR: Client configuration not found!"
    echo "Please run './setup.sh' to create client first."
    exit 1
fi
source "${CLIENT_CONFIG_DIR}/client_config.sh"

echo "============================================"
echo "Aerospike Cloud - Prometheus Configuration"
echo "============================================"
echo ""

echo "Configuring Prometheus on Grafana to scrape Aerospike cluster..."
echo "  Cluster: ${ACS_CLUSTER_NAME}"
echo "  Grafana: ${GRAFANA_NAME} (${GRAFANA_IP})"
echo ""

# ============================================
# Get cluster IPs from config
# ============================================

echo "Loading cluster IPs from configuration..."
echo ""

# Cluster IPs should already be in config (saved during VPC peering setup)
if [ -z "${CLUSTER_IPS}" ] || [ "${CLUSTER_IPS}" == "null" ]; then
    echo "❌ ERROR: Cluster IPs not found in configuration!"
    echo ""
    echo "This usually means VPC peering hasn't completed successfully."
    echo ""
    echo "Please run VPC peering setup again:"
    echo "  cd aeropsike-cloud && ./vpc_peering_setup.sh"
    echo ""
    echo "The VPC peering setup will test connectivity and save cluster IPs."
    exit 1
fi

echo "✓ Using cluster IPs: ${CLUSTER_IPS}"
echo ""

# ============================================
# Configure Prometheus
# ============================================

echo "Configuring Prometheus to scrape cluster..."
echo ""

# Build scrape targets as a YAML array (no quotes, no spaces after commas)
SCRAPE_TARGETS=""
# Strip any carriage returns and whitespace from CLUSTER_IPS
CLUSTER_IPS=$(echo "$CLUSTER_IPS" | tr -d '\r' | tr -d ' ')
IFS=',' read -ra IPS <<< "$CLUSTER_IPS"
for ip in "${IPS[@]}"; do
    # Trim any remaining whitespace from IP
    ip=$(echo "$ip" | xargs)
    if [ -z "$SCRAPE_TARGETS" ]; then
        SCRAPE_TARGETS="${ip}:${PROMETHEUS_PORT}"
    else
        SCRAPE_TARGETS="${SCRAPE_TARGETS},${ip}:${PROMETHEUS_PORT}"
    fi
done

# Create the scrape config with proper YAML array formatting
SCRAPE_CONFIG="  - job_name: aerospike-cloud
    static_configs:
      - targets: [${SCRAPE_TARGETS}]"

# Check if config already exists
echo "Checking existing Prometheus configuration..."
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" &>/dev/null
EXISTING_JOB=$(aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "grep -A 2 'job_name: aerospike-cloud' /etc/prometheus/prometheus.yml" 2>/dev/null)

if [ -n "$EXISTING_JOB" ]; then
    echo "⚠️  Aerospike job already exists in Prometheus config, removing old config..."
    aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "sudo sed -i '/job_name: aerospike-cloud/,+4d' /etc/prometheus/prometheus.yml" 2>/dev/null
fi

# Add to Prometheus config via SSH
echo "Adding Aerospike cluster to Prometheus scrape config..."
aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "echo '${SCRAPE_CONFIG}' | sudo tee -a /etc/prometheus/prometheus.yml > /dev/null" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to update Prometheus config"
    echo ""
    echo "You can manually add this to /etc/prometheus/prometheus.yml on the Grafana instance:"
    echo "${SCRAPE_CONFIG}"
    echo ""
    echo "Continuing anyway..."
    return 1 2>/dev/null || exit 1
fi

# Restart Prometheus to apply changes
echo "Restarting Prometheus..."
aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "sudo systemctl restart prometheus" 2>/dev/null

if [ $? -ne 0 ]; then
    echo "⚠️  WARNING: Failed to restart Prometheus"
    echo "You may need to manually restart it: sudo systemctl restart prometheus"
    return 1 2>/dev/null || exit 1
fi

echo "✓ Prometheus configured successfully"
echo ""

# Wait for Prometheus to start scraping
echo "Waiting for Prometheus to start scraping (10 seconds)..."
sleep 10

# Verify targets are up
echo ""
echo "Verifying Prometheus targets..."
TARGET_HEALTH=$(aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "curl -s http://localhost:9090/api/v1/targets | jq -r '.data.activeTargets[] | select(.labels.job == \"aerospike-cloud\") | .health'" 2>/dev/null)

if echo "$TARGET_HEALTH" | grep -q "up"; then
    echo "✓ All targets are healthy!"
else
    echo "⚠️  Some targets may not be healthy yet. Check Prometheus: http://${GRAFANA_IP}:9090/targets"
fi

# Update Grafana config file with cluster endpoints
CLUSTER_ENDPOINTS=$(echo "$CLUSTER_IPS" | sed "s/,/:${PROMETHEUS_PORT},/g" | sed "s/$/:${PROMETHEUS_PORT}/")

cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_PRIVATE_IP="${GRAFANA_PRIVATE_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
export CLUSTER_METRICS_ENDPOINTS="${CLUSTER_ENDPOINTS}"
export PROMETHEUS_CONFIGURED="true"
EOF

echo ""

# ============================================
# Display connection information
# ============================================

echo "============================================"
echo "✓ Prometheus Configuration Complete!"
echo "============================================"
echo ""
echo "Grafana Dashboard: ${GRAFANA_URL}"
echo "Prometheus: http://${GRAFANA_IP}:9090"
echo ""
echo "Monitoring:"
echo "  Cluster: ${ACS_CLUSTER_NAME}"
echo "  Metrics Endpoints: ${CLUSTER_ENDPOINTS}"
echo ""
echo "You can now view Aerospike metrics in Grafana!"
echo ""

