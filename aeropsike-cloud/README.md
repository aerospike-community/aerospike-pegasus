# Aerospike Cloud Setup

This directory contains scripts for setting up and managing Aerospike Cloud clusters.

## Directory Structure

```
aeropsike-cloud/
├── setup.sh              # Main setup script
├── configure.sh          # Configuration variables
├── cluster_setup.sh      # Cluster setup and authentication
├── client_setup.sh       # Client setup
├── grafana_setup.sh      # Grafana setup
├── api-scripts/          # API utility scripts
│   └── get-token.sh     # Authentication token generation
└── README.md            # This file
```

## Prerequisites

1. **API Key CSV File**: Download your Aerospike Cloud API key CSV file from the Aerospike Cloud console
2. **Dependencies**: 
   - `curl` - for API calls
   - `jq` - for JSON processing

## Configuration

### Credentials Directory

The scripts automatically create and use `~/.aerospike-cloud/` to store:
- `credentials` - Your API key ID and secret
- `token.json` - OAuth token response (valid for 8 hours)
- `auth.header` - Authorization header for API calls

### Initial Setup

1. **Place your API key CSV file** in the project root directory (e.g., `aerospike-cloud-apikey-*.csv`)

2. **Run the setup script**:
   ```bash
   cd aeropsike-cloud
   ./setup.sh
   ```

3. The script will automatically:
   - Create the `~/.aerospike-cloud/` directory
   - Extract credentials from the CSV file
   - Generate a credentials file
   - Acquire an authentication token

### Manual Credentials Setup

If you prefer to set up credentials manually, create `~/.aerospike-cloud/credentials`:

```bash
mkdir -p ~/.aerospike-cloud
cat > ~/.aerospike-cloud/credentials <<EOF
ACS_CLIENT_ID="your-client-id"
ACS_CLIENT_SECRET="your-client-secret"
EOF
```

## Configuration Variables

Edit `configure.sh` to customize your setup:

### Cluster Configuration
- `ACS_CLUSTER_NAME` - Name of the database cluster (default: "Benchmark")
- `CLUSTER_SIZE` - Number of nodes in the cluster (default: 3)

### Infrastructure Configuration
- `CLOUD_PROVIDER` - Cloud provider: `aws` or `gcp` (default: "aws")
- `CLOUD_REGION` - Deployment region (default: "us-east-1")
- `INSTANCE_TYPE` - Instance type for nodes (default: "m5d.large")
- `AVAILABILITY_ZONE_COUNT` - Number of availability zones 1-3 (default: 2)
- `DEST_CIDR` - /19 IPv4 CIDR block for VPC (default: "10.128.0.0/19")
  - **Note:** Cannot use `10.129.0.0/19` (reserved for ACS internal use)

### Aerospike Cloud Configuration
- `DATA_STORAGE` - Data storage type (default: "local-disk")
  - Options: `memory`, `local-disk`, `network-storage`
- `DATA_RESILIENCY` - Optional persistence layer
  - For memory: `local-disk` or `network-storage`
  - For local-disk: `network-storage`
- `AEROSPIKE_VERSION` - Optional: specific version (leave empty for latest)

### Namespace Configuration
- `NAMESPACE_NAME` - Namespace name (default: "test")
- `NAMESPACE_REPLICATION_FACTOR` - Replication factor (default: 2)
- `NAMESPACE_COMPRESSION` - Optional: `none`, `lz4`, `snappy`, `zstd`

See `configure.sh` for all available configuration options.

## API Endpoints

- **Authentication**: `https://auth.control.aerospike.cloud/oauth/token`
- **API Base**: `https://api.aerospike.cloud/v2`

## Token Management

Authentication tokens are valid for **8 hours**. If your token expires:

```bash
cd aeropsike-cloud
./api-scripts/get-token.sh
```

## Cluster Setup Process

The `setup.sh` script performs **parallel execution** for faster setup:

### Phase 1: Start Cluster Setup
1. **Authentication** - Acquires OAuth token from Aerospike Cloud
2. **Cluster Check** - Verifies if cluster already exists
3. **Cluster Creation** - Creates new database cluster if needed

### Phase 2-3: Parallel Execution (⚡ **40% faster!**)
- **Client Setup** (5-10 min) - Provisions EC2 instances while cluster provisions
- **Cluster Provisioning** (15-20 min) - Monitors status every 60 seconds

### Phase 4-5: Completion
4. **Final Checks** - Ensures both cluster and client are ready
5. **Connection Details** - Saves all configuration files

### Key Features
- ✅ **Parallel execution** - Client provisions while cluster provisions
- ✅ **Fully resumable** - Can interrupt (Ctrl+C) and re-run
- ✅ **State validation** - Validates against Aerospike Cloud API, AWS CLI, and aerolab
- ✅ **Smart recovery** - Detects manual changes and auto-corrects state
- ✅ **Live progress** - Shows elapsed time and spinning indicator
- ✅ **Total time**: ~15-20 minutes (vs 20-30 minutes sequential)

