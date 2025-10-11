# VPC Peering Setup Guide

## Overview

The VPC peering setup establishes private connectivity between your AWS client VPC and the Aerospike Cloud cluster VPC. This eliminates public internet exposure, reduces latency, and provides a secure connection.

## Architecture

```
┌─────────────────────────────────┐      ┌─────────────────────────────────┐
│  Client VPC (AWS)                │      │  Aerospike Cloud Cluster VPC    │
│  CIDR: 10.140.0.0/19            │◄────►│  CIDR: 10.131.0.0/19           │
│                                  │ VPC  │                                 │
│  ┌────────────────────────┐     │Peer  │  ┌────────────────────────┐    │
│  │  Client Instances      │     │      │  │  Aerospike Cluster     │    │
│  │  (c6i.4xlarge)         │────►│─────►│──│  (i4i.large x 2)       │    │
│  └────────────────────────┘     │      │  └────────────────────────┘    │
│                                  │      │                                 │
│  Route Tables Updated            │      │  Private Hosted Zone            │
│  Security Groups Configured      │      │  DNS Resolution Enabled         │
└─────────────────────────────────┘      └─────────────────────────────────┘
```

## Prerequisites

✅ **Before running VPC peering setup:**

1. **Cluster must be active**
   ```bash
   # Check cluster status
   source ~/.aerospike-cloud/current_cluster.sh
   echo $ACS_CLUSTER_STATUS  # Should be "active"
   ```

2. **Client must be provisioned**
   ```bash
   # Check client exists
   ls ~/.aerospike-cloud/client/client_config.sh
   ```

3. **AWS CLI configured**
   ```bash
   aws sts get-caller-identity
   ```

4. **No CIDR overlaps**
   - Client VPC CIDR must NOT overlap with:
     - Aerospike Cloud cluster CIDR (default: 10.131.0.0/19)
     - Aerospike internal services: 10.129.0.0/24

## Usage

### Automatic Setup (Recommended)

The complete setup process is automated:

```bash
cd aeropsike-cloud
./vpc_peering_setup.sh
```

### What Gets Automated

The script automatically:

1. ✅ Validates prerequisites
2. ✅ Gets AWS Account ID
3. ✅ Initiates VPC peering via Aerospike Cloud API
4. ✅ Waits for peering request status
5. ✅ Accepts peering connection in AWS
6. ✅ Waits for peering to become active
7. ✅ Configures route tables (all subnets)
8. ✅ Associates Private Hosted Zone for DNS
9. ✅ Configures security group rules
10. ✅ Tests DNS resolution and connectivity

### Resumable Execution

The script is fully resumable. If interrupted:

```bash
# State is saved to ~/.aerospike-cloud/vpc_peering_state.sh
# Re-run the script to resume
./vpc_peering_setup.sh
```

## Step-by-Step Process

### Phase 1: Validation

```
✓ Cluster is active: test-skr (17772951-c8ec-4b8c-a857-bc1e257cbdda)
✓ Client VPC found: vpc-0123456789abcdef0 (10.140.0.0/19)
✓ AWS CLI is available
✓ jq is available
✓ AWS Account ID: 123456789012
✓ Found route tables: rtb-xxx rtb-yyy
✓ No CIDR block overlaps detected
```

### Phase 2: Initiate Peering

```
ℹ️  Initiating VPC peering request...
VPC Details:
{
  "vpcId": "vpc-0123456789abcdef0",
  "cidrBlock": "10.140.0.0/19",
  "accountId": "123456789012",
  "region": "ap-south-1",
  "secureConnection": true
}
✓ VPC peering request initiated successfully
```

### Phase 3: Wait for Pending Acceptance

```
ℹ️  Waiting for peering status to become 'pending-acceptance'...
  Status: initiating-request (elapsed: 10s)
  Status: pending-acceptance (elapsed: 30s)
✓ Peering status is now: pending-acceptance
```

### Phase 4: Accept Peering

```
ℹ️  Accepting VPC peering connection...
✓ VPC peering connection accepted
ℹ️  Waiting for peering status to become 'active'...
✓ Peering status is now: active
```

### Phase 5: Configure Routes

```
ℹ️  Configuring route tables...
ℹ️  Checking route table: rtb-xxx
ℹ️  Creating route to 10.131.0.0/19 via pcx-xxx
✓ Route created in rtb-xxx
✓ Routes configured: 2 added, 0 already existed
```

