#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Source common functions
. $PREFIX/api-scripts/common.sh

echo "============================================"
echo "Aerospike Cloud - Connectivity Verification"
echo "============================================"
echo ""

# ============================================
# Validation
# ============================================

# Check if cluster exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "❌ ERROR: No cluster found!"
    echo "Please run './setup.sh' first."
    exit 1
fi

source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Check if client exists
if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
    echo "❌ ERROR: No client found!"
    echo "Please run './setup.sh' first."
    exit 1
fi

source "${CLIENT_CONFIG_DIR}/client_config.sh"

# Check if VPC peering exists
if [ ! -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
    echo "⚠️  WARNING: VPC peering not configured!"
    echo "Connectivity test will likely fail."
    echo ""
    read -p "Continue anyway? [y/N]: " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 0
    fi
fi

# Get cluster hostname
ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}" 2>/dev/null)

if [ -z "$ACS_CLUSTER_HOSTNAME" ]; then
    echo "❌ ERROR: Failed to get cluster hostname"
    exit 1
fi

echo "Test Configuration:"
echo "  Cluster: ${ACS_CLUSTER_NAME}"
echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
echo "  Client: ${CLIENT_NAME}"
echo "  Client IPs: ${CLIENT_PUBLIC_IPS}"
echo ""

# ============================================
# Create test script to run on client
# ============================================

TEST_SCRIPT=$(cat <<'EOF'
#!/bin/bash

HOSTNAME="$1"
CLUSTER_ID="$2"

echo "============================================"
echo "Running Connectivity Tests from Client"
echo "============================================"
echo ""

# Test 1: DNS Resolution
echo "Test 1: DNS Resolution"
echo "  Testing: dig +short ${HOSTNAME}"
echo ""

DNS_RESULT=$(dig +short ${HOSTNAME} 2>&1)
DNS_EXIT_CODE=$?

if [ $DNS_EXIT_CODE -eq 0 ] && [ -n "$DNS_RESULT" ]; then
    echo "  ✓ DNS Resolution: SUCCESS"
    echo "  Resolved IPs:"
    echo "$DNS_RESULT" | while read ip; do
        echo "    - ${ip}"
    done
    
    # Save first IP for connectivity tests
    FIRST_IP=$(echo "$DNS_RESULT" | head -1)
else
    echo "  ❌ DNS Resolution: FAILED"
    echo "  Error: $DNS_RESULT"
    echo ""
    echo "  Troubleshooting:"
    echo "    1. Check VPC DNS settings (enableDnsSupport, enableDnsHostnames)"
    echo "    2. Verify Private Hosted Zone association"
    echo "    3. Wait a few minutes for DNS propagation"
    exit 1
fi

echo ""

# Test 2: Port 4000 (TLS)
echo "Test 2: TCP Connectivity to Port 4000 (Aerospike TLS)"
echo "  Testing: nc -zv ${FIRST_IP} 4000"
echo ""

NC_OUTPUT=$(timeout 10 nc -zv ${FIRST_IP} 4000 2>&1)
NC_EXIT_CODE=$?

if [ $NC_EXIT_CODE -eq 0 ]; then
    echo "  ✓ Port 4000: ACCESSIBLE"
else
    echo "  ❌ Port 4000: NOT ACCESSIBLE"
    echo "  Output: $NC_OUTPUT"
    echo ""
    echo "  Troubleshooting:"
    echo "    1. Check security group outbound rules"
    echo "    2. Verify route table entries to cluster CIDR"
    echo "    3. Confirm VPC peering status is 'active'"
fi

echo ""

# Test 3: Port 3000 (Non-TLS, optional)
echo "Test 3: TCP Connectivity to Port 3000 (Aerospike Non-TLS)"
echo "  Testing: nc -zv ${FIRST_IP} 3000"
echo ""

NC_OUTPUT_3000=$(timeout 5 nc -zv ${FIRST_IP} 3000 2>&1)
NC_EXIT_CODE_3000=$?

if [ $NC_EXIT_CODE_3000 -eq 0 ]; then
    echo "  ✓ Port 3000: ACCESSIBLE"
else
    echo "  ⚠️  Port 3000: NOT ACCESSIBLE (optional)"
    echo "  Note: Non-TLS port may be disabled on cluster"
fi

echo ""

# Test 4: Port 9145 (Prometheus metrics, optional)
echo "Test 4: TCP Connectivity to Port 9145 (Prometheus Metrics)"
echo "  Testing: nc -zv ${FIRST_IP} 9145"
echo ""

NC_OUTPUT_9145=$(timeout 5 nc -zv ${FIRST_IP} 9145 2>&1)
NC_EXIT_CODE_9145=$?

if [ $NC_EXIT_CODE_9145 -eq 0 ]; then
    echo "  ✓ Port 9145: ACCESSIBLE"
else
    echo "  ⚠️  Port 9145: NOT ACCESSIBLE (optional)"
    echo "  Note: Metrics port access is optional"
fi

echo ""

# Test 5: AQL Connection (if aql is available)
echo "Test 5: Aerospike AQL Connection"
echo ""

if command -v aql &> /dev/null; then
    echo "  Testing AQL connection (without TLS)..."
    echo "  Command: aql -h ${FIRST_IP}:3000 -c 'show namespaces'"
    echo ""
    
    AQL_OUTPUT=$(timeout 10 aql -h ${FIRST_IP}:3000 -c 'show namespaces' 2>&1)
    AQL_EXIT_CODE=$?
    
    if [ $AQL_EXIT_CODE -eq 0 ]; then
        echo "  ✓ AQL Connection: SUCCESS"
        echo "$AQL_OUTPUT"
    else
        echo "  ⚠️  AQL Connection: FAILED"
        echo "  Note: TLS may be required or port 3000 may be disabled"
        echo ""
        echo "  To connect with TLS:"
        echo "    1. Get TLS certificate from Aerospike Cloud Console"
        echo "    2. Run: aql --tls-enable --tls-name ${CLUSTER_ID} --tls-cafile <cert> -h ${HOSTNAME}:4000"
    fi
else
    echo "  ℹ️  aql not installed, skipping AQL connection test"
    echo ""
    echo "  To install aql:"
    echo "    sudo apt-get update"
    echo "    sudo apt-get install aerospike-tools"
fi

echo ""
echo "============================================"
echo "Connectivity Test Summary"
echo "============================================"
echo ""

if [ $DNS_EXIT_CODE -eq 0 ] && [ $NC_EXIT_CODE -eq 0 ]; then
    echo "✓ All critical tests passed!"
    echo "  - DNS resolution: SUCCESS"
    echo "  - Port 4000 (TLS): ACCESSIBLE"
    echo ""
    echo "Your client can connect to the Aerospike Cloud cluster."
    exit 0
elif [ $DNS_EXIT_CODE -eq 0 ]; then
    echo "⚠️  DNS works but connectivity failed"
    echo "  - DNS resolution: SUCCESS"
    echo "  - Port 4000 (TLS): FAILED"
    echo ""
    echo "Check security groups and route tables."
    exit 1
else
    echo "❌ Critical tests failed"
    echo "  - DNS resolution: FAILED"
    echo ""
    echo "Check VPC DNS settings and Private Hosted Zone."
    exit 1
fi
EOF
)