See [PARALLEL_SETUP.md](PARALLEL_SETUP.md) and [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for detailed documentation.

### Resumable Setup with State Validation

The setup process is fully resumable with real-time validation! 

**On every run:**
- ✅ Validates cluster status via **Aerospike Cloud API**
- ✅ Validates client existence via **aerolab**
- ✅ Validates VPC peering via **Aerospike Cloud API + AWS CLI**
- ✅ Auto-corrects state if resources were manually changed
- ✅ Resumes from the correct phase

**If interrupted:**
- State is saved to `~/.aerospike-cloud/setup_state.sh`
- Simply re-run `./setup.sh` to resume
- Validation ensures state matches reality

See [STATE_MANAGEMENT.md](STATE_MANAGEMENT.md) for comprehensive validation details.

### Cluster Files

After successful setup, cluster information is saved to:
```
~/.aerospike-cloud/
├── current_cluster.sh              # Current cluster ID and name
└── {cluster-id}/
    └── cluster_config.sh           # Connection details (hostname, TLS, port)
```

## Client Setup

After your cluster is active, provision client instances to run workloads:

```bash
./client_setup.sh
```

The client setup:
1. ✅ **Provisions EC2 instances** using aerolab in a **separate VPC**
2. ✅ **Extracts all details** (VPC ID, subnet IDs, instance IDs, IPs)
3. ✅ **Tracks configuration** in `~/.aerospike-cloud/client/`
4. ✅ **Prepares for VPC peering** with the Aerospike Cloud cluster

### Client Configuration

```
~/.aerospike-cloud/
└── client/
    ├── client_config.sh    # Environment variables (VPC ID, IPs, etc.)
    └── client_info.json    # Full client details
```

See [CLIENT_SETUP.md](CLIENT_SETUP.md) for detailed documentation.

## VPC Peering Setup

Enable private connectivity between your client VPC and Aerospike Cloud cluster:

```bash
./vpc_peering_setup.sh
```

The VPC peering setup:
1. ✅ **Validates prerequisites** (cluster active, client provisioned)
2. ✅ **Initiates peering request** via Aerospike Cloud API
3. ✅ **Accepts peering connection** in AWS
4. ✅ **Configures route tables** automatically
5. ✅ **Associates Private Hosted Zone** for DNS resolution
6. ✅ **Configures security groups** (ports 4000, 3000, 9145)
7. ✅ **Tests connectivity** and DNS resolution
8. ✅ **Fully resumable** with state management

### What Gets Configured

- **VPC Peering Connection** between client VPC and Aerospike Cloud VPC
- **Route table entries** to Aerospike Cloud CIDR (10.131.0.0/19)
- **DNS resolution** via Private Hosted Zone association
- **Security group rules** for Aerospike ports (4000 TLS, 3000 non-TLS, 9145 metrics)

### Configuration Files

```
~/.aerospike-cloud/
└── {cluster-id}/
    └── vpc_peering.sh      # Peering ID, Zone ID, CIDR blocks
```

### Testing Connectivity

**Automated Verification (Recommended):**

```bash
./verify_connectivity.sh
```

This script automatically:
- ✅ Uses aerolab to SSH into the client
- ✅ Tests DNS resolution of cluster hostname
- ✅ Tests TCP connectivity to ports 4000, 3000, 9145
- ✅ Attempts AQL connection (if installed)
- ✅ Provides detailed troubleshooting if tests fail

**Manual Testing (from client instance):**

```bash
# SSH to client
source ~/.aerospike-cloud/client/client_config.sh
ssh -i ~/.ssh/key.pem ubuntu@${CLIENT_PUBLIC_IPS}

# Test DNS resolution
dig +short {cluster-hostname}

# Test port connectivity
nc -zv {aerospike-ip} 4000

# Connect with aql
aql --tls-enable --tls-name {cluster-id} \
    --tls-cafile {cert-path} \
    -h {hostname}:4000
```

## Destroy Resources

### Destroy Everything
```bash
./destroy.sh --yes    # Destroy VPC peering + client + cluster
```

### Destroy Components Individually
```bash
# Destroy only VPC peering
./vpc_peering_destroy.sh --yes

# Destroy only client
./client_destroy.sh

# Destroy only cluster
./cluster_destroy.sh --yes
```

**Destruction order:** VPC Peering → Client → Cluster

## Implementation Status

- ✅ **Authentication and token management**
- ✅ **Database cluster creation and monitoring**
- ✅ **Resumable cluster setup with state management**
- ✅ **Parallel execution** (client + cluster) - **40% faster setup!**
- ✅ **Client instance deployment with VPC tracking**
- ✅ **VPC peering setup** - Automated private connectivity
- ✅ **Complete teardown scripts with confirmation**
- 🔄 **Grafana monitoring setup** (coming soon)

## Troubleshooting

### Token Generation Fails
- Verify your credentials in `~/.aerospike-cloud/credentials`
- Check network connectivity to `auth.control.aerospike.cloud`
- Ensure `jq` is installed: `brew install jq` (macOS) or `apt-get install jq` (Linux)

### API Key CSV Not Found
- Ensure the CSV file is in the project root directory
- File name should match pattern: `aerospike-cloud-apikey-*.csv`

### Credentials Not Loading
- Check file permissions: `chmod 600 ~/.aerospike-cloud/credentials`
- Verify file format (no extra spaces or special characters)

