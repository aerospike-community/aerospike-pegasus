#!/bin/bash

PREFIX=$(pwd "$0")"/"$(dirname "$0")
. $PREFIX/configure.sh

# Load state if exists
STATE_FILE="${ACS_CONFIG_DIR}/setup_state.sh"
if [ -f "$STATE_FILE" ]; then
    source "$STATE_FILE"
    # Initialize phases if not set (backward compatibility)
    VPC_PEERING_PHASE="${VPC_PEERING_PHASE:-pending}"
    GRAFANA_SETUP_PHASE="${GRAFANA_SETUP_PHASE:-pending}"
    PROMETHEUS_CONFIG_PHASE="${PROMETHEUS_CONFIG_PHASE:-pending}"
else
    # Initialize state
    CLUSTER_SETUP_PHASE="pending"     # pending, provisioning, active, complete
    CLIENT_SETUP_PHASE="pending"      # pending, running, complete
    VPC_PEERING_PHASE="pending"       # pending, configured, complete
    GRAFANA_SETUP_PHASE="pending"     # pending, creating, created, configured, complete
    PROMETHEUS_CONFIG_PHASE="pending" # pending, complete
fi

# ============================================
# Functions
# ============================================

save_state() {
    mkdir -p "${ACS_CONFIG_DIR}"
    cat > "$STATE_FILE" <<EOF
export CLUSTER_SETUP_PHASE="${CLUSTER_SETUP_PHASE}"
export CLIENT_SETUP_PHASE="${CLIENT_SETUP_PHASE}"
export VPC_PEERING_PHASE="${VPC_PEERING_PHASE}"
export GRAFANA_SETUP_PHASE="${GRAFANA_SETUP_PHASE}"
export PROMETHEUS_CONFIG_PHASE="${PROMETHEUS_CONFIG_PHASE}"
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
                echo "     Resetting cluster state to 'pending'"
                CLUSTER_SETUP_PHASE="pending"
                state_changed=true
                rm -f "${ACS_CONFIG_DIR}/current_cluster.sh"
            fi
        else
            echo "     API Status: ${ACTUAL_STATUS}"
            
            # Update state based on actual status
            if [ "$ACTUAL_STATUS" == "active" ]; then
                if [ "$CLUSTER_SETUP_PHASE" != "active" ]; then
                    echo "     Updating state: ${CLUSTER_SETUP_PHASE} → active"
                    CLUSTER_SETUP_PHASE="active"
                    state_changed=true
                fi
            elif [ "$ACTUAL_STATUS" == "provisioning" ]; then
                if [ "$CLUSTER_SETUP_PHASE" != "provisioning" ]; then
                    echo "     Updating state: ${CLUSTER_SETUP_PHASE} → provisioning"
                    CLUSTER_SETUP_PHASE="provisioning"
                    state_changed=true
                fi
            else
                echo "     Current state: ${CLUSTER_SETUP_PHASE}"
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
        
        if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
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
            rm -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
        else
            echo "     ℹ️  No Grafana instance provisioned yet"
        fi
    else
        # Grafana exists
        echo "     ✓ Grafana exists: ${GRAFANA_EXISTS}"
        
        # If state was pending, check config file to determine actual state
        if [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
            if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
                source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
                
                # Check if Prometheus is actually configured (not just the flag)
                echo "     Checking Prometheus configuration..."
                PROM_CONFIGURED=$(aerolab client attach -n "${GRAFANA_NAME}" -l 1 -- "grep -q 'job_name: aerospike-cloud' /etc/prometheus/prometheus.yml && echo 'true' || echo 'false'" 2>/dev/null | tr -d '\r\n')
                
                if [ "${PROM_CONFIGURED}" == "true" ]; then
                    echo "     Updating state: pending → complete (found existing setup with Prometheus)"
                    GRAFANA_SETUP_PHASE="complete"
                    PROMETHEUS_CONFIG_PHASE="complete"
                    
                    # Update config file with the flag
                    if ! grep -q "PROMETHEUS_CONFIGURED" "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" 2>/dev/null; then
                        echo 'export PROMETHEUS_CONFIGURED="true"' >> "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
                    fi
                else
                    echo "     Updating state: pending → created (Prometheus not configured)"
                    GRAFANA_SETUP_PHASE="created"
                    PROMETHEUS_CONFIG_PHASE="pending"
                fi
                state_changed=true
            else
                echo "     Updating state: pending → created"
                GRAFANA_SETUP_PHASE="created"
                state_changed=true
            fi
        fi
        
        # Update state based on current phase
        if [[ "$GRAFANA_SETUP_PHASE" == "creating" ]]; then
            echo "     Updating state: creating → created"
            GRAFANA_SETUP_PHASE="created"
            state_changed=true
        fi
        
        # Check if Prometheus is configured
        if [[ "$PROMETHEUS_CONFIG_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" != "complete" ]]; then
            echo "     Updating state: ${GRAFANA_SETUP_PHASE} → complete"
            GRAFANA_SETUP_PHASE="complete"
            state_changed=true
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
    echo "This typically takes 10-20 minutes total."
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
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh"
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
    echo "✓ VPC peering setup complete!"
    echo ""
}

run_grafana_create_instance() {
    local phase_label="$1"
    
    echo ""
    echo "============================================"
    echo "Phase ${phase_label}: Grafana Instance Creation"
    echo "============================================"
    echo ""
    
    # Check if Grafana instance already exists
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    GRAFANA_EXISTS=$(aerolab client list -j 2>/dev/null | jq -r ".[] | select(.ClientName == \"${GRAFANA_NAME}\") | .ClientName" | head -1)
    
    if [ -n "$GRAFANA_EXISTS" ]; then
        echo "✓ Grafana instance already exists"
        GRAFANA_SETUP_PHASE="created"
        save_state
        echo ""
        return 0
    fi
    
    # Run Grafana instance creation
    . $PREFIX/grafana_create_instance.sh
    
    GRAFANA_SETUP_PHASE="created"
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
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
        if [ "${PROMETHEUS_CONFIGURED}" == "true" ]; then
            echo "✓ Prometheus already configured"
            echo "  Metrics endpoints: ${CLUSTER_METRICS_ENDPOINTS}"
            echo ""
            return 0
        fi
    fi
    
    # Run Prometheus configuration
    . $PREFIX/prometheus_configure.sh
    
    PROMETHEUS_CONFIG_PHASE="complete"
    GRAFANA_SETUP_PHASE="complete"
    save_state
    
    echo ""
}

finalize_setup() {
    CLUSTER_SETUP_PHASE="complete"
    save_state
    
    echo ""
    echo "============================================"
    echo "✓ SETUP COMPLETE!"
    echo "============================================"
    echo ""
    
    # Load cluster info
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    
    # Load cluster connection details if available
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh"
    fi
    
    echo "Cluster Details:"
    echo "  Name: ${ACS_CLUSTER_NAME}"
    echo "  ID: ${ACS_CLUSTER_ID}"
    echo "  Status: ${ACS_CLUSTER_STATUS}"
    if [ -n "${ACS_CLUSTER_HOSTNAME}" ]; then
        echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
        echo "  TLS Name: ${ACS_CLUSTER_TLSNAME}"
        echo "  Port: ${SERVICE_PORT}"
    fi
    
    # Load and display database user info if exists
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh" ]; then
        source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh"
        echo ""
        echo "Database User:"
        echo "  Username: ${DB_USER}"
        echo "  Password: ${DB_PASSWORD}"
        echo "  Roles: ${DB_USER_ROLES}"
    fi
    echo ""
    
    # Load client info if exists
    if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        source "${CLIENT_CONFIG_DIR}/client_config.sh"
        
        echo "Client Details:"
        echo "  Name: ${CLIENT_NAME}"
        echo "  Instance Type: ${CLIENT_INSTANCE_TYPE}"
        echo "  VPC ID: ${CLIENT_VPC_ID}"
        echo "  VPC CIDR: ${CLIENT_VPC_CIDR}"
        echo "  Private IPs: ${CLIENT_PRIVATE_IPS}"
        echo "  Public IPs: ${CLIENT_PUBLIC_IPS}"
        echo ""
        
        # Check VPC peering status
        if [[ "$VPC_PEERING_PHASE" == "complete" ]]; then
            echo "VPC Peering:"
            if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
                source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh"
                echo "  Status: Active"
                echo "  Peering ID: ${PEERING_ID}"
                echo "  Client VPC: ${CLIENT_VPC_ID} (${CLIENT_VPC_CIDR})"
                echo "  Cluster CIDR: ${CLUSTER_CIDR}"
                echo "  Hosted Zone ID: ${ZONE_ID}"
            fi
            echo ""
        fi
        
        # Check Grafana status
        if [[ "$GRAFANA_SETUP_PHASE" == "complete" ]]; then
            echo "Grafana/Monitoring:"
            if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
                source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
                echo "  Dashboard: ${GRAFANA_URL}"
                echo "  Instance: ${GRAFANA_NAME}"
                echo "  IP: ${GRAFANA_IP}"
                echo "  Credentials: admin/admin"
            fi
        fi
    fi
    
    echo ""
    
    # Determine next steps based on what's completed
    if [[ "$VPC_PEERING_PHASE" != "complete" ]]; then
        echo "Next Steps:"
        echo "  1. Set up VPC peering: ./vpc_peering_setup.sh"
        echo "  2. Verify connectivity: ./verify_connectivity.sh"
        if [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
            echo "  3. Create Grafana: ./grafana_create_instance.sh"
        fi
        if [[ "$GRAFANA_SETUP_PHASE" == "created" ]] || [[ "$GRAFANA_SETUP_PHASE" == "creating" ]]; then
            echo "  3. Configure Prometheus: ./prometheus_configure.sh"
        fi
        echo "  4. Build Perseus workload: ./client/buildPerseus.sh"
        echo "  5. Run workload: ./client/runPerseus.sh"
    elif [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
        echo "Next Steps:"
        echo "  1. Create Grafana: ./grafana_create_instance.sh"
        echo "  2. Configure Prometheus: ./prometheus_configure.sh"
        echo "  3. Build Perseus workload: ./client/buildPerseus.sh"
        echo "  4. Run workload: ./client/runPerseus.sh"
    elif [[ "$GRAFANA_SETUP_PHASE" == "created" ]] || [[ "$PROMETHEUS_CONFIG_PHASE" != "complete" ]]; then
        echo "Next Steps:"
        echo "  1. Configure Prometheus: ./prometheus_configure.sh"
        echo "  2. Build Perseus workload: ./client/buildPerseus.sh"
        echo "  3. Run workload: ./client/runPerseus.sh"
    else
        echo "Next Steps:"
        echo "  1. Build Perseus workload: ./client/buildPerseus.sh"
        echo "  2. Run workload: ./client/runPerseus.sh"
        if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" ]; then
            source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
            echo "  3. View metrics: ${GRAFANA_URL}"
        fi
        
        # Offer to run connectivity verification if not done
        if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh" ] || ! grep -q "CLUSTER_IPS" "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh" 2>/dev/null; then
            echo ""
            read -p "Would you like to verify connectivity now? [Y/n]: " -n 1 -r
            echo ""
            
            if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                echo ""
                . $PREFIX/verify_connectivity.sh
            fi
        fi
    fi
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

# Phase 2.5: Start Grafana instance creation in parallel (if cluster is provisioning and Grafana not created)
if [[ "$CLUSTER_SETUP_PHASE" == "provisioning" ]] && [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
    # Only create Grafana if client setup has started or completed (need client VPC)
    if [[ "$CLIENT_SETUP_PHASE" != "pending" ]]; then
        run_grafana_create_instance "2.5 (Parallel)"
        GRAFANA_SETUP_PHASE="creating"
        save_state
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

# Phase 5: Setup VPC peering (if cluster and client are ready, and VPC peering not done)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$VPC_PEERING_PHASE" == "pending" ]]; then
    # Ask if user wants to set up VPC peering
    echo ""
    read -p "Would you like to set up VPC peering now? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        run_vpc_peering_setup
    else
        echo "Skipping VPC peering setup. You can run it later with:"
        echo "  ./vpc_peering_setup.sh"
        echo ""
    fi
fi

# Phase 6: Create Grafana instance if not done yet (after client is complete)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "pending" ]]; then
    # Ask if user wants to set up Grafana
    echo ""
    read -p "Would you like to create Grafana instance now? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        run_grafana_create_instance "6"
    else
        echo "Skipping Grafana creation. You can run it later with:"
        echo "  ./grafana_create_instance.sh"
        echo ""
    fi
fi

# Phase 7: Configure Prometheus (after VPC peering and Grafana are ready)
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]] && [[ "$VPC_PEERING_PHASE" == "complete" ]] && [[ "$GRAFANA_SETUP_PHASE" == "created" ]] && [[ "$PROMETHEUS_CONFIG_PHASE" == "pending" ]]; then
    # Ask if user wants to configure Prometheus
    echo ""
    read -p "Would you like to configure Prometheus for cluster monitoring now? [Y/n]: " -n 1 -r
    echo ""
    
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        run_prometheus_config
    else
        echo "Skipping Prometheus configuration. You can run it later with:"
        echo "  ./prometheus_configure.sh"
        echo ""
    fi
fi

# Phase 8: Final setup complete
if [[ "$CLUSTER_SETUP_PHASE" == "active" ]] && [[ "$CLIENT_SETUP_PHASE" == "complete" ]]; then
    finalize_setup
fi