# ============================================
# Run test script on client via aerolab
# ============================================

echo "Connecting to client via aerolab..."
echo ""

# Configure aerolab backend
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null

# Upload and run test script
REMOTE_SCRIPT="/tmp/connectivity_test.sh"

echo "Uploading test script to client..."
echo "$TEST_SCRIPT" | aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "cat > ${REMOTE_SCRIPT} && chmod +x ${REMOTE_SCRIPT}"

if [ $? -ne 0 ]; then
    echo "❌ ERROR: Failed to upload test script"
    exit 1
fi

echo ""
echo "Running connectivity tests..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Run the test script
aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "${REMOTE_SCRIPT} ${ACS_CLUSTER_HOSTNAME} ${ACS_CLUSTER_ID}"
TEST_EXIT_CODE=$?

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Clean up
aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "rm -f ${REMOTE_SCRIPT}" 2>/dev/null

# ============================================
# Summary and Recommendations
# ============================================

if [ $TEST_EXIT_CODE -eq 0 ]; then
    echo "============================================"
    echo "✓ CONNECTIVITY VERIFICATION: SUCCESS"
    echo "============================================"
    echo ""
    echo "Your setup is ready for workload deployment!"
    echo ""
    echo "Next Steps:"
    echo "  1. Build Perseus workload: ./client/buildPerseus.sh"
    echo "  2. Run workload: ./client/runPerseus.sh"
    echo ""
else
    echo "============================================"
    echo "❌ CONNECTIVITY VERIFICATION: FAILED"
    echo "============================================"
    echo ""
    echo "Please fix the issues above before running workloads."
    echo ""
    echo "Common fixes:"
    echo "  1. Ensure VPC peering is active in both AWS and Aerospike Cloud"
    echo "  2. Check security group rules allow outbound to cluster CIDR"
    echo "  3. Verify route tables have entries to cluster CIDR via peering"
    echo "  4. Wait a few minutes for DNS propagation"
    echo ""
    echo "To manually debug:"
    echo "  aerolab client attach -n ${CLIENT_NAME} shell -l 1"
    echo "  Then run: dig +short ${ACS_CLUSTER_HOSTNAME}"
    echo ""
    exit 1
fi

