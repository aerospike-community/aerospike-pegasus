#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

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

# Construct cluster hostname (pattern: {cluster-id}.aerospike.internal)
ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_ID}.aerospike.internal"

echo "Test Configuration:"
echo "  Cluster: ${ACS_CLUSTER_NAME}"
echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
echo "  Client: ${CLIENT_NAME}"
echo ""

# ============================================
# Run DNS test on client
# ============================================

echo "Configuring aerolab backend..."
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" &>/dev/null

echo ""
echo "Connecting to client and testing DNS resolution..."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Running: dig +short ${ACS_CLUSTER_HOSTNAME}"
echo ""

# Run dig command on client
DNS_RESULT=$(aerolab client attach -n "${CLIENT_NAME}" -l 1 -- "dig +short ${ACS_CLUSTER_HOSTNAME}" 2>&1)
EXIT_CODE=$?

echo "$DNS_RESULT"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================
# Analyze results
# ============================================

if [ $EXIT_CODE -eq 0 ] && [ -n "$DNS_RESULT" ]; then
    # Check if result contains IP addresses (allow leading/trailing whitespace)
    IP_COUNT=$(echo "$DNS_RESULT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | wc -l | tr -d ' ')
    
    if [ "$IP_COUNT" -gt 0 ]; then
        # Extract IPs as comma-separated list
        CLUSTER_IPS=$(echo "$DNS_RESULT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | tr '\n' ',' | sed 's/,$//')
        
        echo "============================================"
        echo "✓ DNS RESOLUTION: SUCCESS"
        echo "============================================"
        echo ""
        echo "Resolved ${IP_COUNT} IP address(es):"
        echo "$DNS_RESULT" | grep -E '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | while read ip; do
            echo "  - ${ip}"
        done
        echo ""
        
        # Save cluster IPs to cluster config
        CLUSTER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
        if [ -f "$CLUSTER_CONFIG_FILE" ]; then
            # Check if CLUSTER_IPS is already in the file
            if ! grep -q "CLUSTER_IPS" "$CLUSTER_CONFIG_FILE"; then
                echo "export CLUSTER_IPS=\"${CLUSTER_IPS}\"" >> "$CLUSTER_CONFIG_FILE"
                echo "✓ Cluster IPs saved to: ${CLUSTER_CONFIG_FILE}"
                echo ""
            fi
        fi
        
        echo "✅ Your client can resolve the cluster hostname!"
        echo ""
        echo "This means:"
        echo "  ✓ VPC peering is working"
        echo "  ✓ Private Hosted Zone is associated correctly"
        echo "  ✓ DNS resolution is functional"
        echo ""
        echo "Next Steps:"
        echo "  1. Test port connectivity: nc -zv <ip> 4000"
        echo "  2. Build Perseus workload: ./client/buildPerseus.sh"
        echo "  3. Run workload: ./client/runPerseus.sh"
        echo ""
        exit 0
    else
        echo "============================================"
        echo "⚠️  DNS RESOLUTION: UNEXPECTED RESULT"
        echo "============================================"
        echo ""
        echo "DNS query succeeded but didn't return IP addresses."
        echo "This might indicate a DNS configuration issue."
        echo ""
        exit 1
    fi
else
    echo "============================================"
    echo "❌ DNS RESOLUTION: FAILED"
    echo "============================================"
    echo ""
    echo "The DNS query failed or returned no results."
    echo ""
    echo "Troubleshooting:"
    echo "  1. Check if VPC peering is active:"
    echo "     - In Aerospike Cloud Console"
    echo "     - In AWS VPC Console"
    echo ""
    echo "  2. Verify Private Hosted Zone association:"
    echo "     source ~/.aerospike-cloud/${ACS_CLUSTER_ID}/vpc_peering.sh"
    echo "     aws route53 list-hosted-zones-by-vpc \\"
    echo "       --vpc-id \${CLIENT_VPC_ID} \\"
    echo "       --vpc-region ${CLIENT_AWS_REGION}"
    echo ""
    echo "  3. Check VPC DNS settings:"
    echo "     aws ec2 describe-vpc-attribute \\"
    echo "       --vpc-id \${CLIENT_VPC_ID} \\"
    echo "       --attribute enableDnsHostnames"
    echo ""
    echo "  4. Manually test from client:"
    echo "     aerolab client attach -n ${CLIENT_NAME} -l 1"
    echo "     dig +short ${ACS_CLUSTER_HOSTNAME}"
    echo ""
    exit 1
fi
