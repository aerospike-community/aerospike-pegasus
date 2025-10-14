#!/bin/bash

PREFIX=$(pwd "$0")"/"$(dirname "$0")
. $PREFIX/configure.sh

# State file is now cluster-specific to allow multiple clusters
STATE_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/setup_state.sh"

# Check if switching to a different cluster
if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    CURRENT_CLUSTER_NAME_FROM_STATE="${ACS_CLUSTER_NAME:-}"
    # Reload configure.sh to get the configured cluster name
    . $PREFIX/configure.sh
    
    if [ -n "$CURRENT_CLUSTER_NAME_FROM_STATE" ] && [ "$CURRENT_CLUSTER_NAME_FROM_STATE" != "$ACS_CLUSTER_NAME" ]; then
        echo "ℹ️  Switching from cluster '${CURRENT_CLUSTER_NAME_FROM_STATE}' to '${ACS_CLUSTER_NAME}'"
        echo ""
    fi
fi

# Load state if exists for current cluster
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
    # Initialize phases if not set (backward compatibility)
    VPC_PEERING_PHASE="${VPC_PEERING_PHASE:-pending}"
    GRAFANA_SETUP_PHASE="${GRAFANA_SETUP_PHASE:-pending}"
    PROMETHEUS_CONFIG_PHASE="${PROMETHEUS_CONFIG_PHASE:-pending}"
    PERSEUS_BUILD_PHASE="${PERSEUS_BUILD_PHASE:-pending}"
    
    # Backward compatibility: convert old Grafana states to simplified model
    if [[ "$GRAFANA_SETUP_PHASE" == "creating" ]] || [[ "$GRAFANA_SETUP_PHASE" == "created" ]] || [[ "$GRAFANA_SETUP_PHASE" == "configured" ]]; then
        GRAFANA_SETUP_PHASE="complete"
    fi
else
    # Initialize state
    CLUSTER_SETUP_PHASE="pending"     # pending, provisioning, active, complete
    CLIENT_SETUP_PHASE="pending"      # pending, running, complete
    VPC_PEERING_PHASE="pending"       # pending, complete
    GRAFANA_SETUP_PHASE="pending"     # pending, complete (instance exists)
    PROMETHEUS_CONFIG_PHASE="pending" # pending, complete (configured to scrape cluster)
    PERSEUS_BUILD_PHASE="pending"     # pending, complete
fi

# ============================================
# Functions
# ============================================

save_state() {
    mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}"
    cat > "$STATE_FILE" <<EOF
export CLUSTER_SETUP_PHASE="${CLUSTER_SETUP_PHASE}"
export CLIENT_SETUP_PHASE="${CLIENT_SETUP_PHASE}"
export VPC_PEERING_PHASE="${VPC_PEERING_PHASE}"
export GRAFANA_SETUP_PHASE="${GRAFANA_SETUP_PHASE}"
export PROMETHEUS_CONFIG_PHASE="${PROMETHEUS_CONFIG_PHASE}"
export PERSEUS_BUILD_PHASE="${PERSEUS_BUILD_PHASE}"
EOF
}

validate_state() {
    echo "Validating state file against actual resources..."
    echo ""
    
    local state_changed=false
    
    # Check if cluster actually exists
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        . $PREFIX/api-scripts/common.sh
        
        echo "  Checking cluster '${ACS_CLUSTER_NAME}' (${ACS_CLUSTER_ID})..."
        
        # Try to get cluster status from API
        ACTUAL_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}" 2>/dev/null)
        
        if [ -z "$ACTUAL_STATUS" ]; then
            echo "  ⚠️  Cluster not found in API (may be deleted)"
            if [[ "$CLUSTER_SETUP_PHASE" != "pending" ]]; then
                echo "     Cluster has been deleted, resetting all dependent states..."
                CLUSTER_SETUP_PHASE="pending"
                
                # Reset all dependent phases since cluster is gone
                if [[ "$VPC_PEERING_PHASE" != "pending" ]]; then
                    echo "     Resetting VPC peering state (peering removed with cluster)"
                    VPC_PEERING_PHASE="pending"
                fi
                
                # Grafana instance stays, but Prometheus needs reconfiguration
                if [[ "$PROMETHEUS_CONFIG_PHASE" != "pending" ]]; then
                    echo "     Resetting Prometheus state (metrics endpoints changed)"
                    PROMETHEUS_CONFIG_PHASE="pending"
                                    # Grafana instance itself is still fine, only Prometheus config needs updating
                fi
                
                # Perseus build stays (JAR is generic, cluster details provided at runtime)
                # No need to rebuild Perseus
                
                # Clean up stale cluster config files
                if [ -d "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}" ]; then
                    echo "     Removing stale cluster config files..."
                    rm -rf "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
                fi
                
                state_changed=true
                rm -f "${ACS_CONFIG_DIR}/current_cluster.sh"
            fi
        else
            echo "     API Status: ${ACTUAL_STATUS}"
            
            # Update state based on actual status
            if [ "$CLUSTER_SETUP_PHASE" != "$ACTUAL_STATUS" ] && [[ "$ACTUAL_STATUS" == "active" || "$ACTUAL_STATUS" == "provisioning" ]]; then
                echo "     Updating state: ${CLUSTER_SETUP_PHASE} → ${ACTUAL_STATUS}"
                CLUSTER_SETUP_PHASE="$ACTUAL_STATUS"
                state_changed=true
            fi
            
            # Sync cluster config file with API data (use API as source of truth)
            echo "     Syncing cluster config with API data..."
            ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}" 2>/dev/null)
            ACS_CLUSTER_TLSNAME=$(acs_get_cluster_tls_name "${ACS_CLUSTER_ID}" 2>/dev/null)
            
            # Create/update cluster config file
            mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
            
            if [ "$ACTUAL_STATUS" == "active" ] && [ -n "$ACS_CLUSTER_HOSTNAME" ]; then
                # Cluster is active, get full details
                
                # Try to resolve cluster IPs if client and VPC peering exist
                CLUSTER_IPS=""
                if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ] && [[ "$VPC_PEERING_PHASE" == "complete" ]]; then
                    source "${CLIENT_CONFIG_DIR}/client_config.sh"
                    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
                    DNS_OUTPUT=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "dig +short ${ACS_CLUSTER_HOSTNAME}" 2>&1)
                    CLUSTER_IPS=$(echo "$DNS_OUTPUT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ',' | sed 's/,$//')
                fi
                
                # Write full cluster config
                cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="active"
export ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_HOSTNAME}"
export ACS_CLUSTER_TLSNAME="${ACS_CLUSTER_TLSNAME}"
export SERVICE_PORT=4000
EOF
                
                # Add cluster IPs if resolved
                if [ -n "$CLUSTER_IPS" ]; then
                    echo "export CLUSTER_IPS=\"${CLUSTER_IPS}\"" >> "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
                    echo "     ✓ Cluster config synced (IPs: ${CLUSTER_IPS})"
                else
                    echo "     ✓ Cluster config synced (IPs pending VPC peering)"
                fi
                
                state_changed=true
            elif [ "$ACTUAL_STATUS" == "provisioning" ]; then
                # Cluster is provisioning, create basic config
                cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="provisioning"
