if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Parse command line arguments for cluster name
CLUSTER_TO_DESTROY="${ACS_CLUSTER_NAME}"
if [ -n "$1" ]; then
    CLUSTER_TO_DESTROY="$1"
    echo "Destroying cluster: ${CLUSTER_TO_DESTROY}"
    # Update ACS_CLUSTER_NAME for this run
    export ACS_CLUSTER_NAME="${CLUSTER_TO_DESTROY}"
    # Reload configure to update dependent variables
    . $PREFIX/configure.sh
fi

echo "============================================"
echo "Destroying Cluster: ${ACS_CLUSTER_NAME}"
echo "============================================"
echo ""

# Track failures
FAILED_COMPONENTS=()

# Destroy VPC peering first (if exists)
if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
        echo "VPC peering configuration found, destroying..."
        (. $PREFIX/vpc_peering_destroy.sh --yes) || FAILED_COMPONENTS+=("VPC Peering")
        echo ""
    fi
fi

# Then destroy Grafana (if exists)
if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${GRAFANA_NAME}"; then
    echo "Grafana instance found, destroying..."
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    if aerolab client destroy -n "${GRAFANA_NAME}" -f 2>/dev/null; then
        echo "✓ Grafana destroyed"
    else
        echo "⚠️  Failed to destroy Grafana (may already be deleted)"
        FAILED_COMPONENTS+=("Grafana")
    fi
    echo ""
fi

# Then destroy client (if exists)
if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${CLIENT_NAME}"; then
    (. $PREFIX/client_destroy.sh) || FAILED_COMPONENTS+=("Client")
    echo ""
fi

# Finally destroy cluster (skip confirmation)
export SKIP_CONFIRM=true
(. $PREFIX/cluster_destroy.sh) || FAILED_COMPONENTS+=("Cluster")

# Report summary
echo ""
echo "============================================"
echo "Destroy Summary"
echo "============================================"
if [ ${#FAILED_COMPONENTS[@]} -eq 0 ]; then
    echo "✓ All components destroyed successfully"
    exit 0
else
    echo "⚠️  Some components failed to destroy:"
    for component in "${FAILED_COMPONENTS[@]}"; do
        echo "  - ${component}"
    done
    echo ""
    echo "Note: Components may have already been deleted manually."
    echo "Please verify in AWS Console and Aerospike Cloud Console."
    exit 1
fi
