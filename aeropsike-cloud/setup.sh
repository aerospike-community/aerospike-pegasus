PREFIX=$(pwd "$0")"/"$(dirname "$0")
. $PREFIX/configure.sh

. $PREFIX/cluster_setup.sh

# TODO: Implement client and grafana setup for Aerospike Cloud
# . $PREFIX/client_setup.sh
# . $PREFIX/grafana_setup.sh
