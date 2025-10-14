#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

set -e

# Source common functions
. $PREFIX/api-scripts/common.sh

# ============================================
# Global Variables
# ============================================

PEERING_STATE_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/vpc_peering_state.sh"

# ============================================
# Helper Functions
# ============================================

log_info() {
    echo "ℹ️  $1"
}

log_success() {
    echo "✓ $1"
}

log_error() {
    echo "❌ ERROR: $1"
}

log_warning() {
    echo "⚠️  WARNING: $1"
}

save_peering_state() {
    cat > "$PEERING_STATE_FILE" <<EOF
# VPC Peering State
export VPC_PEERING_INITIATED="$VPC_PEERING_INITIATED"
export VPC_PEERING_ACCEPTED="$VPC_PEERING_ACCEPTED"
export ROUTES_CONFIGURED="$ROUTES_CONFIGURED"
export DNS_CONFIGURED="$DNS_CONFIGURED"
export PEERING_ID="$PEERING_ID"
export ZONE_ID="$ZONE_ID"
EOF
}

# ============================================
# Validation Functions
# ============================================

validate_prerequisites() {
    log_info "Validating prerequisites..."
    
    # Check if cluster exists and is active
    if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        log_error "No cluster found. Please run './setup.sh' first."
        exit 1
    fi
    
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    
    if [ -z "$ACS_CLUSTER_ID" ]; then
        log_error "Cluster ID not found in state file"
        exit 1
    fi
    
    # Verify cluster is active
    CLUSTER_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}" 2>/dev/null)
    if [ "$CLUSTER_STATUS" != "active" ]; then
        log_error "Cluster is not active (status: ${CLUSTER_STATUS}). Wait for cluster to become active."
        exit 1
    fi
    
    log_success "Cluster is active: ${ACS_CLUSTER_NAME} (${ACS_CLUSTER_ID})"
    
    # Check if client exists
    if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        log_error "No client found. Please run './setup.sh' to provision client first."
        exit 1
    fi
    
    source "${CLIENT_CONFIG_DIR}/client_config.sh"
    
    if [ -z "$CLIENT_VPC_ID" ]; then
        log_error "Client VPC ID not found in state file"
        exit 1
    fi
    
    log_success "Client VPC found: ${CLIENT_VPC_ID} (${CLIENT_VPC_CIDR})"
    
    # Check AWS CLI is available
    if ! command -v aws &> /dev/null; then
        log_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
    
    log_success "AWS CLI is available"
    
    # Check jq is available
    if ! command -v jq &> /dev/null; then
        log_error "jq is not installed. Please install it first."
        exit 1
    fi
    
    log_success "jq is available"
}

get_aws_account_id() {
    log_info "Getting AWS Account ID..."
    
    AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
    
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        log_error "Failed to get AWS Account ID. Check AWS credentials."
        exit 1
    fi
    
    log_success "AWS Account ID: ${AWS_ACCOUNT_ID}"
}

get_route_table_ids() {
    log_info "Getting route table IDs for client VPC..."
    
    # Get all route tables for the VPC
    ROUTE_TABLE_IDS=$(aws ec2 describe-route-tables \
        --region "${CLIENT_AWS_REGION}" \
        --filters "Name=vpc-id,Values=${CLIENT_VPC_ID}" \
        --query 'RouteTables[].RouteTableId' \
        --output text 2>/dev/null)
    
    if [ -z "$ROUTE_TABLE_IDS" ]; then
        log_error "Failed to get route table IDs for VPC ${CLIENT_VPC_ID}"
        exit 1
    fi
    
    log_success "Found route tables: ${ROUTE_TABLE_IDS}"
}

check_cidr_overlap() {
    log_info "Checking for CIDR block overlaps..."
    
    # Check if client VPC CIDR overlaps with Aerospike Cloud CIDR
    if [[ "$CLIENT_VPC_CIDR" == "10.129.0.0/24" ]] || [[ "$DEST_CIDR" == *"10.129.0.0/24"* ]]; then
        log_error "CIDR block 10.129.0.0/24 is reserved for Aerospike Cloud internal services"
        exit 1
    fi
    
    log_success "No CIDR block overlaps detected"
}