# Connection details will be added when cluster becomes active
EOF
                echo "     ✓ Cluster config updated (provisioning)"
                state_changed=true
            fi
        fi
    else
        if [[ "$CLUSTER_SETUP_PHASE" != "pending" ]]; then
            echo "  ⚠️  No cluster config found, resetting state"
            CLUSTER_SETUP_PHASE="pending"
            state_changed=true
        else
            echo "  ℹ️  No cluster provisioned yet"
        fi
    fi
    
    # Check if client actually exists in aerolab
    if [[ "$CLIENT_SETUP_PHASE" != "pending" ]]; then
        echo "  Checking client '${CLIENT_NAME}'..."
        
        # Configure aerolab backend first
        aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
        
        CLIENT_EXISTS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${CLIENT_NAME}\") | .ClientName" | head -1)
        
        if [ -z "$CLIENT_EXISTS" ]; then
            echo "     ⚠️  Client not found in aerolab (may be deleted)"
            echo "     Resetting client state to 'pending'"
            CLIENT_SETUP_PHASE="pending"
            state_changed=true
            rm -rf "${CLIENT_CONFIG_DIR}"
        else
            echo "     Found in aerolab: ${CLIENT_EXISTS}"
            
            # Check if config file exists
            if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
                if [[ "$CLIENT_SETUP_PHASE" != "complete" ]]; then
                    echo "     Updating state: ${CLIENT_SETUP_PHASE} → complete"
                    CLIENT_SETUP_PHASE="complete"
                    state_changed=true
                fi
            else
                echo "     ⚠️  Config file missing, will re-extract"
                if [[ "$CLIENT_SETUP_PHASE" == "complete" ]]; then
                    CLIENT_SETUP_PHASE="running"
                    state_changed=true
                fi
            fi
        fi
    else
        echo "  ℹ️  No client provisioned yet"
    fi
    
    # Check if VPC peering config exists
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        
        if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
            if [[ "$VPC_PEERING_PHASE" != "complete" ]]; then
                echo "  ℹ️  VPC peering config found, updating state"
                VPC_PEERING_PHASE="complete"
                state_changed=true
            else
                echo "  ✓ VPC peering configuration exists"
            fi
        else
            if [[ "$VPC_PEERING_PHASE" != "pending" ]]; then
                echo "  ⚠️  No VPC peering config found, resetting state"
                VPC_PEERING_PHASE="pending"
                state_changed=true
            else
                echo "  ℹ️  No VPC peering configured yet"
            fi
        fi
    fi
    
    # Check if Grafana instance actually exists
    # ALWAYS check - even if state is "pending" (in case state file was deleted after complete setup)
    echo "  Checking Grafana '${GRAFANA_NAME}'..."
    
    # Configure aerolab backend
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    
    GRAFANA_EXISTS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${GRAFANA_NAME}\") | .ClientName" | head -1)
    
    if [ -z "$GRAFANA_EXISTS" ]; then
        # Grafana doesn't exist
        if [[ "$GRAFANA_SETUP_PHASE" != "pending" ]]; then
            echo "     ⚠️  Grafana instance not found in aerolab (may have been deleted)"
            echo "     Resetting Grafana state to 'pending'"
            GRAFANA_SETUP_PHASE="pending"
            PROMETHEUS_CONFIG_PHASE="pending"
            state_changed=true
            rm -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
        else
            echo "     ℹ️  No Grafana instance provisioned yet"
        fi
    else
        # Grafana exists
        echo "     ✓ Grafana exists: ${GRAFANA_EXISTS}"
        
        # Check if config file exists, create if missing (regardless of state)
        if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
            echo "     ⚠️  Config file missing, extracting Grafana details..."
            
            # Extract Grafana details from aerolab
            GRAFANA_DETAILS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${GRAFANA_NAME}\")")
            
            if [ -n "$GRAFANA_DETAILS" ]; then
                GRAFANA_IP=$(echo "$GRAFANA_DETAILS" | jq -r '.PublicIp')
                GRAFANA_PRIVATE_IP=$(echo "$GRAFANA_DETAILS" | jq -r '.PrivateIp')
                GRAFANA_INSTANCE_ID=$(echo "$GRAFANA_DETAILS" | jq -r '.InstanceId')
                
                # Create the missing config file
                mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
                cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_PRIVATE_IP="${GRAFANA_PRIVATE_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
