# ==============================================
# Aerospike Cloud Configuration
# ==============================================

# Credentials Directory
ACS_CONFIG_DIR="${HOME}/.aerospike-cloud"

# API Configuration
AUTH_API_URI="https://auth.control.aerospike.cloud/oauth/token"
REST_API_URI="https://api.aerospike.cloud/v2/databases"
ACS_AUTH_HEADER="${ACS_CONFIG_DIR}/auth.header"

# Load Aerospike Cloud Credentials from credentials config file
if [ -f "${ACS_CONFIG_DIR}/credentials.conf" ]; then
    source "${ACS_CONFIG_DIR}/credentials.conf"
fi

# ==============================================
# Database/Cluster Configuration
# ==============================================

# Cluster Basic Config
ACS_CLUSTER_NAME="test-skr"
CLUSTER_SIZE="2"  # Number of nodes (must be divisible by AZ count)

# Infrastructure Config
CLOUD_PROVIDER="aws"  # aws, gcp
CLOUD_REGION="ap-south-1"
INSTANCE_TYPE="i4i.large"  # Instance type for the nodes
AVAILABILITY_ZONE_COUNT="2"  # Number of AZs (1-3)
DEST_CIDR="10.131.0.0/19"  # /19 IPv4 CIDR block for the database VPC (cannot be 10.129.0.0/19)

# Aerospike Cloud Config
DATA_STORAGE="local-disk"  # memory, local-disk, network-storage
DATA_RESILIENCY=""  # Optional: local-disk, network-storage (for in-memory or local-disk databases)

# Aerospike Server Config
AEROSPIKE_VERSION=""  # Optional: specific version, leave empty for latest

# Namespace Config
NAMESPACE_NAME="test"
NAMESPACE_REPLICATION_FACTOR="2"
NAMESPACE_COMPRESSION=""  # Optional: none, lz4, snappy, zstd

# Database User Config
DB_USER="adminas"
DB_PASSWORD="admin12345"

# ==============================================
# Client (AWS EC2) Configuration
# ==============================================

# AWS Config for Client
CLIENT_AWS_REGION="${CLOUD_REGION}"  # Use same region as cluster
CLIENT_AWS_EXPIRE="4h"  # Length of life of nodes prior to expiry

# Client VPC Config (separate from Aerospike Cloud cluster VPC)
CLIENT_VPC_CIDR="10.140.0.0/19"  # Different CIDR from cluster
CLIENT_VPC_NAME="aerospike-client-vpc-${ACS_CLUSTER_NAME}"

# Client Instance Config
CLIENT_NAME="Perseus_${ACS_CLUSTER_NAME}"
CLIENT_INSTANCE_TYPE="c6i.xlarge"  # Choose instances with more CPUs, >32GB RAM
CLIENT_NUMBER_OF_NODES=1

# Client Tracking (now cluster-specific)
CLIENT_CONFIG_DIR="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/client"

# Client Generic Workload Config
TRUNCATE_SET=False
RECORD_SIZE=300
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

# ==============================================
# Grafana/Monitoring Configuration
# ==============================================

# Grafana Instance Config
GRAFANA_NAME="${ACS_CLUSTER_NAME}_GRAFANA"
GRAFANA_INSTANCE_TYPE="t3.xlarge"
GRAFANA_AWS_EXPIRE="${CLIENT_AWS_EXPIRE}"

# Aerospike Cloud Prometheus Metrics Port
PROMETHEUS_PORT="9145"