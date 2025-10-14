# Aerospike Cloud Setup

Automated setup for Aerospike Cloud clusters with client instances and Perseus benchmarking tool.

## Prerequisites

- **Aerospike Cloud API Key**: Download from [Aerospike Cloud Console](https://cloud.aerospike.com)
- **aerolab**: Install from [Github](https://github.com/aerospike/aerolab)
- **AWS CLI**: Configured with credentials
- **jq**: JSON processor (`brew install jq` on macOS)

## Quick Start

### 1. Configuration

Edit `configure.sh` to set your cluster configuration:

```bash
# Cluster Settings
ACS_CLUSTER_NAME="test-skr"          # Your cluster name
CLUSTER_SIZE="2"                      # Number of nodes
CLOUD_REGION="ap-south-1"            # AWS region
INSTANCE_TYPE="i4i.large"            # Instance type

# Namespace
NAMESPACE_NAME="test"

# Note: Aerospike Cloud clusters use TLS by default on port 4000
```

### 2. Add API Key

Place your Aerospike Cloud API key CSV file in the project root:
```bash
aerospike-cloud-apikey-XXXXX.csv
```

### 3. Setup Cluster

Run the complete setup:
```bash
cd aeropsike-cloud
./setup.sh
```

This will:
- Authenticate with Aerospike Cloud
- Create the database cluster
- Set up VPC peering
- Create client instances
- Build Perseus benchmarking tool (does not start it automatically)

**Note**: Full setup takes 15-30 minutes.

### 4. Run Perseus Benchmarking

After setup completes, run Perseus:
```bash
cd ../client
./runPerseus.sh
```

This will:
- Upload TLS certificate to client instances
- Configure Perseus with cluster connection details
- Start Perseus benchmarking tool
- Open terminal windows to monitor each client's output

To rebuild Perseus (after code changes):
```bash
./buildPerseus.sh
```

## Script Idempotency

All setup scripts are **idempotent** - you can safely run them multiple times:

- **Cluster Setup**: Checks if cluster exists before creating. If it exists, retrieves connection details and continues.
- **VPC Peering**: Verifies existing peering before creating new connections. Skips if already configured.
- **Client Setup**: Checks if client instances exist. Re-uses existing instances if found.
- **Perseus Build**: Rebuilds only if source changed. Safe to re-run after failures.

**Benefits**:
- Resume interrupted setups without cleanup
- Update configurations by re-running scripts
- No risk of creating duplicate resources
- Safe to use in automation/CI pipelines

**State Management**: The setup system maintains state for each resource in `~/.aerospike-cloud/`. On every run, it checks the actual state of each component (cluster, VPC peering, client instances) and updates the local state accordingly. This intelligent state tracking means:

- If setup is interrupted at any point, re-running `./setup.sh` will resume from where it left off
- Scripts detect resources deleted outside the automation (e.g., manual deletion of client/grafana/cluster etc )
- State files are automatically synchronized with the actual cloud resources
- You can safely run setup scripts even after network failures or timeouts

**Example**: If cluster creation succeeds but VPC peering fails due to a network issue, simply re-run `./setup.sh`. The script will:
1. Detect the existing cluster and retrieve its details
2. Skip cluster creation entirely
3. Continue with VPC peering setup
4. Proceed with remaining components

### 5. Individual Components

Run components separately if needed:

```bash
# Just create the cluster
./cluster_setup.sh

# Setup VPC peering (after cluster is ready)
./vpc_peering_setup.sh

# Setup client instances
cd ../client
./setup.sh

# Build Perseus
./buildPerseus.sh

# Run Perseus benchmarking
./runPerseus.sh
```

## Connection Details

After setup, cluster details are saved in:
```
~/.aerospike-cloud/<cluster-name>/<cluster-id>/
├── cluster_config.sh    # Connection details
├── db_user.sh          # Database credentials  
└── ca.pem              # TLS certificate (if TLS enabled)
```

## Perseus Workload Configuration

Edit `configure.sh` to adjust Perseus workload parameters:

```bash
# Workload Settings
RECORD_SIZE=300
BATCH_READ_SIZE=200
BATCH_WRITE_SIZE=100
READ_HIT_RATIO=1

# Enable/disable features
STRING_INDEX=False
NUMERIC_INDEX=False
```

## Cleanup

### Destroy All Resources

```bash
cd aeropsike-cloud
./destroy.sh [cluster-name]
```

**Options**:
- `cluster-name` - (Optional) Specify a specific cluster to destroy. If omitted, destroys the cluster configured in `configure.sh`

This removes:
- Aerospike Cloud cluster
- Client instances  
- Grafana instance
- VPC peering connections

**Example**:
```bash
# Destroy the configured cluster (interactive, with confirmation)
./destroy.sh

# Destroy a specific cluster
./destroy.sh my-other-cluster
```

### Destroy Individual Components

You can also destroy components separately:

```bash
# Destroy only the cluster (prompts for confirmation)
./cluster_destroy.sh

# Destroy cluster without confirmation
./cluster_destroy.sh --yes

# Destroy VPC peering
./vpc_peering_destroy.sh

# Destroy VPC peering without confirmation  
./vpc_peering_destroy.sh --yes

# Destroy client instances
./client_destroy.sh

# Destroy Grafana
./grafana_destroy.sh
```

**Available Flags**:
- `--yes` or `-y` - Skip confirmation prompts (useful for automation)

**Note**: The main `destroy.sh` script automatically skips confirmations for sub-components. Confirmations are only shown when running individual destroy scripts directly.
