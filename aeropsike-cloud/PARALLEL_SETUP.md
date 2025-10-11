# Parallel Setup with State Management

## Overview

The Aerospike Cloud setup has been optimized to run **cluster provisioning** and **client setup** in parallel, significantly reducing total setup time. The system includes robust state management that allows you to interrupt and resume at any point.

## Setup Flow

```
┌─────────────────────────────────────────────────────────────┐
│  Phase 1: Start Cluster Setup                               │
│  - Authenticate with API                                     │
│  - Create cluster (or detect existing)                       │
│  - Wait for cluster ID registration                          │
│  State: CLUSTER=provisioning, CLIENT=pending                 │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├── Parallel Execution ──┐
                       │                         │
         ┌─────────────▼────────────┐   ┌────────▼────────────┐
         │  Phase 2: Client Setup    │   │ Phase 3: Monitor    │
         │  (Runs in parallel)       │   │ Cluster Status      │
         │  - Provision EC2          │   │ (Background)        │
         │  - Create VPC             │   │ - Check every 60s   │
         │  - Extract details        │   │ - Update state      │
         │  - Save tracking          │   │                     │
         │  State: CLIENT=running    │   │                     │
         └─────────────┬─────────────┘   └────────┬────────────┘
                       │                          │
                       └──────────┬───────────────┘
                                  │
                       ┌──────────▼─────────────────┐
                       │ Both Complete              │
                       │ CLUSTER=active             │
                       │ CLIENT=complete            │
                       └────────────────────────────┘
```

## State Management

### State File
Location: `~/.aerospike-cloud/setup_state.sh`

```bash
export CLUSTER_SETUP_PHASE="provisioning"  # pending, provisioning, active, complete
export CLIENT_SETUP_PHASE="running"        # pending, running, complete
export VPC_PEERING_PHASE="pending"         # pending, configuring, complete
```

### Phase Tracking

| Phase | Description | Duration | Can Interrupt? |
|-------|-------------|----------|----------------|
| **Phase 1** | Start cluster setup | ~30 seconds | ✅ Yes |
| **Phase 2** | Client setup (parallel) | ~5-10 minutes | ✅ Yes |
| **Phase 3** | Monitor cluster provisioning | ~10-20 minutes | ✅ Yes |
| **Phase 4** | Client setup (if not done) | ~5-10 minutes | ✅ Yes |
| **Phase 5** | VPC peering setup (optional) | ~2-5 minutes | ✅ Yes |
| **Phase 6** | Complete | Instant | N/A |

### Resumable Execution

The setup is **fully resumable** at any point:

```bash
# Start setup
./setup.sh

# Interrupt (Ctrl+C) at any time
^C

# Resume from where you left off
./setup.sh
```

**What happens on resume:**
1. Loads state from `~/.aerospike-cloud/setup_state.sh`
2. Skips completed phases
3. Continues from the current phase
4. Preserves all progress

## Time Savings

### Sequential Setup (Old)
```
Cluster Creation: 30s
Cluster Provisioning: 15-20 minutes ⏱️
Client Setup: 5-10 minutes ⏱️
──────────────────────────────────
Total: 20-30 minutes
```

### Parallel Setup (New)
```
Cluster Creation: 30s
┌─────────────────────┬──────────────────┐
│ Cluster Provisioning│  Client Setup    │
│ 15-20 minutes ⏱️    │  5-10 minutes ⏱️ │
└─────────────────────┴──────────────────┘
──────────────────────────────────
Total: 15-20 minutes (40% faster!)
```

## How It Works

### 1. Cluster Setup with Early Exit

```bash
# In cluster_setup.sh
if [[ "$SKIP_PROVISION_WAIT" == "true" ]]; then
    echo "✓ Cluster setup initiated successfully!"
    echo "  Parallel client setup will begin now..."
    exit 0  # Return control to setup.sh
fi
```

