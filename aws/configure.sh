# AWS Config
AWS_REGION="us-east-1"
AWS_EXPIRE="12h" # length of life of nodes prior to expiry; seconds, minutes, hours, ex 20h 30m. 0 for no expiry.

# Aerospike Config
VER="8.0.0.4"
CLUSTER_NAME="Demo"
CLUSTER_NUMBER_OF_NODES="2"
CLUSTER_INSTANCE_TYPE="i7ie.3xlarge"

# Namespace Config
NAMESPACE_NAME="Test"
NAMESPACE_DEFAULT_TTL="0"
NAMESPACE_PRIMARY_INDEX_STORAGE_TYPE="MEMORY" #MEMORY, DISK
NAMESPACE_SECONDARY_INDEX_STORAGE_TYPE="MEMORY" #MEMORY, DISK
NAMESPACE_DATA_STORAGE_TYPE="DISK" #MEMORY, DISK
NAMESPACE_REPLICATION_FACTOR=2
NAMESPACE_COMPRESSION="snappy" #none, lz4, snappy,i zstd

# NVMe Config
NUMBER_OF_PARTITION_ON_EACH_NVME="6"
OVERPROVISIONING_PERCENTAGE=15
PRIMARY_INDEX_STORAGE_PARTITIONS="1"
PARTITION_TREE_SPRIGS=65536
SECONDARY_INDEX_STORAGE_PARTITIONS="3-4" # Set if the secondary indexes are on Disk.
DATA_STORAGE_PARTITIONS="1-6" # Set if either the primary or secondary indexes are stored on Disk.

# GRAFANA Config
GRAFANA_NAME=${CLUSTER_NAME}"_GRAFANA"
GRAFANA_INSTANCE_TYPE="t3.xlarge"

# Client Instance Config
CLIENT_NAME="Perseus_${CLUSTER_NAME}"
CLIENT_INSTANCE_TYPE="c6i.4xlarge" #Choose instances with more cpus, more than 32 GB of RAM, and no NVMe. C6a family are good choices.
CLIENT_NUMBER_OF_NODES=2

# Client Generic Workload Config
TRUNCATE_SET=False
RECORD_SIZE=1120 #Bytes. This test doesn't allow records smaller than 178 bytes!
BATCH_READ_SIZE=200
BATCH_WRITE_SIZE=100
READ_HIT_RATIO=.75

# Client Caching Config
KEY_CACHE_CAPACITY=1000000000 #The instance must have enough RAM to keep the key cache in memory. Each entry is 8 Bytes. 1 billion entries need 8 GB of Ram
KEY_CACHE_SAVE_RATIO=1.0

# Client Query Workload Config
STRING_INDEX=True
NUMERIC_INDEX=False
GEO_SPATIAL_INDEX=False
UDF_AFFREGATION=False
RANGE_QUERY=False

# Client Range Query Workload Config
NORMAL_RANGE=5
MAX_RANGE=100
CHANCE_OF_MAX=.00001

# setup backend
aerolab config backend -t aws -r ${AWS_REGION}