# ============================================
# VPC Peering Functions
# ============================================

validate_existing_peering() {
    log_info "Checking for existing VPC peering..."
    
    # Get existing peering from Aerospike Cloud API
    PEERING_JSON=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}")
    EXISTING_PEERING_COUNT=$(echo "$PEERING_JSON" | jq -r '.count // 0')
    
    if [[ "$EXISTING_PEERING_COUNT" -gt 0 ]]; then
        # Peering exists, get details
        EXISTING_STATUS=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].status // ""')
        EXISTING_PEERING_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].peeringId // ""')
        EXISTING_VPC_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].vpcId // ""')
        
        log_success "Found existing VPC peering:"
        echo "  Status: ${EXISTING_STATUS}"
        echo "  Peering ID: ${EXISTING_PEERING_ID}"
        echo "  VPC ID: ${EXISTING_VPC_ID}"
        
        # Check if it's for the same VPC
        if [ "$EXISTING_VPC_ID" != "$CLIENT_VPC_ID" ]; then
            log_error "Existing peering is for different VPC (${EXISTING_VPC_ID})"
            log_error "Expected: ${CLIENT_VPC_ID}"
            log_error "Please delete the existing peering and try again"
            exit 1
        fi
        
        # Check status and return appropriate state
        if [ "$EXISTING_STATUS" == "active" ]; then
            log_success "VPC peering is already active"
            return 0  # Fully configured
        elif [ "$EXISTING_STATUS" == "pending-acceptance" ]; then
            log_info "VPC peering is pending acceptance"
            return 1  # Need to accept
        elif [ "$EXISTING_STATUS" == "provisioning" ] || [ "$EXISTING_STATUS" == "initiating-request" ]; then
            log_info "VPC peering is being provisioned"
            return 2  # Wait for it
        else
            log_warning "VPC peering status: ${EXISTING_STATUS}"
            return 3  # Unknown state
        fi
    else
        log_info "No existing VPC peering found"
        return 4  # Need to create
    fi
}

initiate_vpc_peering() {
    log_info "Initiating VPC peering request..."
    
    # Check if peering already exists (shouldn't get here if validate caught it, but safety check)
    EXISTING_PEERING=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r '.count // 0')
    
    if [[ "$EXISTING_PEERING" -gt 0 ]]; then
        log_warning "VPC peering already exists, skipping initiation"
        VPC_PEERING_INITIATED="true"
        return 0
    fi
    
    # Build VPC details JSON
    VPC_DETAILS=$(cat <<EOJSON
{
  "vpcId": "${CLIENT_VPC_ID}",
  "cidrBlock": "${CLIENT_VPC_CIDR}",
  "accountId": "${AWS_ACCOUNT_ID}",
  "region": "${CLIENT_AWS_REGION}",
  "secureConnection": true
}
EOJSON
)
    
    log_info "VPC Details:"
    echo "$VPC_DETAILS" | jq '.'
    
    # Make API request
    API_RESPONSE=$(mktemp)
    HTTP_CODE=$(curl -sX POST "$REST_API_URI/${ACS_CLUSTER_ID}/vpc-peerings" \
        -H "@${ACS_AUTH_HEADER}" \
        -H "Content-Type: application/json" \
        -d "${VPC_DETAILS}" \
        -o "$API_RESPONSE" \
        -w '%{http_code}')
    
    if [[ ${HTTP_CODE} != "201" ]]; then
        log_error "Failed to initiate VPC peering (HTTP ${HTTP_CODE})"
        echo "API Response:"
        cat "$API_RESPONSE" | jq '.' 2>/dev/null || cat "$API_RESPONSE"
        rm -f "$API_RESPONSE"
        exit 1
    fi
    
    rm -f "$API_RESPONSE"
    log_success "VPC peering request initiated successfully"
    
    VPC_PEERING_INITIATED="true"
    save_peering_state
}

