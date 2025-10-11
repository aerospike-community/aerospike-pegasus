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

The `setup.sh` script performs the following steps:

1. **Authentication** - Acquires OAuth token from Aerospike Cloud
2. **Cluster Check** - Verifies if cluster already exists
3. **Cluster Creation** - Creates new database cluster if needed
4. **Provisioning Wait** - Monitors cluster status with live progress indicator
   - Checks status every 60 seconds
   - Shows elapsed time and spinning indicator
   - **Fully resumable** - Can interrupt (Ctrl+C) and re-run
5. **Connection Details** - Saves connection info to `~/.aerospike-cloud/{cluster-id}/`

### Resumable Setup

The setup process is fully resumable! If interrupted:
- Cluster state is saved to `~/.aerospike-cloud/current_cluster.sh`
- Simply re-run `./setup.sh` to resume from where you left off
- The script automatically detects existing clusters and their status

### Cluster Files

After successful setup, cluster information is saved to:
```
~/.aerospike-cloud/
├── current_cluster.sh              # Current cluster ID and name
└── {cluster-id}/
    └── cluster_config.sh           # Connection details (hostname, TLS, port)
```

## Next Steps

Future implementations will include:
1. ✅ Authentication and token management
2. ✅ Database cluster creation
3. 🔄 VPC peering setup
4. 🔄 Client instance deployment
5. 🔄 Grafana monitoring setup

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