When `SKIP_PROVISION_WAIT=true`:
- Creates the cluster
- Waits for cluster ID
- Returns immediately (doesn't wait for provisioning)
- setup.sh proceeds to Phase 2

### 2. Parallel Client Setup

```bash
# Phase 2: Start client setup in parallel
if [[ "$CLUSTER_SETUP_PHASE" == "provisioning" ]] && [[ "$CLIENT_SETUP_PHASE" == "pending" ]]; then
    CLIENT_SETUP_PHASE="running"
    save_state
    
    # Run client setup
    . $PREFIX/client_setup.sh
    
    CLIENT_SETUP_PHASE="complete"
    save_state
fi
```

Client setup runs while cluster provisions:
- Provisions EC2 instances via aerolab
- Creates separate VPC
- Extracts VPC details
- Saves tracking files

### 3. Cluster Status Monitoring

```bash
# Phase 3: Wait for cluster to become active
while true; do
    CURRENT_STATUS=$(acs_get_cluster_status "${ACS_CLUSTER_ID}")
    
    if [[ "$CURRENT_STATUS" == "active" ]]; then
        break
    fi
    
    sleep 60  # Check every minute
done
```

After client setup completes:
- Continues monitoring cluster status
- Updates state every minute
- Shows progress with spinner

## State Transitions

```
CLUSTER_SETUP_PHASE:
  pending ──────> provisioning ──────> active ──────> complete
     │                 │                  │               │
     └─────[Create]────┘                  │               │
                     └────[Wait Active]───┘               │
                                        └─[Client Done]───┘

CLIENT_SETUP_PHASE:
  pending ──────> running ──────> complete
     │               │                │
     └──[Start]──────┘                │
                  └──[Finish]─────────┘
```

## Examples

### Example 1: Fresh Setup

```bash
$ ./setup.sh

============================================
Aerospike Cloud - Complete Setup
============================================

Current State:
  Cluster: pending
  Client: pending

============================================
Phase 1: Starting Cluster Setup
============================================
...
✓ Cluster setup initiated successfully!
  Parallel client setup will begin now...

============================================
Phase 2: Starting Client Setup (Parallel)
============================================
While the cluster provisions, we'll set up the client...
...
✓ Client setup complete!

============================================
Phase 3: Waiting for Cluster to Become Active
============================================
⏳ Status: provisioning | Elapsed: 05:23 | Checks: 6 [|]
```

### Example 2: Resume After Interrupt

```bash
# First run (interrupted during client setup)
$ ./setup.sh
^C  # Interrupted

# Resume
$ ./setup.sh

============================================
Aerospike Cloud - Complete Setup
============================================

Current State:
  Cluster: provisioning     # ← Loaded from state
  Client: running          # ← Loaded from state

# Continues client setup from where it left off
...
```

### Example 3: Already Exists

```bash
$ ./setup.sh

============================================
Current State:
  Cluster: provisioning     # Existing cluster detected
  Client: pending

============================================
Phase 2: Starting Client Setup (Parallel)
============================================
# Skips cluster creation, goes straight to client setup
```

## State Files

### Setup State
`~/.aerospike-cloud/setup_state.sh`
```bash
export CLUSTER_SETUP_PHASE="provisioning"
export CLIENT_SETUP_PHASE="complete"
```

### Cluster State
`~/.aerospike-cloud/current_cluster.sh`
```bash
export ACS_CLUSTER_ID="7cf2313d-de1b-4ee5-8ef1-61030a855cb4"
export ACS_CLUSTER_NAME="test-skr"
export ACS_CLUSTER_STATUS="provisioning"
```

### Client State
`~/.aerospike-cloud/client/client_config.sh`
```bash
export CLIENT_NAME="Perseus_test-skr"
export CLIENT_VPC_ID="vpc-0123456789abcdef0"
export CLIENT_INSTANCE_IDS="i-0a1b2c3d4e5f6g7h8"
# ... and more
```

## Manual Phase Control

### Run Only Cluster Setup
```bash
./cluster_setup.sh
```

### Run Only Client Setup
```bash
./client_setup.sh
```

### Reset State (Start Fresh)
```bash
rm ~/.aerospike-cloud/setup_state.sh
./setup.sh
```

## Error Handling

### Client Setup Fails
- Cluster continues provisioning
- State saved: `CLIENT_SETUP_PHASE=pending`
- Re-run `./setup.sh` to retry client setup
- Cluster provisioning unaffected

### Cluster Creation Fails
- Client setup doesn't start
- Fix the issue and re-run
- State management ensures no duplicate clusters

### Network Interruption
- State saved every step
- Re-run `./setup.sh`
- Resumes from last successful state

## Best Practices

### 1. Let It Run
```bash
# Start and let it complete
./setup.sh

# Total time: ~15-20 minutes
# Don't interrupt unless necessary
```

### 2. Check Progress
```bash
# Terminal 1: Run setup
./setup.sh

# Terminal 2: Monitor (optional)
watch -n 30 'source ~/.aerospike-cloud/setup_state.sh && echo "Cluster: $CLUSTER_SETUP_PHASE, Client: $CLIENT_SETUP_PHASE"'
```

### 3. Clean Shutdown
```bash
# Always use Ctrl+C (SIGINT)
# Avoid kill -9 (SIGKILL)
^C
```

### 4. Verify State
```bash
# Check current state
cat ~/.aerospike-cloud/setup_state.sh

# Check cluster
source ~/.aerospike-cloud/current_cluster.sh
echo "Cluster: $ACS_CLUSTER_NAME ($ACS_CLUSTER_STATUS)"

# Check client
source ~/.aerospike-cloud/client/client_config.sh
echo "Client VPC: $CLIENT_VPC_ID"
```

## Troubleshooting

### Setup hangs in Phase 2
**Cause:** aerolab or AWS issues  
**Fix:** Check aerolab logs, AWS credentials
```bash
aerolab client list
aws sts get-caller-identity
```

### State file corrupted
**Cause:** Manual edit or disk error  
**Fix:** Delete and restart
```bash
rm ~/.aerospike-cloud/setup_state.sh
./setup.sh
```

### Client setup skips
**Cause:** State shows client=complete  
**Fix:** Force re-run
```bash
rm -rf ~/.aerospike-cloud/client/
rm ~/.aerospike-cloud/setup_state.sh
./setup.sh
```

## Related Documentation

- [SETUP_GUIDE.md](SETUP_GUIDE.md) - Complete setup guide
- [CLIENT_SETUP.md](CLIENT_SETUP.md) - Client provisioning details
- [README.md](README.md) - Project overview

