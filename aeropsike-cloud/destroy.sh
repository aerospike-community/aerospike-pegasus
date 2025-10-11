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

# Then destroy client (if exists)
if [ -f "${CLIENT_CONFIG_DIR}/client_config.sh" ] || aerolab client list 2>/dev/null | grep -q "${CLIENT_NAME}"; then
    . $PREFIX/client_destroy.sh
fi

# Finally destroy cluster
. $PREFIX/cluster_destroy.sh

# TODO: Implement Grafana destroy for Aerospike Cloud
# . $PREFIX/grafana_destroy.sh
