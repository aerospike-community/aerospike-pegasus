if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Parse command line arguments (check if already set via export)
if [ -z "$SKIP_CONFIRM" ]; then
    SKIP_CONFIRM=false
fi

if [[ "$1" == "--yes" ]] || [[ "$1" == "-y" ]]; then
    SKIP_CONFIRM=true
fi

echo "====================================="
echo "Aerospike Cloud - Cluster Destroy"
echo "====================================="
echo ""

# Source common functions
. $PREFIX/api-scripts/common.sh

# Check if current_cluster.sh exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "No cluster found in tracker file."
    echo "Looking for cluster by name '${ACS_CLUSTER_NAME}'..."
    
    ACS_CLUSTER_ID=$(acs_get_cluster_id "${ACS_CLUSTER_NAME}" 2>/dev/null)
    
    if [ -z "$ACS_CLUSTER_ID" ]; then
        echo "⚠️  No cluster found with name '${ACS_CLUSTER_NAME}' (may already be deleted)"
        # Clean up any leftover local files
        if [ -d "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}" ]; then
            rm -rf "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}"
            echo "✓ Cleaned up local configuration files"
        fi
        return 0
    fi
    
    echo "Found cluster ID: ${ACS_CLUSTER_ID}"
else
    # Load cluster info from tracker
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    echo "Found tracked cluster:"
    echo "  Name: ${ACS_CLUSTER_NAME}"
    echo "  ID: ${ACS_CLUSTER_ID}"
fi

# Get current status
ACS_CLUSTER_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}" 2>/dev/null)
echo "  Current status: ${ACS_CLUSTER_STATUS}"
echo ""

# Confirm deletion
if [[ "$SKIP_CONFIRM" == false ]]; then
    read -p "Are you sure you want to delete cluster '${ACS_CLUSTER_NAME}' (${ACS_CLUSTER_ID})? [y/N]: " -n 1 -r
    echo ""
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Deletion cancelled."
        exit 0
    fi
else
    echo "Skipping confirmation (--yes flag provided)"
fi

echo ""
echo "Deleting cluster..."

# Call the destroy API
HTTP_CODE=$(curl -s "${REST_API_URI}/${ACS_CLUSTER_ID}" \
    -X DELETE \
    -H "@${ACS_AUTH_HEADER}" \
    -w '%{http_code}' \
    -o /dev/null)

if [[ "${HTTP_CODE}" -eq "202" ]] || [[ "${HTTP_CODE}" -eq "204" ]]; then
    echo "✓ Cluster deletion initiated successfully (HTTP ${HTTP_CODE})"
    echo ""
    
    # Clean up tracker files and entire cluster folder
    echo "Cleaning up cluster files..."
    
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        # Check if the current_cluster.sh matches this cluster
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        if [ "${ACS_CLUSTER_NAME}" == "$(basename $(dirname ${CLIENT_CONFIG_DIR}))" ]; then
            rm -f "${ACS_CONFIG_DIR}/current_cluster.sh"
            echo "✓ Removed ${ACS_CONFIG_DIR}/current_cluster.sh"
        fi
    fi
    
    # Remove the entire cluster folder (includes state, client, and cluster ID subfolder)
    if [ -d "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}" ]; then
        rm -rf "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}"
        echo "✓ Removed ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/"
    fi
    
    echo ""
    echo "====================================="
    echo "✓ Cluster destruction complete!"
    echo "====================================="
    echo "Note: The cluster may take a few minutes to fully decommission."
    echo "You can verify by checking the Aerospike Cloud console."
    
else
    echo ""
    echo "⚠️  Failed to delete cluster!"
    echo "HTTP Response Code: ${HTTP_CODE}"
    
    # Try to get error details
    ERROR_RESPONSE=$(curl -s "${REST_API_URI}/${ACS_CLUSTER_ID}" \
        -X DELETE \
        -H "@${ACS_AUTH_HEADER}")
    
    if [ -n "$ERROR_RESPONSE" ]; then
        echo ""
        echo "API Error Response:"
        echo "$ERROR_RESPONSE" | jq '.' 2>/dev/null || echo "$ERROR_RESPONSE"
    fi
    
    # Clean up local files even if API call failed
    echo ""
    echo "Cleaning up local configuration files..."
    if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
        source "${ACS_CONFIG_DIR}/current_cluster.sh"
        if [ "${ACS_CLUSTER_NAME}" == "$(basename $(dirname ${CLIENT_CONFIG_DIR}))" ]; then
            rm -f "${ACS_CONFIG_DIR}/current_cluster.sh"
            echo "✓ Removed ${ACS_CONFIG_DIR}/current_cluster.sh"
        fi
    fi
    
    if [ -d "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}" ]; then
        rm -rf "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}"
        echo "✓ Removed ${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/"
    fi
    
    return 1
fi
