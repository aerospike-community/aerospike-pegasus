if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

. $PREFIX/cluster_destroy.sh

# TODO: Implement client and grafana destroy for Aerospike Cloud
# . $PREFIX/client_destroy.sh
# . $PREFIX/grafana_destroy.sh
