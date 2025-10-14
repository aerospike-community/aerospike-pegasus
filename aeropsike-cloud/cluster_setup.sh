if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

echo "====================================="
echo "Aerospike Cloud - Cluster Setup"
echo "====================================="

# Step 1: Create credentials directory if it doesn't exist
echo ""
echo "Setting up credentials directory at ${ACS_CONFIG_DIR}..."
mkdir -p "${ACS_CONFIG_DIR}"

# Step 2: Check if credentials config file exists
if [ ! -f "${ACS_CONFIG_DIR}/credentials.conf" ]; then
    echo ""
    echo "Credentials config file not found. Creating from API key CSV file..."
    
    # Look for API key CSV file in multiple locations:
    # 1. Inside credentials directory
    # 2. In ACS_CONFIG_DIR
    # 3. In parent directory of script
    API_KEY_FILE=""
    
    if [ -d "${ACS_CONFIG_DIR}/credentials" ]; then
        API_KEY_FILE=$(find ${ACS_CONFIG_DIR}/credentials -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" | head -n 1)
    fi
    
    if [ -z "$API_KEY_FILE" ]; then
        API_KEY_FILE=$(find ${ACS_CONFIG_DIR} -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" | head -n 1)
    fi
    
    if [ -z "$API_KEY_FILE" ]; then
        API_KEY_FILE=$(find $PREFIX/.. -maxdepth 1 -name "aerospike-cloud-apikey-*.csv" | head -n 1)
    fi
    
    if [ -n "$API_KEY_FILE" ]; then
        echo "Found API key file: $API_KEY_FILE"
        
        # Extract client_id and client_secret from CSV (skip header line)
        CLIENT_ID=$(tail -n 1 "$API_KEY_FILE" | cut -d',' -f2)
        CLIENT_SECRET=$(tail -n 1 "$API_KEY_FILE" | cut -d',' -f3)
        
        # Create credentials config file
        cat > "${ACS_CONFIG_DIR}/credentials.conf" <<EOF
# Aerospike Cloud Credentials
# Generated from API key CSV file: $(basename "$API_KEY_FILE")
ACS_CLIENT_ID="${CLIENT_ID}"
ACS_CLIENT_SECRET="${CLIENT_SECRET}"
EOF
        
        echo "Credentials config file created successfully at ${ACS_CONFIG_DIR}/credentials.conf"
        
        # Reload configure.sh to pick up the new credentials
        . $PREFIX/configure.sh
    else
        echo ""
        echo "ERROR: No API key CSV file found!"
        echo "Please create ${ACS_CONFIG_DIR}/credentials.conf manually with the following content:"
        echo ""
        echo "ACS_CLIENT_ID=\"your-client-id\""
        echo "ACS_CLIENT_SECRET=\"your-client-secret\""
        echo ""
        exit 1
    fi
fi

# Step 3: Verify credentials are loaded
if [ -z "$ACS_CLIENT_ID" ] || [ -z "$ACS_CLIENT_SECRET" ]; then
    echo ""
    echo "ERROR: Credentials not loaded properly!"
    echo "Please check ${ACS_CONFIG_DIR}/credentials.conf file."
    exit 1
fi

# Step 4: Acquire authentication token
echo ""
echo "Acquiring authentication token..."
. $PREFIX/api-scripts/get-token.sh

# Step 5: Verify token was generated
if [ ! -f "${ACS_CONFIG_DIR}/auth.header" ]; then
    echo ""
    echo "ERROR: Failed to generate authentication token!"
    echo "Please check your credentials and try again."
    exit 1
fi

echo ""
echo "✓ Authentication successful!"
echo "  Token saved to: ${ACS_CONFIG_DIR}/auth.header"
echo "  Token is valid for 8 hours."
echo ""

# Step 5: Check if cluster already exists
echo "====================================="
echo "Database Cluster Creation"
echo "====================================="
echo ""

# Source common functions
. $PREFIX/api-scripts/common.sh

# Spinning indicator function
spin() {
    local pid=$1
    local delay=0.1
    local spinstr='|/-\'
    while ps -p $pid > /dev/null 2>&1; do
        local temp=${spinstr#?}
        printf " [%c]  " "$spinstr"
        local spinstr=$temp${spinstr%"$temp"}
        sleep $delay
        printf "\b\b\b\b\b\b"
    done
    printf "    \b\b\b\b"
}

# Check if cluster already exists
echo "Checking if cluster '${ACS_CLUSTER_NAME}' already exists..."
ACS_CLUSTER_ID=$(acs_get_cluster_id "${ACS_CLUSTER_NAME}" 2>/dev/null)

CLUSTER_ALREADY_EXISTS=false

if [[ -n "$ACS_CLUSTER_ID" ]]; then
    CLUSTER_ALREADY_EXISTS=true
    echo "✓ Cluster already exists with ID: ${ACS_CLUSTER_ID}"
    ACS_CLUSTER_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}" 2>/dev/null)
    echo "  Current status: ${ACS_CLUSTER_STATUS}"
    
    # Save cluster info immediately
    cat > "${ACS_CONFIG_DIR}/current_cluster.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="${ACS_CLUSTER_STATUS}"
EOF
    
    # Create or update cluster config file
    mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
    
    # If cluster is active, get connection details
    if [[ "${ACS_CLUSTER_STATUS}" == "active" ]]; then
        echo ""
        echo "✓ Cluster is active and ready to use!"
        
        # Get connection details from API
        ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}")
        ACS_CLUSTER_TLSNAME=$(acs_get_cluster_tls_name "${ACS_CLUSTER_ID}")
        
        # Get and save TLS certificate
        echo "Downloading TLS certificate..."
        ACS_CLUSTER_TLS_CERT=$(acs_get_cluster_tls_cert "${ACS_CLUSTER_ID}")
        if [ -n "$ACS_CLUSTER_TLS_CERT" ] && [ "$ACS_CLUSTER_TLS_CERT" != "null" ]; then
            echo "$ACS_CLUSTER_TLS_CERT" > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/ca.pem"
            echo "✓ TLS certificate saved to ca.pem"
        fi
        
        # Create cluster config with full details
        cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="${ACS_CLUSTER_STATUS}"
export ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_HOSTNAME}"
export ACS_CLUSTER_TLSNAME="${ACS_CLUSTER_TLSNAME}"
export SERVICE_PORT=4000
EOF
        
        echo ""
        echo "Connection Details:"
        echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
        echo "  TLS Name: ${ACS_CLUSTER_TLSNAME}"
        echo "  Port: 4000 (TLS)"
        echo ""
        return 0  # Use return instead of exit when sourced
    elif [[ "${ACS_CLUSTER_STATUS}" == "provisioning" ]]; then
        echo ""
        echo "Cluster is still provisioning."
        
        # Create basic cluster config file (connection details will be added when active)
        cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="provisioning"