EOF
                
                echo "     ✓ Created grafana_config.sh with extracted details"
                state_changed=true
            else
                echo "     ❌ Failed to extract Grafana details from aerolab"
            fi
        fi
        
        # If state was pending, check config file to determine actual state
        if [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
            if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
                echo "     Grafana config exists, updating state: pending → complete"
                GRAFANA_SETUP_PHASE="complete"
                state_changed=true
            else
                # Config file missing, extract details from aerolab and create it
                echo "     ⚠️  Config file missing, extracting Grafana details..."
                
                # Extract Grafana details from aerolab
                GRAFANA_DETAILS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${GRAFANA_NAME}\")")
                
                if [ -n "$GRAFANA_DETAILS" ]; then
                    GRAFANA_IP=$(echo "$GRAFANA_DETAILS" | jq -r '.PublicIp')
                    GRAFANA_PRIVATE_IP=$(echo "$GRAFANA_DETAILS" | jq -r '.PrivateIp')
                    GRAFANA_INSTANCE_ID=$(echo "$GRAFANA_DETAILS" | jq -r '.InstanceId')
                    
                    # Create the missing config file
                    mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
                    cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" <<EOF
export GRAFANA_NAME="${GRAFANA_NAME}"
export GRAFANA_IP="${GRAFANA_IP}"
export GRAFANA_PRIVATE_IP="${GRAFANA_PRIVATE_IP}"
export GRAFANA_INSTANCE_ID="${GRAFANA_INSTANCE_ID}"
export GRAFANA_URL="http://${GRAFANA_IP}:3000"
EOF
                    
                    echo "     ✓ Created grafana_config.sh with extracted details"
                    echo "     Updating state: pending → complete"
                    GRAFANA_SETUP_PHASE="complete"
                else
                    echo "     ❌ Failed to extract Grafana details from aerolab"
                fi
                
                state_changed=true
            fi
        fi
    fi
    
    # Check if Prometheus is configured (if Grafana exists)
    if [[ "$GRAFANA_SETUP_PHASE" != "pending" ]] && [ -n "$GRAFANA_EXISTS" ]; then
        echo "  Checking Prometheus configuration..."
        
        # Load Grafana config to get GRAFANA_NAME
        if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
            source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
        fi
        
        # Check if Prometheus is actually configured
        PROM_CONFIGURED=$(aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "grep -q 'job_name: aerospike-cloud' /etc/prometheus/prometheus.yml && echo 'true' || echo 'false'" 2>/dev/null | tr -d '\r\n')
        
        if [ "${PROM_CONFIGURED}" == "true" ]; then
            if [[ "$PROMETHEUS_CONFIG_PHASE" != "complete" ]]; then
                echo "     ✓ Prometheus is configured (updating state)"
                PROMETHEUS_CONFIG_PHASE="complete"
                
                # Grafana phase is independent and doesn't change based on Prometheus
                
                # Update config file with the flag
                if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
                    if ! grep -q "PROMETHEUS_CONFIGURED" "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" 2>/dev/null; then
                        echo 'export PROMETHEUS_CONFIGURED="true"' >> "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
                    fi
                fi
                
                state_changed=true
            else
                echo "     ✓ Prometheus is configured"
            fi
        else
            if [[ "$PROMETHEUS_CONFIG_PHASE" == "complete" ]]; then
                echo "     ⚠️  Prometheus config missing"
                echo "     Resetting Prometheus state to 'pending'"
                PROMETHEUS_CONFIG_PHASE="pending"
                state_changed=true
            else
                echo "     ℹ️  Prometheus not configured yet"
            fi
        fi
    fi
    
    # Check if database user exists
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        
        if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh" ]; then
            echo "  Checking database user..."
            source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
            
            # Verify user still exists in API
            . $PREFIX/api-scripts/common.sh
            EXISTING_USER=$(curl -sX GET \
                "${REST_API_URI}/${ACS_CLUSTER_ID}/credentials" \
                -H "@${ACS_AUTH_HEADER}" 2>/dev/null | \
                jq -r ".credentials[] | select(.name == \"${DB_USER}\") | .id" 2>/dev/null)
            
            if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "null" ]; then
                echo "     ✓ Database user '${DB_USER}' exists (ID: ${EXISTING_USER})"
            else
                echo "     ⚠️  Database user '${DB_USER}' not found in API (may have been deleted)"
                echo "     Removing stale config file"
                rm -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
                state_changed=true
            fi
        else
            if [[ "$CLUSTER_SETUP_PHASE" == "active" ]]; then
                echo "  ℹ️  Database user not configured yet"
            fi
        fi
    fi
    
    # Check if Perseus is built
    if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        source "${CLIENT_CONFIG_DIR}/client_config.sh"
        
        echo "  Checking Perseus build status..."
        
        # Configure aerolab backend
        aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
        
        # Check if Perseus jar exists on client
        PERSEUS_JAR_EXISTS=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "test -f /root/aerospike-perseus/target/perseus-1.0-SNAPSHOT-jar-with-dependencies.jar && echo 'true' || echo 'false'" 2>/dev/null | tr -d '\r\n')
        
        if [ "${PERSEUS_JAR_EXISTS}" == "true" ]; then
            if [[ "$PERSEUS_BUILD_PHASE" != "complete" ]]; then
                echo "     ✓ Perseus is built (updating state)"
                PERSEUS_BUILD_PHASE="complete"
                state_changed=true
            else
                echo "     ✓ Perseus is built"
            fi
        else
            if [[ "$PERSEUS_BUILD_PHASE" == "complete" ]]; then
                echo "     ⚠️  Perseus build missing (client may have been recreated)"
                echo "     Resetting Perseus build state to 'pending'"
                PERSEUS_BUILD_PHASE="pending"
                state_changed=true
            else
                echo "     ℹ️  Perseus not built yet"
            fi
        fi
    fi
    
    # Save state if anything changed
    if [ "$state_changed" = true ]; then
        echo ""
        echo "  ✓ State file updated"
        save_state
    fi
    
    echo ""
}

