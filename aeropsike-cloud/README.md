# Aerospike Cloud Setup

Automated setup for Aerospike Cloud clusters with client instances and Perseus benchmarking tool.

## Prerequisites

- **Aerospike Cloud API Key**: Download from [Aerospike Cloud Console](https://cloud.aerospike.com)
- **aerolab**: Install from [Aerospike Labs](https://github.com/aerospike/aerolab)
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

# TLS Configuration
ENABLE_TLS="false"                   # false = port 3000, true = port 4000

# Namespace
NAMESPACE_NAME="test"
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
- Build and run Perseus benchmarking tool

**Note**: Full setup takes 15-20 minutes.

### 4. Individual Components

Run components separately if needed:

```bash
# Just create the cluster
./cluster_setup.sh

# Setup VPC peering (after cluster is ready)
./vpc_peering_setup.sh

# Setup client and run Perseus
cd ../client
./setup.sh
./buildPerseus.sh
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

Destroy all resources:
```bash
cd aeropsike-cloud
./destroy.sh
```

This removes:
- Aerospike Cloud cluster
- Client instances
- Grafana instance
- VPC peering connections

## Troubleshooting

### Perseus won't connect
- Check VPC peering: `nc -zv <cluster-ip> 4000`
- Verify DNS resolution: `dig +short <cluster-hostname>`
- Check TLS certificate is present (if using port 4000)

### Cluster not found
```bash
# Re-authenticate
./api-scripts/get-token.sh

# List clusters
curl -s "${REST_API_URI}" -H "@${ACS_AUTH_HEADER}" | jq '.databases[].name'
```

### Client connectivity issues
- Ensure VPC peering is active in Aerospike Cloud console
- Check security groups allow traffic from client VPC CIDR

## Files Overview

```
aeropsike-cloud/
├── setup.sh                    # Complete setup workflow
├── configure.sh                # Main configuration file
├── cluster_setup.sh            # Create Aerospike Cloud cluster
├── vpc_peering_setup.sh        # Setup VPC peering
├── destroy.sh                  # Clean up all resources
└── api-scripts/               # API helper scripts
```

## Support

For issues or questions:
- [Aerospike Cloud Documentation](https://docs.aerospike.com/cloud)
- [Aerospike Community Forums](https://discuss.aerospike.com)

