# State Management & Validation Guide

## Overview

The Aerospike Cloud setup includes comprehensive state management with real-time validation against actual resources (Aerospike Cloud API, AWS CLI, and aerolab). This ensures the setup can detect manual changes and always reflects reality.

## State Validation Process

Every time you run `./setup.sh`, it validates the state by:

### 1. **Cluster Validation** (Aerospike Cloud API)
```bash
# Checks Aerospike Cloud API directly
acs_get_cluster_status "${ACS_CLUSTER_ID}"

# What gets validated:
- Cluster exists in API
- Cluster status (provisioning/active/failed)
- Cluster ID matches configuration
```

**Possible outcomes:**
- ✅ **Cluster active** → Updates state to "active"
- ⏳ **Cluster provisioning** → Maintains "provisioning" state
- ⚠️ **Cluster not found** → Resets to "pending" state
- ❌ **Cluster failed** → Reports error, requires manual intervention

### 2. **Client Validation** (aerolab)
```bash
# Checks aerolab for client existence
aerolab client list -j | jq ".[] | select(.ClientName == \"${CLIENT_NAME}\")"

# What gets validated:
- Client exists in aerolab
- Client instances are running
- Client VPC matches configuration
```

**Possible outcomes:**
- ✅ **Client found** → Maintains "complete" state
- ⚠️ **Client not found** → Resets to "pending", removes config files
- 🔄 **Client partial** → Attempts to resume

### 3. **VPC Peering Validation** (Aerospike Cloud API + AWS CLI)
```bash
# Step 1: Check Aerospike Cloud API
acs_get_vpc_peering_json "${ACS_CLUSTER_ID}"

# Step 2: Validate in AWS
aws ec2 describe-vpc-peering-connections \
    --vpc-peering-connection-ids "${PEERING_ID}"

# What gets validated:
- Peering exists in Aerospike Cloud
- Peering status is "active"
- Peering exists in AWS
- AWS peering status is "active"
```

**Possible outcomes:**
- ✅ **Peering active (both sides)** → Maintains "complete" state
- ⚠️ **Peering not found in API** → Resets to "pending"
- ⚠️ **Peering not found in AWS** → Resets to "pending"
- ⏳ **Peering pending-acceptance** → Resumes acceptance flow

## State File

**Location:** `~/.aerospike-cloud/setup_state.sh`

```bash
export CLUSTER_SETUP_PHASE="active"      # pending, provisioning, active, complete
export CLIENT_SETUP_PHASE="complete"     # pending, running, complete
export VPC_PEERING_PHASE="complete"      # pending, configuring, complete
```

## State Transitions

### Cluster State Flow
```
pending ──────> provisioning ──────> active ──────> complete
   │                 │                  │               │
   └─[Create]────────┘                  │               │
                   └──[Wait 15-20min]───┘               │
                                      └─[Finalize]──────┘
```

### Client State Flow
```
pending ──────> running ──────> complete
   │               │                │
   └──[Provision]──┘                │
                └──[Extract VPC]────┘
```

### VPC Peering State Flow
```
pending ──────> configuring ──────> complete
   │                  │                 │
   └──[Initiate]──────┘                 │
                   └──[Configure]───────┘
```

## Example Validation Scenarios

### Scenario 1: Everything Running Normally

```bash
$ ./setup.sh

Validating state against actual resources...

  Checking cluster status in Aerospike Cloud API...
  ✓ Cluster is active: test-skr
  ✓ Client exists: Perseus_test-skr
  Checking VPC peering in Aerospike Cloud API...
  ✓ VPC peering is active: pcx-xxx
  Checking VPC peering in AWS...
  ✓ VPC peering confirmed active in AWS

Current State:
  Cluster:     active
  Client:      complete
  VPC Peering: complete

✓ SETUP COMPLETE!
```

### Scenario 2: Cluster Deleted from Console

```bash
$ ./setup.sh

Validating state against actual resources...

  Checking cluster status in Aerospike Cloud API...
  ⚠️  Cluster not found in API, resetting state
  ℹ️  No cluster configuration found
  ℹ️  Client not yet provisioned
  ℹ️  VPC peering not yet configured

Current State:
  Cluster:     pending
  Client:      pending
  VPC Peering: pending

# Setup will start fresh from Phase 1
```

### Scenario 3: VPC Peering Deleted from AWS

```bash
$ ./setup.sh

Validating state against actual resources...

  ✓ Cluster is active: test-skr
  ✓ Client exists: Perseus_test-skr
  Checking VPC peering in Aerospike Cloud API...
  ✓ VPC peering is active: pcx-xxx
  Checking VPC peering in AWS...
  ⚠️  VPC peering not found in AWS, may need reconfiguration

Current State:
  Cluster:     active
  Client:      complete
  VPC Peering: pending  # ← Reset automatically

# Will offer to reconfigure VPC peering
```

### Scenario 4: Cluster Still Provisioning

