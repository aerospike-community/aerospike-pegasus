# Cluster Setup Progress Examples

## Example Output

### Initial Setup (New Cluster)

```
=====================================
Aerospike Cloud - Cluster Setup
=====================================

Setting up credentials directory at /Users/user/.aerospike-cloud...

Credentials config file not found. Creating from API key CSV file...
Found API key file: /Users/user/.aerospike-cloud/credentials/aerospike-cloud-apikey-XXX.csv
Credentials config file created successfully at /Users/user/.aerospike-cloud/credentials.conf

Acquiring authentication token...
Generating access token (auth.header) for API calls.
Token is valid for 8 hours.

✓ Authentication successful!
  Token saved to: /Users/user/.aerospike-cloud/auth.header
  Token is valid for 8 hours.

=====================================
Database Cluster Creation
=====================================

Checking if cluster 'Benchmark' already exists...

Creating new database cluster 'Benchmark'...
  Provider: aws
  Region: ap-south-1
  Instance Type: i4i.large
  Cluster Size: 3 nodes
  AZ Count: 2
  Data Storage: local-disk
  VPC CIDR: 10.128.0.0/19
  Namespace: test

API Response Code: 202
✓ Cluster creation request accepted!

✓ Cluster created with ID: e2e81cba-446e-4ff9-9b92-9a9992af44c6

=====================================
Provisioning Cluster
=====================================
This typically takes 10-20 minutes.
You can safely interrupt (Ctrl+C) and re-run setup.sh to resume.

⏳ Status: provisioning | Elapsed: 05:23 | Checks: 6 [/]
```

### Resuming After Interruption

```
=====================================
Aerospike Cloud - Cluster Setup
=====================================

Setting up credentials directory at /Users/user/.aerospike-cloud...

Acquiring authentication token...
Generating access token (auth.header) for API calls.
Token is valid for 8 hours.

✓ Authentication successful!
  Token saved to: /Users/user/.aerospike-cloud/auth.header
  Token is valid for 8 hours.

=====================================
Database Cluster Creation
=====================================

Checking if cluster 'Benchmark' already exists...
✓ Cluster already exists with ID: e2e81cba-446e-4ff9-9b92-9a9992af44c6
  Current status: provisioning

Cluster is still provisioning. Continuing to monitor...

=====================================
Provisioning Cluster
=====================================
This typically takes 10-20 minutes.
You can safely interrupt (Ctrl+C) and re-run setup.sh to resume.

⏳ Status: provisioning | Elapsed: 02:15 | Checks: 3 [-]
```

### Cluster Already Active

```
=====================================
Aerospike Cloud - Cluster Setup
=====================================

Setting up credentials directory at /Users/user/.aerospike-cloud...

Acquiring authentication token...
Generating access token (auth.header) for API calls.
Token is valid for 8 hours.

✓ Authentication successful!
  Token saved to: /Users/user/.aerospike-cloud/auth.header
  Token is valid for 8 hours.

=====================================
Database Cluster Creation
=====================================

Checking if cluster 'Benchmark' already exists...
✓ Cluster already exists with ID: e2e81cba-446e-4ff9-9b92-9a9992af44c6
  Current status: active

✓ Cluster is active and ready to use!

Connection Details:
  Hostname: benchmark-12345.aerospike.cloud
  TLS Name: benchmark-12345.aerospike.cloud
  Port: 4000
```

### Provisioning Complete

```
⏳ Status: provisioning | Elapsed: 18:42 | Checks: 19 [|]

=====================================
✓ Cluster status: active
  Total provisioning time: 18m 42s
=====================================

Connection Details:
  Hostname: benchmark-12345.aerospike.cloud
  TLS Name: benchmark-12345.aerospike.cloud
  Port: 4000

Cluster setup complete!
```

## Progress Indicator

The spinning indicator rotates through these characters:
- `[|]` - Vertical bar
- `[/]` - Forward slash  
- `[-]` - Horizontal bar
- `[\]` - Backslash

Each check happens every **60 seconds** (1 minute).

## Interrupting and Resuming

### To Interrupt
Press `Ctrl+C` at any time during provisioning.

### To Resume
Simply run the setup again:
```bash
cd aeropsike-cloud
./setup.sh
```

The script will:
1. ✅ Skip credential setup (already configured)
2. ✅ Acquire fresh auth token (in case old one expired)
3. ✅ Detect existing cluster by name
4. ✅ Check current status
5. ✅ Resume monitoring if still provisioning
6. ✅ Complete setup once active

## Cluster State Files

During provisioning, the cluster state is continuously updated:

**`~/.aerospike-cloud/current_cluster.sh`**
```bash
export ACS_CLUSTER_ID="e2e81cba-446e-4ff9-9b92-9a9992af44c6"
export ACS_CLUSTER_NAME="Benchmark"
export ACS_CLUSTER_STATUS="provisioning"  # Updates every check
```

Once provisioning completes:

**`~/.aerospike-cloud/{cluster-id}/cluster_config.sh`**
```bash
export ACS_CLUSTER_HOSTNAME="benchmark-12345.aerospike.cloud"
export ACS_CLUSTER_TLSNAME="benchmark-12345.aerospike.cloud"
export SERVICE_PORT=4000
```

## Benefits of Resumable Setup

1. **No lost time** - Interrupt and resume without starting over
2. **Flexible workflow** - Step away during long provisioning
3. **Error recovery** - Automatically handles temporary network issues
4. **State tracking** - Always know cluster status
5. **Multiple runs safe** - Running setup multiple times is idempotent

## Monitoring Cluster Status

You can check cluster status at any time:

```bash
source ~/.aerospike-cloud/current_cluster.sh
source aeropsike-cloud/api-scripts/common.sh
acs_get_cluster_status "$ACS_CLUSTER_ID"
```

Output: `provisioning`, `active`, `failed`, etc.