# Connection details will be added when cluster becomes active
EOF
        
        echo "✓ Created basic cluster config file"
        
        # If skip provision wait, return early for parallel execution
        if [[ "$SKIP_PROVISION_WAIT" == "true" ]]; then
            echo "  Parallel client setup will begin now..."
            echo ""
            return 0  # Use return instead of exit when sourced
        fi
        
        echo "Continuing to monitor..."
        # Will continue to provisioning wait section below
    else
        echo ""
        echo "Cluster status: ${ACS_CLUSTER_STATUS}"
        echo "Please check the cluster manually in Aerospike Cloud console."
        exit 0
    fi
fi

# Step 6: Create the database cluster (only if it doesn't exist)
if [[ "$CLUSTER_ALREADY_EXISTS" == false ]]; then
    echo ""
    echo "Creating new database cluster '${ACS_CLUSTER_NAME}'..."
    echo "  Provider: ${CLOUD_PROVIDER}"
    echo "  Region: ${CLOUD_REGION}"
    echo "  Instance Type: ${INSTANCE_TYPE}"
    echo "  Cluster Size: ${CLUSTER_SIZE} nodes"
    echo "  AZ Count: ${AVAILABILITY_ZONE_COUNT}"
    echo "  Data Storage: ${DATA_STORAGE}"
    echo "  VPC CIDR: ${DEST_CIDR}"
    echo "  Namespace: ${NAMESPACE_NAME}"
    echo ""
    
    # Build the JSON payload
    JSON_PAYLOAD=$(cat <<EOF
{
  "name": "${ACS_CLUSTER_NAME}",
  "infrastructure": {
    "provider": "${CLOUD_PROVIDER}",
    "instanceType": "${INSTANCE_TYPE}",
    "region": "${CLOUD_REGION}",
    "availabilityZoneCount": ${AVAILABILITY_ZONE_COUNT},
    "cidrBlock": "${DEST_CIDR}"
  },
  "aerospikeCloud": {
    "clusterSize": ${CLUSTER_SIZE},
    "dataStorage": "${DATA_STORAGE}"
  },
  "aerospikeServer": {
    "namespaces": [
      {
        "name": "${NAMESPACE_NAME}",
        "replication-factor": ${NAMESPACE_REPLICATION_FACTOR}
      }
    ]
  }
}
EOF
)
    
    # Add optional fields if set
    if [ -n "$DATA_RESILIENCY" ]; then
        JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq ".aerospikeCloud.dataResiliency = \"${DATA_RESILIENCY}\"")
    fi
    
    if [ -n "$NAMESPACE_COMPRESSION" ]; then
        JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq ".aerospikeServer.namespaces[0].compression = \"${NAMESPACE_COMPRESSION}\"")
    fi
    
    if [ -n "$AEROSPIKE_VERSION" ]; then
        JSON_PAYLOAD=$(echo "$JSON_PAYLOAD" | jq ".dataPlaneVersion = \"${AEROSPIKE_VERSION}\"")
    fi
    
    # Note: Network configuration (TLS/non-TLS ports) is managed by Aerospike Cloud
    # and cannot be configured at cluster creation time. By default, clusters use
    # TLS on port 4000. For non-TLS, you would need to update via the API after creation.
    
    # Create the cluster
    API_RESPONSE=$(mktemp)
    HTTP_CODE=$(
        curl "${REST_API_URI}" \
             -sX POST \
             -H 'content-type: application/json' \
             -H "@${ACS_AUTH_HEADER}" \
             --data "${JSON_PAYLOAD}" \
             -w '%{http_code}' \
             -o "${API_RESPONSE}"
    )
    
    echo "API Response Code: ${HTTP_CODE}"
    
    if [[ "${HTTP_CODE}" -ne "202" ]]; then
        echo ""
        echo "ERROR: Failed to create cluster!"
        echo "HTTP Response Code: ${HTTP_CODE}"
        echo ""
        
        # Show API error message if available
        if [ -s "${API_RESPONSE}" ]; then
            echo "API Error Response:"
            cat "${API_RESPONSE}" | jq '.' 2>/dev/null || cat "${API_RESPONSE}"
            echo ""
        fi
        
        echo "Payload sent:"
        echo "${JSON_PAYLOAD}" | jq '.'
        
        rm -f "${API_RESPONSE}"
        exit 1
    fi
    
    rm -f "${API_RESPONSE}"
    
    echo "✓ Cluster creation request accepted!"
    echo ""
    
    # Wait for the cluster to be registered
    echo "Waiting for cluster to be registered"
    sleep 5
    
    # Get the cluster ID
    ACS_CLUSTER_ID=$(acs_get_cluster_id "${ACS_CLUSTER_NAME}")
    
    if [[ -z "$ACS_CLUSTER_ID" ]]; then
        echo "ERROR: Cluster ID was not found after creation."
        exit 1
    fi

    echo "✓ Cluster created with ID: ${ACS_CLUSTER_ID}"
    
    # Save cluster info immediately (even if provisioning)
    mkdir -p "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}"
    
    cat > "${ACS_CONFIG_DIR}/current_cluster.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="provisioning"