wait_for_peering_status() {
    local target_status=$1
    local current_status=""
    local max_wait=300  # 5 minutes (reduced from 10)
    local elapsed=0
    local check_interval=5  # Check every 5 seconds (reduced from 10)
    
    log_info "Waiting for peering status to become '${target_status}'..."
    echo "  (Checking every ${check_interval} seconds, max wait: ${max_wait} seconds)"
    
    while [[ "$current_status" != "$target_status" ]] && [[ $elapsed -lt $max_wait ]]; do
        current_status=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" 2>/dev/null | jq -r '.vpcPeerings[0].status // "unknown"')
        
        # Check for failure states
        if [[ "$current_status" == "failed" ]]; then
            echo ""
            log_error "VPC peering failed"
            echo ""
            echo "Peering details:"
            acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq '.'
            exit 1
        fi
        
        # If status is the target, break immediately
        if [[ "$current_status" == "$target_status" ]]; then
            break
        fi
        
        # Show progress
        printf "\r  Status: %-25s | Elapsed: %3ds / %ds " "$current_status" $elapsed $max_wait
        
        sleep $check_interval
        elapsed=$((elapsed + check_interval))
    done
    
    echo ""
    echo ""
    
    # Final check
    if [[ "$current_status" != "$target_status" ]]; then
        log_warning "Timeout waiting for status '${target_status}' after ${max_wait}s (current: ${current_status})"
        echo ""
        echo "Current peering details:"
        acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq '.'
        echo ""
        
        # If we're close to the target status, continue anyway
        if [[ "$target_status" == "pending-acceptance" ]] && [[ "$current_status" == "initiating-request" ]]; then
            log_warning "Still in 'initiating-request', will attempt to continue..."
            return 0
        fi
        
        read -p "Continue anyway? [y/N]: " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
        return 0
    fi
    
    log_success "Peering status is now: ${target_status}"
}

get_peering_details() {
    log_info "Retrieving peering connection details..."
    
    PEERING_JSON=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}")
    
    PEERING_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].peeringId // ""')
    ZONE_ID=$(echo "$PEERING_JSON" | jq -r '.vpcPeerings[0].privateHostedZoneId // ""')
    
    if [ -z "$PEERING_ID" ] || [ -z "$ZONE_ID" ]; then
        log_error "Failed to get peering details"
        echo "$PEERING_JSON" | jq '.'
        exit 1
    fi
    
    log_success "Peering ID: ${PEERING_ID}"
    log_success "Hosted Zone ID: ${ZONE_ID}"
    
    # Save to cluster config directory
    mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
    cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh" <<EOF
export PEERING_ID="${PEERING_ID}"
export ZONE_ID="${ZONE_ID}"
export CLIENT_VPC_ID="${CLIENT_VPC_ID}"
export CLIENT_VPC_CIDR="${CLIENT_VPC_CIDR}"
export CLUSTER_CIDR="${DEST_CIDR}"
EOF
    
    save_peering_state
}

