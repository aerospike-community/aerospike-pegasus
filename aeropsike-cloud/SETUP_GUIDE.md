# Aerospike Cloud Setup Guide

## Overview

This guide covers the setup process for creating and managing Aerospike Cloud database clusters using the Aerospike Cloud API.

## Prerequisites

Before running the setup, ensure you have:

1. **API Key CSV File**: Download from Aerospike Cloud console
2. **Required Tools**:
   - `curl` - for API calls
   - `jq` - for JSON processing (`brew install jq` on macOS)
   - `bash` - shell environment

## Quick Start

### 1. Place API Key File

Place your Aerospike Cloud API key CSV file in one of these locations:
- `~/.aerospike-cloud/credentials/` (recommended)
- `~/.aerospike-cloud/`
- Project root directory

The file name should match: `aerospike-cloud-apikey-*.csv`

### 2. Configure Settings (Optional)

Edit `configure.sh` to customize your cluster configuration:

```bash
# Cluster name and size
ACS_CLUSTER_NAME="Benchmark"
CLUSTER_SIZE="3"

# Infrastructure
CLOUD_PROVIDER="aws"
CLOUD_REGION="us-east-1"
INSTANCE_TYPE="m5d.large"
AVAILABILITY_ZONE_COUNT="2"
DEST_CIDR="10.128.0.0/19"

# Storage
DATA_STORAGE="local-disk"  # or "memory", "network-storage"

# Namespace
NAMESPACE_NAME="test"
NAMESPACE_REPLICATION_FACTOR="2"
```

### 3. Run Setup

```bash
cd aeropsike-cloud
./setup.sh
```

## Resumable Setup Process

The setup process is **fully resumable**! If you need to interrupt the setup (Ctrl+C):

1. The cluster state is saved to `~/.aerospike-cloud/current_cluster.sh`
2. Simply re-run `./setup.sh` to resume
3. The script will:
   - Skip credential setup (already done)
   - Check existing cluster status
   - Resume monitoring if still provisioning
   - Complete setup once provisioning finishes

## What Happens During Setup

### Step 1: Credentials Setup
- Creates `~/.aerospike-cloud/` directory
- Extracts credentials from CSV file
- Saves to `~/.aerospike-cloud/credentials.conf`

### Step 2: Authentication
- Calls OAuth endpoint: `https://auth.control.aerospike.cloud/oauth/token`
- Saves token to `~/.aerospike-cloud/token.json`
- Creates auth header at `~/.aerospike-cloud/auth.header`
- Token is valid for 8 hours

### Step 3: Cluster Check
- Queries API to see if cluster with same name exists
- If exists, displays current status and connection details
- If not exists, proceeds to create new cluster

### Step 4: Cluster Creation
- Builds JSON payload from configuration
- POSTs to `https://api.aerospike.cloud/v2/databases`
- Waits for HTTP 202 (Accepted) response

### Step 5: Provisioning Wait
- Polls cluster status every **60 seconds** (1 minute)
- Shows live progress with spinning indicator
- Displays elapsed time and check count
- Updates cluster status in `current_cluster.sh` on each check
- **Can be safely interrupted (Ctrl+C) and resumed**
- Typical provisioning time: 10-20 minutes

### Step 6: Connection Details
- Retrieves cluster hostname and TLS name
- Saves to `~/.aerospike-cloud/{cluster-id}/cluster_config.sh`
- Saves current cluster ID to `~/.aerospike-cloud/current_cluster.sh`

## File Structure After Setup

```
~/.aerospike-cloud/
├── credentials/
│   └── aerospike-cloud-apikey-*.csv      # Your API key CSV
├── credentials.conf                       # Extracted credentials
├── token.json                             # OAuth token response
├── auth.header                            # Authorization header
├── current_cluster.sh                     # Current cluster reference
└── {cluster-id}/
    └── cluster_config.sh                  # Connection details
```

## Configuration Options

### Instance Types

Choose appropriate instance types based on your workload:
- **Memory-optimized**: `r5.large`, `r5.xlarge`, `r6i.large`
- **Compute-optimized**: `c5.large`, `c5.xlarge`, `c6i.large`
- **Storage-optimized**: `i3.large`, `i3.xlarge`, `m5d.large`, `m6id.large`

### Data Storage Options

1. **Memory** (`memory`)
   - Fastest performance
   - Data stored in RAM
   - Optional persistence with `dataResiliency`

