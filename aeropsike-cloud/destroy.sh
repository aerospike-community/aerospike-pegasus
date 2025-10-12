if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Destroy VPC peering first (if exists)
if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/vpc_peering.sh" ]; then
        echo "VPC peering configuration found, destroying..."
        . $PREFIX/vpc_peering_destroy.sh --yes
    fi
fi

# Then destroy Grafana (if exists)
if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${GRAFANA_NAME}"; then
    echo "Grafana instance found, destroying..."
    aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" 2>/dev/null
    aerolab client destroy -n "${GRAFANA_NAME}" -f 2>/dev/null
    rm -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/grafana_config.sh"
    echo "✓ Grafana destroyed"
fi

# Then destroy client (if exists)
if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${CLIENT_NAME}"; then
    . $PREFIX/client_destroy.sh
fi

# Finally destroy cluster
. $PREFIX/cluster_destroy.sh