accept_peering_connection() {
    log_info "Accepting VPC peering connection..."
    
    # Check current status
    CURRENT_STATUS=$(acs_get_vpc_peering_json "${ACS_CLUSTER_ID}" | jq -r '.vpcPeerings[0].status')
    
    if [[ "$CURRENT_STATUS" == "active" ]]; then
        log_warning "Peering connection already active, skipping acceptance"
        VPC_PEERING_ACCEPTED="true"
        save_peering_state
        return 0
    fi
    
    if [[ "$CURRENT_STATUS" != "pending-acceptance" ]]; then
        log_warning "Peering status is '${CURRENT_STATUS}', attempting to accept anyway..."
    fi
    
    log_info "Running AWS CLI to accept peering connection..."
    log_info "Command: aws ec2 accept-vpc-peering-connection --vpc-peering-connection-id ${PEERING_ID} --region ${CLIENT_AWS_REGION}"
    
    # Accept the peering connection with visible output
    AWS_OUTPUT=$(mktemp)
    aws ec2 accept-vpc-peering-connection \
        --vpc-peering-connection-id "${PEERING_ID}" \
        --region "${CLIENT_AWS_REGION}" \
        --no-cli-pager > "$AWS_OUTPUT" 2>&1
    
    AWS_EXIT_CODE=$?
    
    if [ $AWS_EXIT_CODE -ne 0 ]; then
        log_error "Failed to accept VPC peering connection (exit code: $AWS_EXIT_CODE)"
        echo ""
        echo "AWS CLI Output:"
        cat "$AWS_OUTPUT"
        rm -f "$AWS_OUTPUT"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Check if peering connection exists:"
        echo "     aws ec2 describe-vpc-peering-connections --vpc-peering-connection-ids ${PEERING_ID} --region ${CLIENT_AWS_REGION}"
        echo "  2. Check AWS credentials:"
        echo "     aws sts get-caller-identity"
        echo "  3. Verify you have permission to accept peering connections"
        exit 1
    fi
    
    rm -f "$AWS_OUTPUT"
    log_success "VPC peering connection accepted via AWS CLI"
    
    VPC_PEERING_ACCEPTED="true"
    save_peering_state
}

configure_route_tables() {
    log_info "Configuring route tables..."
    
    local routes_added=0
    local routes_existed=0
    local routes_fixed=0
    
    for ROUTE_TABLE_ID in $ROUTE_TABLE_IDS; do
        log_info "Checking route table: ${ROUTE_TABLE_ID}"
        
        # Check if route already exists and get its details
        ROUTE_INFO=$(aws ec2 describe-route-tables \
            --region "${CLIENT_AWS_REGION}" \
            --route-table-id "${ROUTE_TABLE_ID}" \
            --query "RouteTables[0].Routes[?DestinationCidrBlock=='${DEST_CIDR}'].[VpcPeeringConnectionId,State]" \
            --output text 2>/dev/null)
        
        if [ -n "$ROUTE_INFO" ]; then
            # Route exists, check if it's valid
            EXISTING_PEERING_ID=$(echo "$ROUTE_INFO" | awk '{print $1}')
            ROUTE_STATE=$(echo "$ROUTE_INFO" | awk '{print $2}')
            
            if [ "$EXISTING_PEERING_ID" == "$PEERING_ID" ] && [ "$ROUTE_STATE" == "active" ]; then
                log_success "Route to ${DEST_CIDR} already correctly configured"
                routes_existed=$((routes_existed + 1))
                continue
            else
                # Route exists but is stale (blackhole) or pointing to wrong peering
                log_warning "Found stale route: peering=${EXISTING_PEERING_ID}, state=${ROUTE_STATE}"
                log_info "Deleting stale route..."
                
                aws ec2 delete-route \
                    --region "${CLIENT_AWS_REGION}" \
                    --route-table-id "${ROUTE_TABLE_ID}" \
                    --destination-cidr-block "${DEST_CIDR}" > /dev/null 2>&1
                
                if [ $? -eq 0 ]; then
                    log_success "Stale route deleted"
                    routes_fixed=$((routes_fixed + 1))
                else
                    log_error "Failed to delete stale route"
                    exit 1
                fi
            fi
        fi
        
        # Create route (either new or replacing stale one)
        log_info "Creating route to ${DEST_CIDR} via ${PEERING_ID}"
        aws ec2 create-route \
            --region "${CLIENT_AWS_REGION}" \
            --route-table-id "${ROUTE_TABLE_ID}" \
            --destination-cidr-block "${DEST_CIDR}" \
            --vpc-peering-connection-id "${PEERING_ID}" > /dev/null 2>&1
        
        if [ $? -eq 0 ]; then
            log_success "Route created in ${ROUTE_TABLE_ID}"
            routes_added=$((routes_added + 1))
        else
            log_error "Failed to create route in ${ROUTE_TABLE_ID}"
            exit 1
        fi
    done
    
    log_success "Routes configured: ${routes_added} added, ${routes_existed} already valid, ${routes_fixed} stale fixed"
    
    ROUTES_CONFIGURED="true"
    save_peering_state
}