display_current_state() {
    echo "Current State:"
    echo "  Cluster:           ${CLUSTER_SETUP_PHASE:-unknown}"
    echo "  Client:            ${CLIENT_SETUP_PHASE:-unknown}"
    echo "  VPC Peering:       ${VPC_PEERING_PHASE:-pending}"
    echo "  Grafana:           ${GRAFANA_SETUP_PHASE:-pending}"
    echo "  Prometheus Config: ${PROMETHEUS_CONFIG_PHASE:-pending}"
    echo "  Perseus Build:     ${PERSEUS_BUILD_PHASE:-pending}"
    echo ""
}

validate_and_refresh_token() {
    echo "============================================"
    echo "Validating Authentication Token"
    echo "============================================"
    echo ""
    
    # Check if credentials config file exists
    if [ ! -f "${ACS_CONFIG_DIR}/credentials.conf" ]; then
        echo "⚠️  Credentials config file not found. Looking for API key CSV file..."
        
        # Look for API key CSV file in multiple locations
        API_KEY_FILE=""
        
        if [ -d "${ACS_CONFIG_DIR}/credentials" ]; then
            API_KEY_FILE=$(find ${ACS_CONFIG_DIR}/credentials -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" 2>/dev/null | head -n 1)
        fi
        
        if [ -z "$API_KEY_FILE" ]; then
            API_KEY_FILE=$(find ${ACS_CONFIG_DIR} -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" 2>/dev/null | head -n 1)
        fi
        
        if [ -z "$API_KEY_FILE" ]; then
            API_KEY_FILE=$(find $PREFIX/.. -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" 2>/dev/null | head -n 1)
        fi
        
        if [ -n "$API_KEY_FILE" ]; then
            echo "✓ Found API key file: $API_KEY_FILE"
            
            # Extract client_id and client_secret from CSV (skip header line)
            CLIENT_ID=$(tail -n 1 "$API_KEY_FILE" | cut -d',' -f2)
            CLIENT_SECRET=$(tail -n 1 "$API_KEY_FILE" | cut -d',' -f3)
            
            # Create credentials config file
            mkdir -p "${ACS_CONFIG_DIR}"
            cat > "${ACS_CONFIG_DIR}/credentials.conf" <<EOF
# Aerospike Cloud Credentials
# Generated from API key CSV file: $(basename "$API_KEY_FILE")
ACS_CLIENT_ID="${CLIENT_ID}"
ACS_CLIENT_SECRET="${CLIENT_SECRET}"
EOF
            
            echo "✓ Credentials config file created at ${ACS_CONFIG_DIR}/credentials.conf"
            
            # Reload configure.sh to pick up the new credentials
            . $PREFIX/configure.sh
        else
            echo ""
            echo "❌ ERROR: No API key CSV file found!"
            echo "Please create ${ACS_CONFIG_DIR}/credentials.conf manually with the following content:"
            echo ""
            echo "ACS_CLIENT_ID=\"your-client-id\""
            echo "ACS_CLIENT_SECRET=\"your-client-secret\""
            echo ""
            exit 1
        fi
    fi
    
    # Verify credentials are loaded
    if [ -z "$ACS_CLIENT_ID" ] || [ -z "$ACS_CLIENT_SECRET" ]; then
        echo "❌ ERROR: Credentials not loaded properly!"
        echo "Please check ${ACS_CONFIG_DIR}/credentials.conf file."
        exit 1
    fi
    
    # Check if token exists and is valid
    TOKEN_VALID=false
    
    if [ -f "${ACS_CONFIG_DIR}/auth.header" ]; then
        echo "Checking existing token validity..."
        
        # Test token with a simple API call
        TEST_RESPONSE=$(curl -s "${REST_API_URI}?limit=1" -H "@${ACS_AUTH_HEADER}" 2>/dev/null)
        
        # Check if response contains "databases" key (valid) or error
        if echo "$TEST_RESPONSE" | jq -e '.databases' > /dev/null 2>&1; then
            TOKEN_VALID=true
            echo "✓ Existing token is valid"
        else
            echo "⚠️  Existing token is invalid or expired"
        fi
    else
        echo "ℹ️  No token found"
    fi
    
    # Generate new token if needed
    if [ "$TOKEN_VALID" = false ]; then
        echo "Generating new authentication token..."
        . $PREFIX/api-scripts/get-token.sh
        
        # Verify token was generated
        if [ ! -f "${ACS_CONFIG_DIR}/auth.header" ]; then
            echo ""
            echo "❌ ERROR: Failed to generate authentication token!"
            echo "Please check your credentials and try again."
            exit 1
        fi
        
        echo "✓ New token generated successfully"
    fi
    
    echo ""
}

run_cluster_setup() {
    echo "============================================"
    echo "Phase 1: Starting Cluster Setup"
    echo "============================================"
    echo ""
    
    # Source cluster setup but modify to not wait for provisioning
    export SKIP_PROVISION_WAIT="true"
. $PREFIX/cluster_setup.sh
    
    # Check if cluster is now provisioning or active
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        
        if [[ "$ACS_CLUSTER_STATUS" == "provisioning" ]]; then
            CLUSTER_SETUP_PHASE="provisioning"
        elif [[ "$ACS_CLUSTER_STATUS" == "active" ]]; then
            CLUSTER_SETUP_PHASE="active"
        fi
        save_state
    fi
}

run_client_setup() {
    local phase_name=$1
    
    echo ""
    echo "============================================"
    echo "Phase ${phase_name}: Client Setup"
    echo "============================================"
    echo ""
    
    if [[ "$CLIENT_SETUP_PHASE" == "running" ]]; then
        echo "Resuming interrupted client setup..."
    else
        echo "Setting up client..."
    fi
    echo ""
    
    CLIENT_SETUP_PHASE="running"
    save_state
    
    # Run client setup (use 'set +e' to prevent exit on error)
    set +e
. $PREFIX/client_setup.sh
    CLIENT_SETUP_EXIT_CODE=$?
    set -e
    
    if [ $CLIENT_SETUP_EXIT_CODE -ne 0 ]; then
        echo ""
        echo "⚠️  Client setup encountered an error (exit code: $CLIENT_SETUP_EXIT_CODE)"
        echo "State has been saved. You can re-run './setup.sh' to retry."
        exit $CLIENT_SETUP_EXIT_CODE
    fi
    
    CLIENT_SETUP_PHASE="complete"
    save_state
    
    echo ""
    echo "✓ Client setup complete!"
    echo ""
}

wait_for_cluster_active() {
    echo "============================================"
    echo "Phase 3: Waiting for Cluster to Become Active"
    echo "============================================"
    echo ""
    
    # Load cluster info
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    
    # Source common functions
    . $PREFIX/api-scripts/common.sh
    
    echo "Monitoring cluster status..."
    echo "This typically takes 10-30 minutes total."
    echo "You can safely interrupt (Ctrl+C) and re-run setup.sh to resume."
    echo ""
    
    PROVISION_START=$(date +%s)
    CHECK_COUNT=0
    
    # Spinning indicator function
    spin() {
        local pid=$1
        local delay=0.1
        local spinstr='|/-\'
        while kill -0 $pid 2>/dev/null; do
            local temp=${spinstr#?}
            printf " [%c]  " "$spinstr"
            spinstr=$temp${spinstr%"$temp"}
            sleep $delay
            printf "\b\b\b\b\b\b"
        done
        printf "    \b\b\b\b"
    }
    
    while true; do
        CURRENT_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}" 2>/dev/null)
        
        # Update status in file
        if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
            sed -i.bak "s/export ACS_CLUSTER_STATUS=\".*\"/export ACS_CLUSTER_STATUS=\"${CURRENT_STATUS}\"/" "${ACS_CONFIG_DIR}/current_cluster.sh" 2>/dev/null || \
            sed -i '' "s/export ACS_CLUSTER_STATUS=\".*\"/export ACS_CLUSTER_STATUS=\"${CURRENT_STATUS}\"/" "${ACS_CONFIG_DIR}/current_cluster.sh" 2>/dev/null
        fi
        
        if [[ "$CURRENT_STATUS" == "active" ]]; then
            echo ""
            echo ""
            echo "✓ Cluster is now ACTIVE!"
            CLUSTER_SETUP_PHASE="active"
            save_state
            
            # Get connection details from API and update cluster config file
            echo "Retrieving cluster connection details..."
            . $PREFIX/api-scripts/common.sh
            ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}" 2>/dev/null)
            ACS_CLUSTER_TLSNAME=$(acs_get_cluster_tls_name "${ACS_CLUSTER_ID}" 2>/dev/null)
            
            if [ -n "$ACS_CLUSTER_HOSTNAME" ]; then
                # Update cluster config file with connection details
                cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="active"
export ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_HOSTNAME}"
export ACS_CLUSTER_TLSNAME="${ACS_CLUSTER_TLSNAME}"
export SERVICE_PORT=4000
EOF
                echo "✓ Updated cluster config with connection details"
            else
                echo "⚠️  Could not retrieve connection details from API"
            fi
            
            break
        fi
        
        CHECK_COUNT=$((CHECK_COUNT + 1))
        ELAPSED=$(($(date +%s) - PROVISION_START))
        MINUTES=$((ELAPSED / 60))
        SECONDS=$((ELAPSED % 60))
        
        # Show progress with spinning indicator
        printf "\r⏳ Status: %s | Elapsed: %02d:%02d | Checks: %d " "${CURRENT_STATUS}" $MINUTES $SECONDS $CHECK_COUNT
        
        # Spin for 60 seconds
        sleep 60 &
        spin $!
    done
    
    echo ""
}

run_db_user_setup() {
    echo ""
    echo "============================================"
    echo "Database User Setup"
    echo "============================================"
    echo ""
    
    # Check if user already exists
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
        if [ -n "$DB_USER_ID" ]; then
            echo "✓ Database user '${DB_USER}' already configured (ID: ${DB_USER_ID})"
            echo ""
            return 0
        fi
    fi
    
    # Run database user setup
    . $PREFIX/db_user_setup.sh
    
    echo ""
}

run_vpc_peering_setup() {
    echo ""
    echo "============================================"
    echo "Phase 6: VPC Peering Setup"
    echo "============================================"
    echo ""
    
    VPC_PEERING_PHASE="configuring"
    save_state
    
    # Run VPC peering setup
    . $PREFIX/vpc_peering_setup.sh
    
    VPC_PEERING_PHASE="complete"
    save_state
    
    echo ""
    echo "✓ VPC peering setup complete (with connectivity test and IP resolution)!"
    echo ""
}

run_grafana_create_instance() {
    local phase_label="$1"
    
    echo ""
    echo "============================================"
    echo "Phase ${phase_label}: Grafana Instance Creation"
    echo "============================================"
    echo ""
    
    # Run Grafana instance creation (handles both new and existing instances)
    . $PREFIX/grafana_create_instance.sh
    
    # Once Grafana instance exists, mark as complete
    # Prometheus configuration is tracked separately
    GRAFANA_SETUP_PHASE="complete"
    save_state
    
    echo ""
}

run_prometheus_config() {
    echo ""
    echo "============================================"
    echo "Phase 7: Prometheus Configuration"
    echo "============================================"
    echo ""
    
    # Check if already configured
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
        if [ "${PROMETHEUS_CONFIGURED}" == "true" ]; then
            echo "✓ Prometheus already configured"
            if [ -n "${CLUSTER_METRICS_ENDPOINTS}" ]; then
                echo "  Metrics endpoints: ${CLUSTER_METRICS_ENDPOINTS}"
            fi
            echo ""
            return 0
        fi
    fi
    
    # Run Prometheus configuration
    . $PREFIX/prometheus_configure.sh
    
    PROMETHEUS_CONFIG_PHASE="complete"
    save_state
    
    echo ""
}

run_perseus_build() {
    echo ""
    echo "============================================"
    echo "Phase 8: Perseus Workload Build"
    echo "============================================"
    echo ""
    
    # Load client config
    if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        source "${CLIENT_CONFIG_DIR}/client_config.sh"
    fi
    
    # Check if Perseus is already built
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    PERSEUS_JAR_EXISTS=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "test -f /root/aerospike-perseus/target/perseus-1.0-SNAPSHOT-jar-with-dependencies.jar && echo 'true' || echo 'false'" 2>/dev/null | tr -d '\r\n')
    
    if [ "${PERSEUS_JAR_EXISTS}" == "true" ]; then
        echo "✓ Perseus is already built on client"
        echo ""
        PERSEUS_BUILD_PHASE="complete"
        save_state
        return 0
    fi
    
    # Run Perseus build using shared client script (same as AWS)
    echo "Building Perseus workload on client: ${CLIENT_NAME}"
    echo ""
    . $PREFIX/../client/buildPerseus.sh
    
    # Wait a bit for parallel execution to settle
    echo ""
    echo "Waiting for Perseus build to complete (this may take several minutes)..."
    sleep 10
    
    # Verify the JAR was created
    echo "Verifying Perseus build..."
    for attempt in {1..30}; do
        PERSEUS_JAR_EXISTS=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "test -f /root/aerospike-perseus/target/perseus-1.0-SNAPSHOT-jar-with-dependencies.jar && echo 'true' || echo 'false'" 2>/dev/null | tr -d '\r\n')
        
        if [ "${PERSEUS_JAR_EXISTS}" == "true" ]; then
            echo "✓ Perseus build verified successfully!"
            PERSEUS_BUILD_PHASE="complete"
            save_state
            echo ""
            return 0
        fi
        
        if [ $attempt -lt 30 ]; then
            echo "  Build still in progress... (attempt $attempt/30)"
            sleep 10
        fi
    done
    
    echo ""
    echo "⚠️  WARNING: Perseus JAR not found after waiting"
    echo "The build may still be running. Check with:"
    echo "  aerolab client attach -n ${CLIENT_NAME} -l 1 -- 'ls -l /root/aerospike-perseus/target/'"
    echo ""
    echo "If build failed, you can retry by running this script again."
    echo ""
}

