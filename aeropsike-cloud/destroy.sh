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

# Destroy VPC peering first (if exists)
if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
        echo "VPC peering configuration found, destroying..."
        . $PREFIX/vpc_peering_destroy.sh --yes
    fi
fi

# Then destroy Grafana (if exists)
if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/grafana_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${GRAFANA_NAME}"; then
    echo "Grafana instance found, destroying..."
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    aerolab client destroy -n "${GRAFANA_NAME}" -f 2>/dev/null
    echo "✓ Grafana destroyed"
fi

# Then destroy client (if exists)
if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${CLIENT_NAME}"; then
    . $PREFIX/client_destroy.sh
fi

# Finally destroy cluster (skip confirmation)
export SKIP_CONFIRM=true
. $PREFIX/cluster_destroy.sh