associate_hosted_zone() {
    log_info "Associating VPC with private hosted zone..."
    
    # Associate VPC with hosted zone (might already be associated, so we allow failure)
    set +e  # Temporarily disable exit on error
    ASSOC_OUTPUT=$(aws route53 associate-vpc-with-hosted-zone \
        --hosted-zone-id "${ZONE_ID}" \
        --vpc VPCRegion="${CLIENT_AWS_REGION}",VPCId="${CLIENT_VPC_ID}" 2>&1)
    ASSOC_EXIT_CODE=$?
    set -e  # Re-enable exit on error
    
    if [ $ASSOC_EXIT_CODE -eq 0 ]; then
        log_success "VPC associated with hosted zone ${ZONE_ID}"
    elif echo "$ASSOC_OUTPUT" | grep -q "ConflictingDomainExists\|already associated"; then
        log_success "VPC already associated with hosted zone ${ZONE_ID}"
    else
        log_warning "VPC association status unclear, but continuing (error: ${ASSOC_OUTPUT})"
    fi
    
    DNS_CONFIGURED="true"
    save_peering_state
}

configure_security_groups() {
    log_info "Checking security group configuration..."
    
    # Get security group IDs from client config
    if [ -z "$CLIENT_SECURITY_GROUPS" ]; then
        log_warning "No security groups found in client config, skipping security group configuration"
        return 0
    fi
    
    log_info "Security groups to configure: ${CLIENT_SECURITY_GROUPS}"
    
    # Split comma-separated security groups
    IFS=',' read -ra SG_ARRAY <<< "$CLIENT_SECURITY_GROUPS"
    
    for SG_ID in "${SG_ARRAY[@]}"; do
        SG_ID=$(echo "$SG_ID" | xargs)  # Trim whitespace
        
        log_info "Configuring security group: ${SG_ID}"
        
        # Check if outbound rule for port 4000 exists
        EXISTING_RULE=$(aws ec2 describe-security-group-rules \
            --region "${CLIENT_AWS_REGION}" \
            --filters "Name=group-id,Values=${SG_ID}" \
            --query "SecurityGroupRules[?CidrIpv4=='${DEST_CIDR}' && FromPort==\`4000\` && ToPort==\`4000\`]" \
            --output text 2>/dev/null)
        
        if [ -n "$EXISTING_RULE" ]; then
            log_warning "Outbound rule for port 4000 to ${DEST_CIDR} already exists in ${SG_ID}"
        else
            log_info "Adding outbound rule for Aerospike port 4000..."
            aws ec2 authorize-security-group-egress \
                --region "${CLIENT_AWS_REGION}" \
                --group-id "${SG_ID}" \
                --ip-permissions IpProtocol=tcp,FromPort=4000,ToPort=4000,IpRanges="[{CidrIp=${DEST_CIDR},Description='Aerospike Cloud TLS'}]" > /dev/null 2>&1
            
            if [ $? -eq 0 ]; then
                log_success "Added outbound rule for port 4000"
            else
                log_warning "Failed to add outbound rule (may already exist)"
            fi
        fi
        
        # Optionally add port 3000 for non-TLS
        log_info "Adding outbound rule for Aerospike port 3000 (non-TLS, optional)..."
        aws ec2 authorize-security-group-egress \
            --region "${CLIENT_AWS_REGION}" \
            --group-id "${SG_ID}" \
            --ip-permissions IpProtocol=tcp,FromPort=3000,ToPort=3000,IpRanges="[{CidrIp=${DEST_CIDR},Description='Aerospike Cloud non-TLS'}]" > /dev/null 2>&1 || true
        
        # Add prometheus exporter port 9145 (optional)
        log_info "Adding outbound rule for Prometheus port 9145 (optional)..."
        aws ec2 authorize-security-group-egress \
            --region "${CLIENT_AWS_REGION}" \
            --group-id "${SG_ID}" \
            --ip-permissions IpProtocol=tcp,FromPort=9145,ToPort=9145,IpRanges="[{CidrIp=${DEST_CIDR},Description='Aerospike Prometheus Exporter'}]" > /dev/null 2>&1 || true
    done
    
    log_success "Security groups configured"
}