### Phase 6: Configure DNS

```
ℹ️  Associating VPC with private hosted zone...
✓ VPC associated with hosted zone Z04089311NGVVH0FO3QGG
```

### Phase 7: Configure Security Groups

```
ℹ️  Configuring security group: sg-xxx
ℹ️  Adding outbound rule for Aerospike port 4000...
✓ Added outbound rule for port 4000
ℹ️  Adding outbound rule for Aerospike port 3000 (non-TLS, optional)...
ℹ️  Adding outbound rule for Prometheus port 9145 (optional)...
✓ Security groups configured
```

### Phase 8: Test Connectivity

```
ℹ️  Testing connectivity...
ℹ️  Cluster hostname: 17772951-c8ec-4b8c-a857-bc1e257cbdda.aerospike.internal
ℹ️  Waiting 30 seconds for DNS propagation...
ℹ️  Testing DNS resolution...
✓ DNS resolution successful!
Resolved IPs:
10.131.2.45
10.131.3.67
```

## Configuration Files

After successful setup:

```
~/.aerospike-cloud/
├── current_cluster.sh          # Cluster info
├── client/
│   └── client_config.sh        # Client VPC details
└── {cluster-id}/
    ├── cluster_config.sh       # Cluster connection details
    └── vpc_peering.sh          # Peering configuration ⬅️ NEW
```

### vpc_peering.sh Contents

```bash
export PEERING_ID="pcx-0123456789abcdef0"
export ZONE_ID="Z04089311NGVVH0FO3QGG"
export CLIENT_VPC_ID="vpc-0123456789abcdef0"
export CLIENT_VPC_CIDR="10.140.0.0/19"
export CLUSTER_CIDR="10.131.0.0/19"
```

## Security Group Rules Added

The script automatically adds the following **outbound** rules to client security groups:

| Port | Protocol | Destination | Purpose |
|------|----------|-------------|---------|
| 4000 | TCP | 10.131.0.0/19 | Aerospike TLS connections |
| 3000 | TCP | 10.131.0.0/19 | Aerospike non-TLS (optional) |
| 9145 | TCP | 10.131.0.0/19 | Prometheus metrics (optional) |

**Note:** No inbound rules are needed because security groups are stateful.

## Testing Connectivity

### From Your Local Machine

```bash
# Test DNS resolution
dig +short 17772951-c8ec-4b8c-a857-bc1e257cbdda.aerospike.internal

# Output should show private IPs like:
# 10.131.2.45
# 10.131.3.67
```

### From Client Instance

SSH to your client instance:

```bash
# Get client public IP
source ~/.aerospike-cloud/client/client_config.sh
ssh -i ~/.ssh/your-key.pem ubuntu@${CLIENT_PUBLIC_IPS}
```

Once on the client instance:

```bash
# Test DNS resolution
dig +short 17772951-c8ec-4b8c-a857-bc1e257cbdda.aerospike.internal

# Test port connectivity
nc -zv 10.131.2.45 4000

# Expected output:
# Connection to 10.131.2.45 4000 port [tcp/*] succeeded!
```

### Connect with AQL

From the client instance:

```bash
# Get TLS certificate from Aerospike Cloud Console first
# Then connect:
aql --tls-enable \
    --tls-name 17772951-c8ec-4b8c-a857-bc1e257cbdda \
    --tls-cafile /path/to/ca-cert.pem \
    -h 17772951-c8ec-4b8c-a857-bc1e257cbdda.aerospike.internal:4000 \
    -U admin \
    -P password
```

## Troubleshooting

### DNS Resolution Fails

**Symptom:**
```bash
dig +short {hostname}
# Returns nothing
```

**Solutions:**
1. Wait 5-10 minutes for DNS propagation
2. Check VPC DNS settings:
   ```bash
   aws ec2 describe-vpc-attribute \
     --vpc-id ${CLIENT_VPC_ID} \
     --attribute enableDnsSupport \
     --region ${CLIENT_AWS_REGION}
   
   aws ec2 describe-vpc-attribute \
     --vpc-id ${CLIENT_VPC_ID} \
     --attribute enableDnsHostnames \
     --region ${CLIENT_AWS_REGION}
   ```
3. Both should be `true`. If not:
   ```bash
   aws ec2 modify-vpc-attribute \
     --vpc-id ${CLIENT_VPC_ID} \
     --enable-dns-support
   
   aws ec2 modify-vpc-attribute \
     --vpc-id ${CLIENT_VPC_ID} \
     --enable-dns-hostnames
   ```

