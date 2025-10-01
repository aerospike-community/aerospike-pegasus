# AWS Config
AWS_REGION="us-east-1"
AWS_EXPIRE="24h" # length of life of nodes prior to expiry; seconds, minutes, hours, ex 20h 30m. 0 for no expiry.

# Aerospike Config
VER="8.0.0.4"
CLUSTER_NAME="Benchmark"
CLUSTER_NUMBER_OF_NODES="3"
CLUSTER_INSTANCE_TYPE="r6gd.8xlarge"

# Namespace Config
NAMESPACE_NAME="Test"
NAMESPACE_DEFAULT_TTL="0"
NAMESPACE_PRIMARY_INDEX_STORAGE_TYPE="MEMORY" #MEMORY, DISK
NAMESPACE_SECONDARY_INDEX_STORAGE_TYPE="MEMORY" #MEMORY, DISK
NAMESPACE_DATA_STORAGE_TYPE="DISK" #MEMORY, DISK
NAMESPACE_REPLICATION_FACTOR=2
NAMESPACE_COMPRESSION="none" #none, lz4, snappy,i zstd

# NVMe Config
NUMBER_OF_PARTITION_ON_EACH_NVME="5"
OVERPROVISIONING_PERCENTAGE=15
PRIMARY_INDEX_STORAGE_PARTITIONS="1"
PARTITION_TREE_SPRIGS=65536
SECONDARY_INDEX_STORAGE_PARTITIONS="1" # Set if the secondary indexes are on Disk.
DATA_STORAGE_PARTITIONS="1-5" # Set if either the primary or secondary indexes are stored on Disk.

# GRAFANA Config
GRAFANA_NAME=${CLUSTER_NAME}"_GRAFANA"
GRAFANA_INSTANCE_TYPE="t3.xlarge"

# Client Instance Config
CLIENT_NAME="Perseus_${CLUSTER_NAME}"
CLIENT_INSTANCE_TYPE="c6i.4xlarge" #Choose instances with more cpus, more than 32 GB of RAM, and no NVMe. C6a family are good choices.
CLIENT_NUMBER_OF_NODES=1

# Client Generic Workload Config
TRUNCATE_SET=False
RECORD_SIZE=300 #Bytes. This test doesn't allow records smaller than 178 bytes!
BATCH_READ_SIZE=200
BATCH_WRITE_SIZE=100
READ_HIT_RATIO=1

# Client Query Workload Config
STRING_INDEX=False
NUMERIC_INDEX=False
GEO_SPATIAL_INDEX=False
UDF_AFFREGATION=False
RANGE_QUERY=False

# Client Range Query Workload Config
NORMAL_RANGE=10
MAX_RANGE=100
CHANCE_OF_MAX=.01

# setup backend
aerolab config backend -t aws -r ${AWS_REGION}
