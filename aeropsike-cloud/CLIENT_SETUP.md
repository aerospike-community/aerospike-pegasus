# Aerospike Cloud - Client Setup Guide

## Overview

The client setup provisions AWS EC2 instances using `aerolab` to run workloads against your Aerospike Cloud cluster. The client instances are provisioned in a **separate VPC** to enable VPC peering with the Aerospike Cloud cluster VPC.

## Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│  Aerospike Cloud Cluster VPC    │      │    Client VPC (AWS)             │
│  (Managed by Aerospike)          │      │    (Managed by aerolab)         │
│                                  │      │                                 │
│  CIDR: 10.131.0.0/19            │◄────►│  CIDR: 10.140.0.0/19           │
│                                  │ VPC  │                                 │
│  ┌────────────────────────┐     │Peer  │  ┌────────────────────────┐    │
│  │  Aerospike Cluster     │     │      │  │  Perseus Client        │    │
│  │  (i4i.large x 2)       │     │      │  │  (c6i.4xlarge)         │    │
│  └────────────────────────┘     │      │  └────────────────────────┘    │
└─────────────────────────────────┘      └─────────────────────────────────┘
```

## Prerequisites

1. **Aerospike Cloud cluster must be active**
   - Run `./setup.sh` first to create the cluster
   - Wait for cluster to reach "active" status

2. **aerolab installed and configured**
   ```bash
   # Install aerolab
   curl -sSL https://install.aerolab.aerospike.com | bash
   
   # Configure AWS credentials
   export AWS_ACCESS_KEY_ID="your-access-key"
   export AWS_SECRET_ACCESS_KEY="your-secret-key"
   ```

3. **AWS CLI installed** (for extracting VPC details)
   ```bash
   # macOS
   brew install awscli
   
   # Linux
   pip install awscli
   ```

## Configuration

Edit `configure.sh` to customize client settings:

```bash
# Client Instance Config
CLIENT_NAME="Perseus_${ACS_CLUSTER_NAME}"
CLIENT_INSTANCE_TYPE="c6i.4xlarge"      # Instance type
CLIENT_NUMBER_OF_NODES=1                 # Number of client instances
CLIENT_AWS_REGION="${CLOUD_REGION}"      # Same region as cluster
CLIENT_AWS_EXPIRE="2h"                   # Auto-expire time
CLIENT_VPC_CIDR="10.140.0.0/19"         # VPC CIDR (must not overlap with cluster)
```

## Usage

### Setup Client

**Method 1: As part of full setup**
```bash
./setup.sh
# This will:
# 1. Create/check cluster
# 2. Create client in new VPC
# 3. Extract and save all details
```

**Method 2: Standalone client setup**
```bash
./client_setup.sh
# Requires cluster to exist first
```

**Method 3: Skip Perseus build**
```bash
./client_setup.sh --skip-perseus
# Only provisions client, skips workload build
```

### What Gets Created

1. **AWS Resources** (via aerolab):
   - New VPC with CIDR `10.140.0.0/19`
   - Public and private subnets
   - Internet Gateway
   - Route tables
   - Security groups
   - EC2 instances (client nodes)

2. **Tracking Files**:
   ```
   ~/.aerospike-cloud/
   └── client/
       ├── client_config.sh    # Shell environment variables
       └── client_info.json    # Full client details (JSON)
   ```

### Tracked Information

The setup automatically extracts and saves:

**Instance Details:**
- Instance IDs
- Public IP addresses
- Private IP addresses
- Instance type
- Region

**Network Details:**
- VPC ID
- VPC CIDR block
- Subnet IDs
- Security Group IDs

**Example `client_config.sh`:**
```bash
# Cluster Association
export ACS_CLUSTER_ID="7cf2313d-de1b-4ee5-8ef1-61030a855cb4"
export ACS_CLUSTER_NAME="test-skr"

# Client Basic Info
export CLIENT_NAME="Perseus_test-skr"
export CLIENT_NUMBER_OF_NODES="1"
export CLIENT_INSTANCE_TYPE="c6i.4xlarge"
export CLIENT_AWS_REGION="ap-south-1"

