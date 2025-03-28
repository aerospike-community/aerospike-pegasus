if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

echo $PREFIX

. $PREFIX/client_destroy.sh
. $PREFIX/grafana_destroy.sh
. $PREFIX/cluster_destroy.sh
