. $PREFIX"/../cluster/templates/prepareTemplates.sh"

# create cluster

echo "Grow the cluster"
aerolab cluster grow -n ${CLUSTER_NAME} -v ${VER} -o aerospike.conf --instance-type ${CLUSTER_INSTANCE_TYPE} --ebs=20 --start=n || exit 1
rm -rf aerospike.conf

New_Node_Number=$(aerolab cluster list -i | grep "cluster="${CLUSTER_NAME}" "| wc -l  | xargs)

echo "Configure NVMe disks"
OVERPROVISIONING=$(expr 100 - $OVERPROVISIONING_PERCENTAGE)
PARTITION_SIZE=$(expr $OVERPROVISIONING / $NUMBER_OF_PARTITION_ON_EACH_NVME)
for i in $(seq 1 $NUMBER_OF_PARTITION_ON_EACH_NVME); do P+=${PARTITION_SIZE}","; done
aerolab cluster partition create -n ${CLUSTER_NAME} --nodes=${New_Node_Number} -t nvme -p ${P%?} || exit 1

if [ "${NAMESPACE_DATA_STORAGE_TYPE}" = "DISK" ]; then
  echo "Configure Data Storage Type to Disk"
  aerolab cluster partition conf -n ${CLUSTER_NAME} --namespace=${NAMESPACE_NAME} --nodes=${New_Node_Number} --filter-type=nvme --configure=device || exit 1
  aerolab conf adjust -n ${CLUSTER_NAME} --nodes=${New_Node_Number}  set "namespace ${NAMESPACE_NAME}.storage-engine device.compression" ${NAMESPACE_COMPRESSION} || exit 1

fi

if [ "${NAMESPACE_PRIMARY_INDEX_STORAGE_TYPE}" = "MEMORY" ]; then
  echo "Configure Primary Index Storage Type to Memory"
  # Default
fi
if [ "${NAMESPACE_PRIMARY_INDEX_STORAGE_TYPE}" = "DISK" ]; then
  echo "Configure Primary Index Storage Type to Disk"
  aerolab cluster partition conf -n ${CLUSTER_NAME} --namespace=${NAMESPACE_NAME} --nodes=${New_Node_Number} --filter-type=nvme --configure=device --filter-partitions=${DATA_STORAGE_PARTITIONS} || exit 1
  aerolab cluster partition mkfs -n ${CLUSTER_NAME} --nodes=${New_Node_Number} --filter-type=nvme --filter-partitions=${PRIMARY_INDEX_STORAGE_PARTITIONS} || exit 1
  aerolab cluster partition conf -n ${CLUSTER_NAME} --namespace=${NAMESPACE_NAME} --nodes=${New_Node_Number} --filter-type=nvme --configure=pi-flash --filter-partitions=${PRIMARY_INDEX_STORAGE_PARTITIONS} || exit 1
  aerolab conf adjust -n ${CLUSTER_NAME} --nodes=${New_Node_Number} set "namespace ${NAMESPACE_NAME}.partition-tree-sprigs" ${PARTITION_TREE_SPRIGS} || exit 1
fi


if [ "${NAMESPACE_SECONDARY_INDEX_STORAGE_TYPE}" = "MEMORY" ]; then
  echo "Configure Secondary Index Storage Type to Memory"
  # Default
fi
if [ "${NAMESPACE_SECONDARY_INDEX_STORAGE_TYPE}" = "DISK" ]; then
  echo "Configure Secondary Index Storage Type to Disk"
  aerolab cluster partition conf -n ${CLUSTER_NAME} --namespace=${NAMESPACE_NAME} --nodes=${New_Node_Number} --filter-type=nvme --configure=device --filter-partitions=${DATA_STORAGE_PARTITIONS} || exit 1
  aerolab cluster partition mkfs -n ${CLUSTER_NAME} --nodes=${New_Node_Number} --filter-type=nvme --filter-partitions=${SECONDARY_INDEX_STORAGE_PARTITIONS} || exit 1
  aerolab cluster partition conf -n ${CLUSTER_NAME} --namespace=${NAMESPACE_NAME} --nodes=${New_Node_Number} --filter-type=nvme --configure=si-flash --filter-partitions=${SECONDARY_INDEX_STORAGE_PARTITIONS} || exit 1
fi

if [ "${NAMESPACE_DATA_STORAGE_TYPE}" = "MEMORY" ]; then
  echo "Configure Data Storage Type to Memory"
  aerolab conf namespace-memory -n ${CLUSTER_NAME} --nodes=${New_Node_Number} --namespace=${NAMESPACE_NAME} --mem-pct=75
  aerolab conf adjust -n ${CLUSTER_NAME} --nodes=${New_Node_Number} set "namespace ${NAMESPACE_NAME}.storage-engine memory.compression" ${NAMESPACE_COMPRESSION} || exit 1
fi


aerolab aerospike start -n ${CLUSTER_NAME} -l ${New_Node_Number}

# let the node join the cluster
echo "Wait"
sleep 10

# exporter
echo "Adding exporter"
aerolab cluster add exporter -n ${CLUSTER_NAME} -l ${New_Node_Number} -o $PREFIX"/../cluster/templates/ape.toml"

echo "Reconfiguring Prometheus"
aerolab client configure ams -n ${GRAFANA_NAME} -s ${CLUSTER_NAME}