EOF

    # Create basic cluster config file immediately
    cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="provisioning"
# Connection details will be added when cluster becomes active
EOF
    
    echo "✓ Created basic cluster config file"

fi  # End of cluster creation block

# Check if we should skip provision wait (for parallel execution)
if [[ "$SKIP_PROVISION_WAIT" == "true" ]]; then
    echo ""
    echo "✓ Cluster setup initiated successfully!"
    echo "  Status: provisioning"
    echo "  Parallel client setup will begin now..."
    echo ""
    return 0  # Use return instead of exit when sourced
fi

# Wait for cluster provisioning with better progress indicator
echo ""
echo "====================================="
echo "Provisioning Cluster"
echo "====================================="
echo "This typically takes 10-20 minutes."
echo "You can safely interrupt (Ctrl+C) and re-run setup.sh to resume."
echo ""

PROVISION_START=$(date +%s)
CHECK_COUNT=0
set +e

while true; do
    CURRENT_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}")
    
    # Update status in file
    cat > "${ACS_CONFIG_DIR}/current_cluster.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="${CURRENT_STATUS}"
EOF
    
    if [[ "${CURRENT_STATUS}" != "provisioning" ]]; then
        break
    fi
    
    CHECK_COUNT=$((CHECK_COUNT + 1))
    ELAPSED=$(( $(date +%s) - PROVISION_START ))
    MINUTES=$(( ELAPSED / 60 ))
    SECONDS=$(( ELAPSED % 60 ))
    
    # Show progress with spinning indicator
    printf "\r⏳ Status: provisioning | Elapsed: %02d:%02d | Checks: %d " $MINUTES $SECONDS $CHECK_COUNT
    
    # Rotate spinner characters
    case $((CHECK_COUNT % 4)) in
        0) printf "[|]" ;;
        1) printf "[/]" ;;
        2) printf "[-]" ;;
        3) printf "[\\]" ;;
    esac
    
    # Wait 60 seconds (1 minute) between checks
    sleep 60