### Port Connection Fails

**Symptom:**
```bash
nc -zv 10.131.2.45 4000
# Connection refused or timeout
```

**Solutions:**
1. Verify route tables:
   ```bash
   aws ec2 describe-route-tables \
     --region ${CLIENT_AWS_REGION} \
     --filters "Name=vpc-id,Values=${CLIENT_VPC_ID}"
   ```
   Look for route to 10.131.0.0/19 via peering connection

2. Verify security group rules:
   ```bash
   aws ec2 describe-security-groups \
     --region ${CLIENT_AWS_REGION} \
     --group-ids ${CLIENT_SECURITY_GROUPS}
   ```
   Look for outbound rule allowing port 4000 to 10.131.0.0/19

3. Verify peering status:
   ```bash
   aws ec2 describe-vpc-peering-connections \
     --vpc-peering-connection-ids ${PEERING_ID} \
     --region ${CLIENT_AWS_REGION}
   ```
   Status should be "active"

### CIDR Overlap Error

**Symptom:**
```
ERROR: CIDR block 10.129.0.0/24 is reserved for Aerospike Cloud
```

**Solution:**
Change client VPC CIDR in `configure.sh`:
```bash
CLIENT_VPC_CIDR="10.141.0.0/19"  # Use different CIDR
```
Recreate client with new CIDR.

### Peering Already Exists

**Symptom:**
```
⚠️  WARNING: VPC peering already exists, skipping initiation
```

**This is normal** - the script detects existing peering and continues.

## Manual Cleanup

If automatic cleanup fails, manually delete:

### 1. Delete Peering Connection
```bash
aws ec2 delete-vpc-peering-connection \
  --vpc-peering-connection-id ${PEERING_ID} \
  --region ${CLIENT_AWS_REGION}
```

### 2. Delete Route Table Entries
```bash
# For each route table
aws ec2 delete-route \
  --route-table-id ${ROUTE_TABLE_ID} \
  --destination-cidr-block 10.131.0.0/19 \
  --region ${CLIENT_AWS_REGION}
```

### 3. Disassociate Hosted Zone
```bash
aws route53 disassociate-vpc-from-hosted-zone \
  --hosted-zone-id ${ZONE_ID} \
  --vpc VPCRegion=${CLIENT_AWS_REGION},VPCId=${CLIENT_VPC_ID}
```

## Best Practices

### 1. Run After Both Cluster and Client Are Ready
```bash
# Wrong order:
./vpc_peering_setup.sh  # Cluster not active yet ❌

# Correct order:
./setup.sh              # Wait for completion
./vpc_peering_setup.sh  # Then run peering ✅
```

### 2. Test Connectivity Before Deploying Workloads
Always verify DNS and port connectivity before running benchmarks.

### 3. Document Your Configuration
Save important IDs:
```bash
source ~/.aerospike-cloud/${ACS_CLUSTER_ID}/vpc_peering.sh
echo "Peering ID: $PEERING_ID"
echo "Zone ID: $ZONE_ID"
```

### 4. Monitor Peering Status
Check peering status periodically:
```bash
aws ec2 describe-vpc-peering-connections \
  --vpc-peering-connection-ids ${PEERING_ID} \
  --query 'VpcPeeringConnections[0].Status.Code' \
  --output text
```

## API Endpoints Used

The script uses the following Aerospike Cloud API endpoints:

| Endpoint | Method | Purpose |
|----------|--------|---------|
| `/v2/databases/{id}/vpc-peerings` | POST | Initiate peering |
| `/v2/databases/{id}/vpc-peerings` | GET | Check peering status |
| `/v2/databases/{id}/vpc-peerings/{peering-id}` | DELETE | Delete peering |

## Related Documentation

- [Aerospike Cloud VPC Peering Docs](https://aerospike.com/docs/cloud/configure-aws-vpc-peering)
- [AWS VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/what-is-vpc-peering.html)
- [AWS Security Groups](https://docs.aws.amazon.com/vpc/latest/userguide/security-group-rules.html)
- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Complete setup process
- [CLIENT_SETUP.md](CLIENT_SETUP.md) - Client provisioning
- [PARALLEL_SETUP.md](PARALLEL_SETUP.md) - Parallel execution details