finalize_setup() {
    CLUSTER_SETUP_PHASE="complete"
    save_state
    
    echo ""
    echo "╔════════════════════════════════════════════════════════════════════════════╗"
    echo "║                       ✓ SETUP COMPLETE!                                    ║"
    echo "╚════════════════════════════════════════════════════════════════════════════╝"
    echo ""
    
    # Load all configurations
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
    fi
    
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
    fi
    
    if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        source "${CLIENT_CONFIG_DIR}/client_config.sh"
    fi
    
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh"
    fi
    
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
    fi
    
    # ============================================
    # 1. AEROSPIKE CLOUD CLUSTER
    # ============================================
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📊 AEROSPIKE CLOUD CLUSTER"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  Cluster Name:     ${ACS_CLUSTER_NAME}"
    echo "  Cluster ID:       ${ACS_CLUSTER_ID}"
    echo "  Status:           ${ACS_CLUSTER_STATUS}"
    echo "  Region:           ${CLOUD_REGION}"
    echo ""
    if [ -n "${ACS_CLUSTER_HOSTNAME}" ]; then
        echo "  Connection Details:"
        echo "    Hostname:       ${ACS_CLUSTER_HOSTNAME}"
        echo "    Port:           ${SERVICE_PORT}"
        echo "    TLS Name:       ${ACS_CLUSTER_TLSNAME}"
        if [ -n "${CLUSTER_IPS}" ]; then
            echo "    Private IPs:    ${CLUSTER_IPS}"
        fi
    fi
    echo ""
    
    # ============================================
    # 2. DATABASE USER
    # ============================================
    if [ -n "${DB_USER}" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "👤 DATABASE USER"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Username:         ${DB_USER}"
        echo "  Password:         ${DB_PASSWORD}"
        echo "  Roles:            ${DB_USER_ROLES}"
        echo ""
        echo "  Connect with aql:"
        echo "    aql --tls-enable --tls-name ${ACS_CLUSTER_TLSNAME} \\"
        echo "        -h ${ACS_CLUSTER_HOSTNAME}:${SERVICE_PORT} \\"
        echo "        -U ${DB_USER} -P ${DB_PASSWORD}"
        echo ""
    fi
    
    # ============================================
    # 3. CLIENT INSTANCES
    # ============================================
    if [ -n "${CLIENT_NAME}" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "💻 CLIENT INSTANCES"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Name:             ${CLIENT_NAME}"
        echo "  Instance Type:    ${CLIENT_INSTANCE_TYPE}"
        echo "  Number of Nodes:  ${CLIENT_NUMBER_OF_NODES}"
        echo "  Public IPs:       ${CLIENT_PUBLIC_IPS}"
        echo "  Private IPs:      ${CLIENT_PRIVATE_IPS}"
        echo ""
        echo "  VPC Details:"
        echo "    VPC ID:         ${CLIENT_VPC_ID}"
        echo "    VPC CIDR:       ${CLIENT_VPC_CIDR}"
        echo "    Subnet IDs:     ${CLIENT_SUBNET_IDS}"
        echo ""
        echo "  Connect to client:"
        echo "    aerolab client attach -n ${CLIENT_NAME} -l 1"
        echo ""
    fi
    
    # ============================================
    # 4. VPC PEERING
    # ============================================
    if [[ "$VPC_PEERING_PHASE" == "complete" ]] && [ -n "${PEERING_ID}" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "🔗 VPC PEERING"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Status:           Active"
        echo "  Peering ID:       ${PEERING_ID}"
        echo ""
        echo "  Network Details:"
        echo "    Client VPC:     ${CLIENT_VPC_ID} (${CLIENT_VPC_CIDR})"
        echo "    Cluster CIDR:   ${CLUSTER_CIDR}"
        echo ""
        echo "  DNS Configuration:"
        echo "    Hosted Zone ID: ${ZONE_ID}"
        echo "    Domain:         aerospike.internal"
        echo ""
    fi
    
    # ============================================
    # 5. GRAFANA & MONITORING
    # ============================================
    if [[ "$GRAFANA_SETUP_PHASE" == "complete" ]] && [ -n "${GRAFANA_URL}" ]; then
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📈 GRAFANA & MONITORING"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "  Dashboard URL:    ${GRAFANA_URL}"
        echo "  Prometheus URL:   http://${GRAFANA_IP}:9090"
        echo ""
        echo "  Instance Details:"
        echo "    Name:           ${GRAFANA_NAME}"
        echo "    Public IP:      ${GRAFANA_IP}"
        echo "    Private IP:     ${GRAFANA_PRIVATE_IP}"
        echo ""
        echo "  Login Credentials:"
        echo "    Username:       admin"
        echo "    Password:       admin (change on first login)"
        echo ""
        if [ -n "${CLUSTER_METRICS_ENDPOINTS}" ]; then
            echo "  Metrics Endpoints:"
            echo "    ${CLUSTER_METRICS_ENDPOINTS}"
            echo ""
        fi
    fi
    
    # ============================================
    # 6. PERSEUS WORKLOAD
    # ============================================
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚡ PERSEUS WORKLOAD"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    if [[ "$PERSEUS_BUILD_PHASE" == "complete" ]]; then
        echo "  Build Status:     ✓ Built and ready"
        echo ""
        echo "  Run Perseus workload:"
        echo "    cd aeropsike-cloud"
        echo "    bash ../client/runPerseus_cloud.sh"
        echo ""
        echo "  Stop Perseus:"
        echo "    aerolab client attach -n ${CLIENT_NAME} -l all --parallel -- \"pkill -f perseus\""
    else
        echo "  Build Status:     ⚠ Not built yet"
        echo ""
        echo "  Build Perseus first:"
        echo "    cd aeropsike-cloud"
        echo "    bash ../client/buildPerseus.sh"
    fi
    echo ""
    
    # ============================================
    # 7. USEFUL COMMANDS
    # ============================================
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🔧 USEFUL COMMANDS"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    echo "  Connect to Client:"
    echo "    aerolab client attach -n ${CLIENT_NAME} -l 1"
    echo ""
    
    echo "  Verify Connectivity:"
    echo "    cd aeropsike-cloud && ./verify_connectivity.sh"
    echo ""
    
    if [[ "$PERSEUS_BUILD_PHASE" == "complete" ]]; then
        echo "  Run Perseus Workload:"
        echo "    cd aeropsike-cloud && bash ../client/runPerseus_cloud.sh"
        echo ""
        echo "  Stop Perseus:"
        echo "    aerolab client attach -n ${CLIENT_NAME} -l all --parallel -- \"pkill -f perseus\""
        echo ""
    else
        echo "  Build Perseus:"
        echo "    cd aeropsike-cloud && bash ../client/buildPerseus.sh"
        echo ""
    fi
    
    echo "  View Cluster Logs (from client):"
    echo "    aerolab client attach -n ${CLIENT_NAME} -l 1"
    echo "    # Then inside client:"
    echo "    tail -f out.log"
    echo ""
    
    echo "  Destroy Everything:"
    echo "    cd aeropsike-cloud && ./destroy.sh"
    echo ""
    
    # ============================================
    # 8. CONFIGURATION FILES
    # ============================================
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📁 CONFIGURATION FILES"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "  All configuration files are stored in:"
    echo "    ${ACS_CONFIG_DIR}/"
    echo ""
    echo "  Cluster Config:     ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
    echo "  DB User Config:     ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
    echo "  Client Config:      ${CLIENT_CONFIG_DIR}/client_config.sh"
    if [[ "$VPC_PEERING_PHASE" == "complete" ]]; then
        echo "  VPC Peering:        ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh"
    fi
    if [[ "$GRAFANA_SETUP_PHASE" == "complete" ]]; then
        echo "  Grafana Config:     ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh"
    fi
    echo ""
    
    # ============================================
    # SUMMARY & NEXT STEPS
    # ============================================
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    if [[ "$VPC_PEERING_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "complete" ]] && [[ "$PERSEUS_BUILD_PHASE" == "complete" ]]; then
        echo "✅ ALL COMPONENTS READY!"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        echo "🎉 Your Aerospike Cloud environment is fully configured!"
        echo ""
        echo "Quick Start:"
        echo "  1. Run Perseus: bash ../client/runPerseus_cloud.sh"
        echo "  2. View Metrics: open ${GRAFANA_URL}"
        echo "  3. Monitor Logs: aerolab client attach -n ${CLIENT_NAME} -l 1"
        echo ""
    else
        echo "📋 REMAINING STEPS"
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo ""
        
        if [[ "$VPC_PEERING_PHASE" != "complete" ]]; then
            echo "  [ ] Set up VPC peering: ./vpc_peering_setup.sh"
            echo "  [ ] Verify connectivity: ./verify_connectivity.sh"
        fi
        
        if [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
            echo "  [ ] Create Grafana: ./grafana_create_instance.sh"
        fi
        
        if [[ "$PROMETHEUS_CONFIG_PHASE" != "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" != "pending" ]]; then
            echo "  [ ] Configure Prometheus: ./prometheus_configure.sh"
        fi
        
        if [[ "$PERSEUS_BUILD_PHASE" != "complete" ]]; then
            echo "  [ ] Build Perseus: bash ../client/buildPerseus.sh"
        fi
        
        echo ""
        echo "Run './setup.sh' again to continue setup."
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    # Clean up state file as setup is complete
    rm -f "$STATE_FILE"
}

# ============================================
# Main Execution Flow
# ============================================

echo "============================================"
echo "Aerospike Cloud - Complete Setup"
echo "============================================"
echo ""

# Validate and refresh authentication token first
validate_and_refresh_token

# Validate state against actual resources
validate_state
display_current_state

# Phase 1: Start cluster setup (if not already done)
if [[ "$CLUSTER_SETUP_PHASE" == "pending" ]]; then
    run_cluster_setup
fi

# Phase 2: Start client setup in parallel (if cluster is provisioning and client not done)
if [[ "$CLUSTER_SETUP_PHASE" == "provisioning" ]] && [[ "$CLIENT_SETUP_PHASE" != "complete" ]]; then
    run_client_setup "2 (Parallel)"
fi

# Phase 2.5: Start Grafana instance creation in parallel (if cluster is provisioning and Grafana not done)
if [[ "$CLUSTER_SETUP_PHASE" == "provisioning" ]] && [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
    # Only create Grafana if client setup has started or completed (need client VPC)
    if [[ "$CLIENT_SETUP_PHASE" != "pending" ]]; then
        run_grafana_create_instance "2.5 (Parallel)"
    fi
fi

# Phase 3: Wait for cluster to become active (if still provisioning)
if [[ "$CLUSTER_SETUP_PHASE" == "provisioning" ]]; then
    wait_for_cluster_active
fi

# Phase 3.5: Setup database user (if cluster is active)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]]; then
    run_db_user_setup
fi

# Phase 4: Resume or start client setup if not complete (cluster is now active)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" != "complete" ]]; then
    if [[ "$CLIENT_SETUP_PHASE" == "running" ]]; then
        run_client_setup "4 (Resuming)"
    else
        run_client_setup "4"
    fi
fi

# Phase 5: Setup/validate VPC peering (if cluster and client are ready)
# Run even if complete to validate routes and ensure IPs are saved
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]]; then
    if [[ "$VPC_PEERING_PHASE" == "pending" ]]; then
        run_vpc_peering_setup
    elif [[ "$VPC_PEERING_PHASE" == "complete" ]]; then
        # VPC peering already complete, but run validation to ensure routes and IPs are current
        echo ""
        echo "============================================"
        echo "Phase 6: VPC Peering Validation"
        echo "============================================"
        echo ""
        echo "VPC peering already complete, validating configuration..."
        echo ""
        
        # Run vpc_peering_setup.sh which is now idempotent
        # It will validate routes, fix stale entries, and ensure IPs are saved
        . $PREFIX/vpc_peering_setup.sh
        
        echo ""
        echo "✓ VPC peering validation complete!"
        echo ""
    fi
fi

# Phase 6: Create Grafana instance if not done yet (after client is complete)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
    run_grafana_create_instance "6"
fi

# Phase 7: Configure Prometheus (after VPC peering and Grafana are ready)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$VPC_PEERING_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "complete" ]] && [[ "$PROMETHEUS_CONFIG_PHASE" == "pending" ]]; then
    run_prometheus_config
fi

# Phase 8: Build Perseus workload (after everything else is ready)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$VPC_PEERING_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "complete" ]] && [[ "$PERSEUS_BUILD_PHASE" == "pending" ]]; then
    run_perseus_build
fi

# Phase 9: Final setup complete
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]]; then
    finalize_setup
fi