done

set -e

FINAL_STATUS="${CURRENT_STATUS}"
TOTAL_ELAPSED=$(( $(date +%s) - PROVISION_START ))
TOTAL_MINUTES=$(( TOTAL_ELAPSED / 60 ))
TOTAL_SECONDS=$(( TOTAL_ELAPSED % 60 ))

echo ""
echo ""
echo "====================================="
echo "✓ Cluster status: ${FINAL_STATUS}"
echo "  Total provisioning time: ${TOTAL_MINUTES}m ${TOTAL_SECONDS}s"
echo "====================================="

# Get connection details from API
ACS_CLUSTER_HOSTNAME=$(acs_get_cluster_hostname "${ACS_CLUSTER_ID}")
ACS_CLUSTER_TLSNAME=$(acs_get_cluster_tls_name "${ACS_CLUSTER_ID}")

# Get and save TLS certificate
echo "Downloading TLS certificate..."
ACS_CLUSTER_TLS_CERT=$(acs_get_cluster_tls_cert "${ACS_CLUSTER_ID}")
if [ -n "$ACS_CLUSTER_TLS_CERT" ] && [ "$ACS_CLUSTER_TLS_CERT" != "null" ]; then
    echo "$ACS_CLUSTER_TLS_CERT" > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/ca.pem"
    echo "✓ TLS certificate saved to ca.pem"
fi

# Update cluster config file with full connection details
cat > "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh" <<EOF
export ACS_CLUSTER_ID="${ACS_CLUSTER_ID}"
export ACS_CLUSTER_NAME="${ACS_CLUSTER_NAME}"
export ACS_CLUSTER_STATUS="active"
export ACS_CLUSTER_HOSTNAME="${ACS_CLUSTER_HOSTNAME}"
export ACS_CLUSTER_TLSNAME="${ACS_CLUSTER_TLSNAME}"
export SERVICE_PORT=4000
EOF

echo ""
echo "Connection Details:"
echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
echo "  TLS Name: ${ACS_CLUSTER_TLSNAME}"
echo "  Port: 4000 (TLS)"
echo ""
echo "Cluster setup complete!"