2. **Local Disk** (`local-disk`)
   - Uses NVMe SSDs
   - Good balance of performance and cost
   - Optional network backup with `dataResiliency`

3. **Network Storage** (`network-storage`)
   - Uses EBS volumes
   - Most durable
   - Slightly lower performance

### VPC CIDR Block

The `DEST_CIDR` must be a `/19` CIDR block (8,192 IP addresses):
- Valid: `10.128.0.0/19`, `10.0.0.0/19`, `172.16.0.0/19`
- **Invalid**: `10.129.0.0/19` (reserved by Aerospike Cloud)

## Example Configurations

### Development Cluster

```bash
ACS_CLUSTER_NAME="dev-cluster"
CLUSTER_SIZE="1"
INSTANCE_TYPE="m5d.large"
AVAILABILITY_ZONE_COUNT="1"
DATA_STORAGE="memory"
```

### Production Cluster

```bash
ACS_CLUSTER_NAME="prod-cluster"
CLUSTER_SIZE="6"
INSTANCE_TYPE="m5d.4xlarge"
AVAILABILITY_ZONE_COUNT="3"
DATA_STORAGE="local-disk"
DATA_RESILIENCY="network-storage"
NAMESPACE_REPLICATION_FACTOR="2"
```

### High-Performance Cluster

```bash
ACS_CLUSTER_NAME="high-perf"
CLUSTER_SIZE="9"
INSTANCE_TYPE="i3.4xlarge"
AVAILABILITY_ZONE_COUNT="3"
DATA_STORAGE="local-disk"
NAMESPACE_REPLICATION_FACTOR="3"
```

## Connecting to Your Cluster

After setup completes, connection details are displayed:

```
Connection Details:
  Hostname: xxx-xxx.aerospike.cloud
  TLS Name: xxx-xxx.aerospike.cloud
  Port: 4000
```

Use these details to connect with Aerospike tools:
- `asadm`
- `aql`
- Client libraries

## Managing Your Cluster

### Check Cluster Status

```bash
source ~/.aerospike-cloud/current_cluster.sh
source aeropsike-cloud/api-scripts/common.sh
acs_get_cluster_status "$ACS_CLUSTER_ID"
```

### List All Clusters

```bash
source aeropsike-cloud/api-scripts/common.sh
acs_list_clusters
```

### Refresh Token (after 8 hours)

```bash
cd aeropsike-cloud
./api-scripts/get-token.sh
```

## Troubleshooting

### Error: "Credentials not loaded properly"
- Check that CSV file is in the correct location
- Verify CSV file format (should have 3 columns)
- Ensure `credentials.conf` was created correctly

### Error: "Failed to create cluster" (HTTP 400)
- Check CIDR block is valid `/19` and not `10.129.0.0/19`
- Verify instance type is available in the selected region
- Ensure cluster name doesn't already exist

### Error: "Failed to create cluster" (HTTP 401)
- Token may have expired (8 hour lifetime)
- Re-run `./api-scripts/get-token.sh`
- Check credentials are correct

### Error: "Failed to create cluster" (HTTP 403)
- Check API key has necessary permissions
- Verify organization has available quota

### Cluster stuck in "provisioning"
- Normal provisioning takes 10-20 minutes
- The script checks every 60 seconds and shows progress
- You can safely interrupt and resume by re-running `./setup.sh`
- If longer than 30 minutes, check Aerospike Cloud console
- Contact Aerospike support if issue persists

### Script was interrupted during provisioning
- No problem! Just re-run `./setup.sh`
- The script will detect the existing cluster
- Check its current status
- Resume monitoring if still provisioning
- Complete setup once ready

## Next Steps

After cluster is provisioned:

1. **Set up VPC Peering** (if needed)
   ```bash
   # Coming soon
   ./api-scripts/02-vpc-peering.sh
   ```

2. **Deploy Client Instances** (if needed)
   ```bash
   # Coming soon
   ./client_setup.sh
   ```

3. **Connect and Test**
   - Use `asadm` or `aql` to connect
   - Run benchmarks
   - Monitor performance

## Additional Resources

- [Aerospike Cloud Documentation](https://docs.aerospike.com/cloud)
- [API Documentation](https://api.aerospike.com/docs)
- [Aerospike Tools](https://docs.aerospike.com/tools)

## Support

For issues or questions:
- Aerospike Cloud Console
- Aerospike Support Portal
- Aerospike Community Forums