# AWS Instance Details
export CLIENT_INSTANCE_IDS="i-0a1b2c3d4e5f6g7h8"
export CLIENT_PRIVATE_IPS="10.140.1.10"
export CLIENT_PUBLIC_IPS="13.235.123.45"

# AWS Network Details
export CLIENT_VPC_ID="vpc-0123456789abcdef0"
export CLIENT_VPC_CIDR="10.140.0.0/19"
export CLIENT_SUBNET_IDS="subnet-abc123,subnet-def456"
export CLIENT_SECURITY_GROUPS="sg-0123456789abcdef0"
```

## Accessing Client Details

### Load configuration in scripts:
```bash
source ~/.aerospike-cloud/client/client_config.sh
echo "Client VPC: ${CLIENT_VPC_ID}"
echo "Client IPs: ${CLIENT_PUBLIC_IPS}"
```

### View JSON details:
```bash
cat ~/.aerospike-cloud/client/client_info.json | jq '.'
```

### SSH to client:
```bash
source ~/.aerospike-cloud/client/client_config.sh
ssh -i ~/.ssh/your-key.pem ubuntu@${CLIENT_PUBLIC_IPS}
```

## Next Steps

After client setup, you can:

1. **Set up VPC Peering** (to be implemented)
   ```bash
   ./vpc_peering_setup.sh
   ```

2. **Build Perseus Workload**
   ```bash
   ./client/buildPerseus.sh
   ```

3. **Run Workload**
   ```bash
   ./client/runPerseus.sh
   ```

## Destroy Client

```bash
# Destroy just the client
./client_destroy.sh

# Or destroy everything (client + cluster)
./destroy.sh
```

**What gets destroyed:**
- All EC2 instances
- VPC and associated networking (aerolab handles cleanup)
- Tracking files in `~/.aerospike-cloud/client/`

## Troubleshooting

### Client creation fails

1. **Check aerolab installation:**
   ```bash
   aerolab version
   ```

2. **Check AWS credentials:**
   ```bash
   aws sts get-caller-identity
   ```

3. **Check AWS quotas:**
   - Ensure you have available VPC quota
   - Ensure you have available EC2 instance quota for the instance type

### VPC CIDR conflicts

If you get CIDR conflicts, update `CLIENT_VPC_CIDR` in `configure.sh`:
```bash
CLIENT_VPC_CIDR="10.141.0.0/19"  # Use a different CIDR
```

### Cannot extract VPC details

If AWS CLI fails to extract details:
```bash
# Verify AWS CLI is configured
aws configure list

# Manually check instance details
aws ec2 describe-instances --region ap-south-1 \
  --filters "Name=tag:Name,Values=Perseus_*"
```

### Client already exists

The script is idempotent - if a client with the same name exists, it will:
1. Skip creation
2. Extract and update tracking information
3. Continue with Perseus build (if not skipped)

## Configuration Reference

### Instance Types

Recommended client instance types:
- `c6i.4xlarge` - 16 vCPUs, 32 GB RAM (default)
- `c6i.8xlarge` - 32 vCPUs, 64 GB RAM (higher load)
- `c6i.16xlarge` - 64 vCPUs, 128 GB RAM (maximum load)

Choose instances with:
- High CPU count for concurrent operations
- At least 32 GB RAM
- Network-optimized (c6i family)
- **No NVMe** (client doesn't need local storage)

### Expiry Settings

Control instance lifetime:
- `0` - Never expire
- `2h` - Expire after 2 hours
- `24h` - Expire after 24 hours
- `7d` - Expire after 7 days

## Advanced Usage

### Multiple Clients

To provision multiple client instances:

1. Update `configure.sh`:
   ```bash
   CLIENT_NUMBER_OF_NODES=3  # Create 3 clients
   ```

2. Run setup:
   ```bash
   ./client_setup.sh
   ```

All instances will be in the same VPC with the same configuration.

### Custom VPC Configuration

If you need specific VPC settings, you can:

1. Pre-create VPC with AWS CLI
2. Configure aerolab to use existing VPC
3. Update tracking manually

(Refer to aerolab documentation for advanced VPC options)

## Related Documentation

- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Cluster setup
- [README.md](README.md) - Project overview
- [CHANGELOG.md](CHANGELOG.md) - Version history