```bash
$ ./setup.sh

Validating state against actual resources...

  Checking cluster status in Aerospike Cloud API...
  ⏳ Cluster is still provisioning: test-skr
  ✓ Client exists: Perseus_test-skr
  ℹ️  VPC peering not yet configured

Current State:
  Cluster:     provisioning
  Client:      complete
  VPC Peering: pending

# Will resume monitoring cluster provisioning
```

## Manual State Reset

### Reset Everything
```bash
rm ~/.aerospike-cloud/setup_state.sh
./setup.sh
```

### Reset Only VPC Peering
```bash
# Edit state file
nano ~/.aerospike-cloud/setup_state.sh
# Change: VPC_PEERING_PHASE="pending"

./setup.sh
```

### Reset Only Client
```bash
rm -rf ~/.aerospike-cloud/client/
# Edit state file
nano ~/.aerospike-cloud/setup_state.sh
# Change: CLIENT_SETUP_PHASE="pending"

./setup.sh
```

## State Recovery Scenarios

### 1. Interrupted During Client Setup

**State file shows:**
```bash
CLUSTER_SETUP_PHASE="provisioning"
CLIENT_SETUP_PHASE="running"  # ← Interrupted
```

**What happens:**
1. Validates cluster (still provisioning)
2. Validates client (not found in aerolab)
3. Resets client to "pending"
4. Continues cluster monitoring
5. Provisions client once cluster is ready

### 2. Manual Cluster Deletion

**State file shows:**
```bash
CLUSTER_SETUP_PHASE="active"
CLIENT_SETUP_PHASE="complete"
VPC_PEERING_PHASE="complete"
```

**What happens:**
1. API check fails to find cluster
2. Resets cluster to "pending"
3. Clears current_cluster.sh
4. Starts fresh cluster creation

### 3. Manual VPC Peering Changes

**State file shows:**
```bash
CLUSTER_SETUP_PHASE="active"
CLIENT_SETUP_PHASE="complete"
VPC_PEERING_PHASE="complete"
```

**AWS shows:** Peering deleted or in wrong state

**What happens:**
1. API check finds peering in Aerospike Cloud
2. AWS check fails
3. Resets VPC peering to "pending"
4. Offers to reconfigure

## Best Practices

### 1. Always Use setup.sh for Resumption

```bash
# ✅ Good
./setup.sh  # Validates state, resumes correctly

# ❌ Bad
./cluster_setup.sh  # Bypasses state validation
```

### 2. Check State Before Manual Operations

```bash
# View current state
cat ~/.aerospike-cloud/setup_state.sh

# Validate state
./setup.sh  # Will validate and report
```

### 3. Handle Interruptions Gracefully

```bash
# Start setup
./setup.sh

# Interrupt with Ctrl+C at any time
^C

# Resume (validates state first)
./setup.sh
```

### 4. Use Destroy Scripts for Cleanup

```bash
# ✅ Good - proper cleanup with state management
./destroy.sh --yes

# ❌ Bad - manual deletion leaves orphaned state
# (Delete from console/AWS manually)
```

## State Files Location

```
~/.aerospike-cloud/
├── setup_state.sh                      # Main state tracking
├── current_cluster.sh                  # Cluster details
├── client/
│   └── client_config.sh                # Client details
├── {cluster-id}/
│   ├── cluster_config.sh               # Connection details
│   └── vpc_peering.sh                  # Peering details
└── vpc_peering_state.sh                # Temp peering state (during setup)
```

## Troubleshooting State Issues

### State File Corrupted

**Symptom:** Script errors on startup

**Solution:**
```bash
# Backup current state
cp ~/.aerospike-cloud/setup_state.sh ~/setup_state_backup.sh

# Delete and recreate
rm ~/.aerospike-cloud/setup_state.sh
./setup.sh  # Validates everything from scratch
```

### State Out of Sync

**Symptom:** State says "complete" but resources don't exist

**Solution:**
```bash
# Run validation
./setup.sh

# The validation will detect mismatches and reset states
```

### Force Fresh Start

**Symptom:** Want to completely start over

**Solution:**
```bash
# Destroy everything
./destroy.sh --yes

# Remove all state
rm -rf ~/.aerospike-cloud/

# Start fresh
./setup.sh
```

## Validation Output Explained

### ✓ Green checkmark
Resource exists and is in expected state

### ⚠️ Yellow warning
Resource state mismatch, will attempt recovery

### ⏳ Hourglass
Resource is in transitional state (provisioning, configuring)

### ℹ️ Info
Resource not yet created (normal for early phases)

### ❌ Red X
Error condition requiring manual intervention

## Related Documentation

- [PARALLEL_SETUP.md](PARALLEL_SETUP.md) - Complete setup flow
- [VPC_PEERING_GUIDE.md](VPC_PEERING_GUIDE.md) - VPC peering details
- [CLIENT_SETUP.md](CLIENT_SETUP.md) - Client provisioning
- [README.md](README.md) - Project overview