test_connectivity() {
    log_info "Testing connectivity and resolving cluster IPs..."
    
    # Load client config
    if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
        log_error "Client config file not found"
        exit 1
    fi
    source "${CLIENT_CONFIG_DIR}/client_config.sh"
    
    # Get cluster hostname
    if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
        log_error "Cluster config file not found"
        exit 1
    fi
    source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
    
    if [ -z "$ACS_CLUSTER_HOSTNAME" ]; then
        log_error "Cluster hostname not found in config"
        exit 1
    fi
    
    if [ -z "$CLIENT_NAME" ]; then
        log_error "Client name not found in config"
        exit 1
    fi
    
    log_info "Cluster hostname: ${ACS_CLUSTER_HOSTNAME}"
    log_info "Client name: ${CLIENT_NAME}"
    
    # Check if this is a new setup or re-validation
    CLUSTER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
    EXISTING_IPS=$(grep "^export CLUSTER_IPS=" "$CLUSTER_CONFIG_FILE" 2>/dev/null | cut -d'"' -f2)
    
    # Configure aerolab backend
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" &>/dev/null
    
    # Test DNS resolution via client (with retry logic for new setups)
    DNS_OUTPUT=""
    EXIT_CODE=1
    
    if [ -z "$EXISTING_IPS" ]; then
        # First time setup - retry DNS resolution with backoff (up to 3 minutes)
        log_info "Resolving cluster IPs via DNS (with retry for propagation)..."
        
        MAX_ATTEMPTS=12
        WAIT_TIME=15
        
        for attempt in $(seq 1 $MAX_ATTEMPTS); do
            log_info "DNS resolution attempt ${attempt}/${MAX_ATTEMPTS}..."
            
            DNS_OUTPUT=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "dig +short ${ACS_CLUSTER_HOSTNAME}" 2>&1)
            EXIT_CODE=$?
            
            # Check if we got valid IPs
            if [ $EXIT_CODE -eq 0 ] && echo "$DNS_OUTPUT" | grep -qE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+'; then
                log_success "DNS resolution successful on attempt ${attempt}"
                break
            fi
            
            if [ $attempt -lt $MAX_ATTEMPTS ]; then
                log_info "No IPs yet, waiting ${WAIT_TIME} seconds before retry..."
                sleep $WAIT_TIME
            else
                log_warning "DNS resolution failed after ${MAX_ATTEMPTS} attempts"
            fi
        done
    else
        # Re-validation - single attempt
        log_info "Testing DNS resolution via client (re-validation)..."
        DNS_OUTPUT=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "dig +short ${ACS_CLUSTER_HOSTNAME}" 2>&1)
        EXIT_CODE=$?
    fi
    
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "DNS Resolution Test"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    
    if [ $EXIT_CODE -eq 0 ] && [ -n "$DNS_OUTPUT" ]; then
        # Extract IPs from output (use same pattern as verify_connectivity.sh)
        # Strip carriage returns, newlines, and extra spaces
        CLUSTER_IPS=$(echo "$DNS_OUTPUT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr -d '\r' | tr '\n' ',' | sed 's/,$//' | tr -d ' ')
        
        if [ -n "$CLUSTER_IPS" ]; then
            IP_COUNT=$(echo "$DNS_OUTPUT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l | tr -d ' ')
            
            log_success "DNS RESOLUTION: SUCCESS"
            echo ""
            echo "Resolved ${IP_COUNT} IP address(es):"
            echo "$DNS_OUTPUT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | while read ip; do
                echo "  - ${ip}"
            done
            echo ""
            
            # Save cluster IPs to cluster config
            # Ensure no carriage returns or other control characters in the value
            CLEAN_CLUSTER_IPS=$(echo "$CLUSTER_IPS" | tr -d '\r\n' | tr -s ' ' | xargs)
            CLUSTER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
            if ! grep -q "CLUSTER_IPS" "$CLUSTER_CONFIG_FILE" 2>/dev/null; then
                echo "export CLUSTER_IPS=\"${CLEAN_CLUSTER_IPS}\"" >> "$CLUSTER_CONFIG_FILE"
                log_success "Cluster IPs saved to config file"
            else
                # Update existing line - remove old line and append new one to avoid sed issues with special chars
                grep -v "^export CLUSTER_IPS=" "$CLUSTER_CONFIG_FILE" > "$CLUSTER_CONFIG_FILE.tmp"
                echo "export CLUSTER_IPS=\"${CLEAN_CLUSTER_IPS}\"" >> "$CLUSTER_CONFIG_FILE.tmp"
                mv "$CLUSTER_CONFIG_FILE.tmp" "$CLUSTER_CONFIG_FILE"
                log_success "Cluster IPs updated in config file"
            fi
            
            echo ""
            log_success "VPC peering is working correctly!"
            echo ""
            echo "Verification:"
            echo "  ✓ VPC peering connection is active"
            echo "  ✓ Route tables are configured"
            echo "  ✓ Private Hosted Zone is associated"
            echo "  ✓ DNS resolution is functional"
            echo ""
        else
            log_warning "DNS query succeeded but didn't return IP addresses"
            echo "DNS output: $DNS_OUTPUT"
            echo ""
        fi
    else
        log_warning "DNS RESOLUTION: FAILED"
        echo ""
        echo "⚠️  Could not resolve cluster IPs after multiple attempts."
        echo ""
        echo "This can happen if DNS propagation is slower than usual."
        echo ""
        echo "VPC peering setup will continue, but you may need to:"
        echo "  1. Wait a few minutes for DNS to propagate"
        echo "  2. Re-run setup to resolve and save IPs:"
        echo "     cd aeropsike-cloud && ./setup.sh"
        echo ""
        echo "You can also manually test DNS resolution:"
        echo "  aerolab client attach -n ${CLIENT_NAME} -l 1"
        echo "  dig +short ${ACS_CLUSTER_HOSTNAME}"
        echo ""
        echo "VPC peering is configured correctly - only IP resolution is pending."
        echo ""
    fi
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
}

display_summary() {
    echo ""
    echo "============================================"
    echo "✓ VPC PEERING SETUP COMPLETE!"
    echo "============================================"
    echo ""
    echo "Peering Details:"
    echo "  Peering ID: ${PEERING_ID}"
    echo "  Hosted Zone ID: ${ZONE_ID}"
    echo "  Client VPC: ${CLIENT_VPC_ID} (${CLIENT_VPC_CIDR})"
    echo "  Cluster CIDR: ${DEST_CIDR}"
    echo "  Status: Active"
    echo ""
    echo "Configuration Files:"
    echo "  ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh"
    echo "  ${PEERING_STATE_FILE}"
    echo ""
    echo "Next Steps:"
    echo "  1. Test DNS resolution:"
    echo "     dig +short ${ACS_CLUSTER_HOSTNAME}"
    echo ""
    echo "  2. Test connectivity from client (SSH to ${CLIENT_PUBLIC_IPS}):"
    echo "     nc -zv <AEROSPIKE_IP> 4000"
    echo ""
    echo "  3. Connect with aql:"
    echo "     Get TLS certificate from Aerospike Cloud Console"
    echo "     aql --tls-enable --tls-name ${ACS_CLUSTER_ID} --tls-cafile <cert> -h ${ACS_CLUSTER_HOSTNAME}:4000"
    echo ""
}

# ============================================
# Main Execution
# ============================================

main() {
    echo "============================================"
    echo "Aerospike Cloud - VPC Peering Setup"
    echo "============================================"
    echo ""
    
    # Load existing state if available
    if [ -f "$PEERING_STATE_FILE" ]; then
        source "$PEERING_STATE_FILE"
        log_info "Loaded existing peering state"
    else
        # Initialize state
        VPC_PEERING_INITIATED="false"
        VPC_PEERING_ACCEPTED="false"
        ROUTES_CONFIGURED="false"
        DNS_CONFIGURED="false"
        PEERING_ID=""
        ZONE_ID=""
    fi
    
    # Step 1: Validate prerequisites
    validate_prerequisites
    get_aws_account_id
    get_route_table_ids
    check_cidr_overlap
    
    echo ""
    
    # Step 1.5: Check if VPC peering already exists and is configured
    set +e  # Temporarily disable exit on error (using return codes for flow control)
    validate_existing_peering
    PEERING_STATUS=$?
    set -e  # Re-enable exit on error
    
    case $PEERING_STATUS in
        0)  # Fully configured and active
            log_info "VPC peering is already fully configured"
            # Get peering details and validate routes/DNS
            get_peering_details
            
            # Validate and fix routes if needed
            log_info "Validating route tables..."
            configure_route_tables
            
            # Validate DNS configuration
            log_info "Validating DNS configuration..."
            associate_hosted_zone
            
            # Configure security groups
            configure_security_groups
            
            # Test connectivity
            test_connectivity
            
            # Display summary
            display_summary
            
            # Clean up state file
            rm -f "$PEERING_STATE_FILE"
            return 0
            ;;
        1)  # Pending acceptance
            log_info "Resuming from pending-acceptance state..."
            get_peering_details
            accept_peering_connection
            wait_for_peering_status "active"
            configure_route_tables
            associate_hosted_zone
            configure_security_groups
            test_connectivity
            display_summary
            rm -f "$PEERING_STATE_FILE"
            return 0
            ;;
        2)  # Provisioning
            log_info "Waiting for peering to be ready..."
            wait_for_peering_status "pending-acceptance"
            get_peering_details
            accept_peering_connection
            wait_for_peering_status "active"
            configure_route_tables
            associate_hosted_zone
            configure_security_groups
            test_connectivity
            display_summary
            rm -f "$PEERING_STATE_FILE"
            return 0
            ;;
        4)  # Need to create
            log_info "Creating new VPC peering..."
            ;;
        *)  # Unknown or error
            log_warning "Unknown peering state, proceeding with setup..."
            ;;
    esac
    
    # Step 2: Initiate VPC peering (if not done)
    if [[ "$VPC_PEERING_INITIATED" != "true" ]]; then
        initiate_vpc_peering
        sleep 10
    fi
    
    # Step 3: Wait for pending-acceptance status
    wait_for_peering_status "pending-acceptance"
    
    # Step 4: Get peering details
    if [ -z "$PEERING_ID" ] || [ -z "$ZONE_ID" ]; then
        get_peering_details
    fi
    
    # Step 5: Accept peering connection (if not done)
    if [[ "$VPC_PEERING_ACCEPTED" != "true" ]]; then
        accept_peering_connection
    fi
    
    # Step 6: Wait for active status
    wait_for_peering_status "active"
    
    # Step 7: Configure route tables (if not done)
    if [[ "$ROUTES_CONFIGURED" != "true" ]]; then
        configure_route_tables
    fi
    
    # Step 8: Associate hosted zone (if not done)
    if [[ "$DNS_CONFIGURED" != "true" ]]; then
        associate_hosted_zone
    fi
    
    # Step 9: Configure security groups
    configure_security_groups
    
    # Step 10: Test connectivity
    test_connectivity
    
    # Display summary
    display_summary
    
    # Clean up state file
    rm -f "$PEERING_STATE_FILE"
}

# Run main
main

