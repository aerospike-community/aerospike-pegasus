#!/bin/bash

set -e

# Default values
SSH_USERNAME=$(whoami)
CLUSTER_NAME="asd"
CLIENT_CLUSTER_NAME="lgs"
NAMESPACE="test"
CLIENT_COUNT=1
THREAD_COUNT=16
WORKLOAD_TYPE=hydrate
TOTAL_KEYS=500000001
START_KEY=0
TOTAL_TPS=500000
BIN_SIZE=1000
COMPRESSION_RATIO=1
READ_PERCENTAGE=50
EXPIRATION_TIME=0
TIMEOUT=86400
GENDERS_FILE="/etc/genders"
BATCH_SIZE=1
PETNAME=$(petname)  # Default petname generated using petname binary

# Gaussian Workload
STD_DEVIATION=3

show_help() {
cat << EOF
Usage: ${0##*/} [options]

This script configures a cluster and runs a workload

    --help                        display this help and exit
    --ssh-user NAME               set the username for ssh (default: $SSH_USERNAME)
    --cluster-name NAME           set the cluster name (default: $CLUSTER_NAME)
    --client-cluster-name NAME    Set the client cluster name (default: $CLIENT_CLUSTER_NAME)
    --namespace NAME              set the cluster namespace (default: $NAMESPACE)
    --genders-file PATH           path to genders file (default: $GENDERS_FILE)
    --client-count NUM            set the number of concurrent workload sessions on each client machine (default: $CLIENT_COUNT)
    --thread-count NUM            set the number of concurrent workload threads (default: $THREAD_COUNT)
    --workload-type TYPE          set the workload type to hydrate, workload, gaussian, or focus (default: $WORKLOAD_TYPE})
    --total-tps NUM               the number of transactions per second to deliver to the server (default: $TOTAL_TPS)
    --total-keys NUM              the number of keys to use for this test (default: $TOTAL_KEYS)
    --start-key NUM               the start key to use for this test (default: $START_KEY)
    --bin-size NUM                the size of the bin to insert (default: $BIN_SIZE)
    --compression-ratio NUM       the compression ratio to simulate (default: $COMPRESSION_RATIO)
    --read-percentage NUM         the percentage of the workload to be reads (default: ${READ_PERCENTAGE})
    --expiration-time NUM         the expiration time for the workload (default: $EXPIRATION_TIME)
    --timeout NUM                 number of seconds to run asbench (default: $TIMEOUT)
    --async                       use asynchronous I/O
    --tls                         use TLS for client connections
    --numa-node NUM               pin the workload to a specific NUMA node
    --batch-size NUM              set the batch size for operations (default: $BATCH_SIZE)
    --petname NAME               set a custom petname for this run (default: auto-generated)

    Gaussian Workload
    --standard-deviation          standard deviation to use for workload (default: $STD_DEVIATION)

    Workload
    --hot-key                     simulate a hot key
EOF
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help) show_help; exit 0 ;;
        --ssh-user) SSH_USERNAME="$2"; shift ;;
        --cluster-name) CLUSTER_NAME="$2"; shift ;;
        --client-cluster-name) CLIENT_CLUSTER_NAME="$2"; shift ;;
        --namespace) NAMESPACE="$2"; shift ;;
        --genders-file) GENDERS_FILE="$2"; shift ;;
        --client-count) CLIENT_COUNT="$2"; shift ;;
        --thread-count) THREAD_COUNT="$2"; shift ;;
        --workload-type) WORKLOAD_TYPE="$2"; shift ;;
        --total-tps) TOTAL_TPS="$2"; shift ;;
        --total-keys) TOTAL_KEYS="$2"; shift ;;
        --start-key) START_KEY="$2"; shift ;;
        --bin-size) BIN_SIZE="$2"; shift; ;;
        --compression-ratio) COMPRESSION_RATIO="$2"; shift; ;;
        --read-percentage) READ_PERCENTAGE="$2"; shift; ;;
        --expiration-time) EXPIRATION_TIME="$2"; shift; ;;
        --timeout) TIMEOUT="$2"; shift; ;;
        --async) ASYNCHRONOUS_IO=true; ;;
        --tls) USE_TLS=true; ;;
        --hot-key) HOT_KEY=true; ;;
        --numa-node) NUMA_NODE="$2"; shift; ;;
        --batch-size) BATCH_SIZE="$2"; shift; ;;
        --petname) PETNAME="$2"; shift; ;;
        # Gaussian Workload
        --standard-deviation) STD_DEVIATION="$2"; shift ;;

        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# Verify genders file exists
if [ ! -f "${GENDERS_FILE}" ]; then
    echo "the genders file ${GENDERS_FILE} does not exist"
    exit 1
fi

CLIENT_SERVER_COUNT=$(nodeattr -f "${GENDERS_FILE}" -n "${CLIENT_CLUSTER_NAME}" | wc -l)

if [ "${CLIENT_SERVER_COUNT}" -lt 1 ]; then
  echo "expected one tools node got: ${CLIENT_SERVER_COUNT}"
  exit 1
fi

# Check if numactl exists on all client nodes when --numa-node is specified
if [ -v NUMA_NODE ]; then
    if ! pdsh -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" "command -v numactl >/dev/null 2>&1" >/dev/null 2>&1; then
        echo "numactl is not available on all client nodes"
        exit 1
    fi
fi

CLUSTER_SERVER_COUNT=$(nodeattr -f "${GENDERS_FILE}" -n "${CLUSTER_NAME}" | wc -l)

if [ "${CLUSTER_SERVER_COUNT}" -lt 1 ]; then
  echo "expected one asd node got: ${CLUSTER_SERVER_COUNT}"
  exit 1
fi

CLUSTER_HOST=$(nodeattr -f "${GENDERS_FILE}" -n "${CLUSTER_NAME}" | head -1)

INSTALLED_VERSION=$(ssh "${SSH_USERNAME}"@"${CLUSTER_HOST}" -x 'rpm -q aerospike-server-enterprise --qf "%{VERSION}-%{RELEASE}"')

WORKLOAD_BINARY=asbench

cat << EOF
CLUSTER_NAME = ${CLUSTER_NAME}
CLIENT_CLUSTER_NAME = ${CLIENT_CLUSTER_NAME}
NAMESPACE = ${NAMESPACE}
INSTALLED_VERSION = ${INSTALLED_VERSION}
CLIENT_SERVER_COUNT= ${CLIENT_SERVER_COUNT}
CLIENT_COUNT = ${CLIENT_COUNT}
THREAD_COUNT = ${THREAD_COUNT}
WORKLOAD_TYPE = ${WORKLOAD_TYPE}
TOTAL_TPS = ${TOTAL_TPS}
EXPIRATION_TIME = ${EXPIRATION_TIME}
TIMEOUT = ${TIMEOUT}
DATE = $(date -u)
WORKLOAD_BINARY = ${WORKLOAD_BINARY}
EOF

if [ -v NUMA_NODE ]; then
  echo "NUMA_NODE = ${NUMA_NODE}"
fi

echo
echo "select * from aerolab_cluster where project = '${PROJECT_NAME}';" | steampipe ${AEROLAB_INVENTORY_FILE} -markdown 2>/dev/null
echo

ssh "${SSH_USERNAME}"@"${CLUSTER_HOST}" -x "cat /etc/aerospike/aerospike.conf"

TOTAL_ASBENCH=$((CLIENT_SERVER_COUNT*CLIENT_COUNT))

TPS_PER_NODE=$((TOTAL_TPS/CLIENT_SERVER_COUNT))
TPS_PER_CLIENT=$((TPS_PER_NODE/CLIENT_COUNT))

DATA_SLICE=0

cleanup() {
  trap - INT TERM

  echo
  echo "killing asbench..."
  pdsh -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" pkill asbench

  exit 0
}

trap cleanup INT TERM

# Calculate key ranges based on Gaussian distribution using Perl
calculate_key_range() {
    local start_key=$1
    local end_key=$2
    local std_dev=$3
    local num_clients=$4
    local total_tps=$5
    local data_slice=$6

    perl -MPOSIX -le '
    use List::Util qw(sum);

    # Read the arguments
    $start_key = '"$start_key"';
    $end_key = '"$end_key"';
    $std_dev = '"$std_dev"';
    $num_clients = '"$num_clients"';
    $total_tps = '"$total_tps"';
    $data_slice = '"$data_slice"';

    # Generate the ranges and calculate the TPS for each range
    my $range_per_client = int(($end_key - $start_key + 1) / $num_clients);
    my @tps_distribution = calculate_tps_distribution($num_clients, $std_dev, $total_tps);

    my $range_start = $start_key + $data_slice * $range_per_client;
    my $range_end = $data_slice == $num_clients - 1 ? $end_key : $range_start + $range_per_client - 1;
    my $tps = $total_tps == 0 ? 0 : $tps_distribution[$data_slice];
    print "$range_start $range_end $tps";

    sub calculate_tps_distribution {
        my ($num_clients, $std_dev, $total_tps) = @_;
        my @distribution;

        # Calculate a simple Gaussian distribution
        for (my $i = 0; $i < $num_clients; $i++) {
            my $x = $i - $num_clients / 2;
            my $tps = exp(-0.5 * ($x**2) / ($std_dev**2));
            push @distribution, $tps;
        }

        # Normalize to sum to 1 (proportionally scale)
        my $sum = sum @distribution;
        @distribution = map { $_ / $sum } @distribution;

        # Scale to total TPS
        @distribution = map { int($_ * $total_tps) } @distribution;

        return @distribution;
    }

    '
}

if [ -v USE_TLS ]; then
  TLSOPTIONS="--port 4333 --tls-enable --tls-cafile /etc/aerospike/ssl/tls1/cacert.pem --tls-keyfile /etc/aerospike/ssl/tls1/key.pem --tls-name tls1"
fi

if [ -v ASYNCHRONOUS_IO ]; then
  ASYNC_FLAGS="--async --conn-pools-per-node 1"
fi

if [ -v USE_TIMEOUT ]; then
  TIMEOUT_FLAGS="--read-timeout 30 --write-timeout 30 --max-retries=1 --sleep-between-retries 0 --read-socket-timeout 5000 --write-socket-timeout 5000"
fi

if [ -v NUMA_NODE ]; then
  PIN_NUMA_COMMAND="numactl --cpunodebind=${NUMA_NODE} --membind=${NUMA_NODE}"
fi


# Set artifact directory if PAR_EXEC_ARTIFACT_DIRECTORY is set
if [ -v PAR_EXEC_ARTIFACT_DIRECTORY ]; then
    ARTIFACT_DIR="${PAR_EXEC_ARTIFACT_DIRECTORY}"
    
    # Create workload_parameters.json with all configuration parameters
    cat > "${PAR_EXEC_ARTIFACT_DIRECTORY}/workload_parameters.json" << EOF
{
    "ssh_username": "${SSH_USERNAME}",
    "cluster_name": "${CLUSTER_NAME}",
    "client_cluster_name": "${CLIENT_CLUSTER_NAME}",
    "namespace": "${NAMESPACE}",
    "client_count": ${CLIENT_COUNT},
    "thread_count": ${THREAD_COUNT},
    "workload_type": "${WORKLOAD_TYPE}",
    "total_keys": ${TOTAL_KEYS},
    "start_key": ${START_KEY},
    "total_tps": ${TOTAL_TPS},
    "bin_size": ${BIN_SIZE},
    "compression_ratio": ${COMPRESSION_RATIO},
    "read_percentage": ${READ_PERCENTAGE},
    "expiration_time": ${EXPIRATION_TIME},
    "timeout": ${TIMEOUT},
    "batch_size": ${BATCH_SIZE},
    "petname": "${PETNAME}",
    "std_deviation": ${STD_DEVIATION},
    "async_io": $([ -v ASYNCHRONOUS_IO ] && echo "true" || echo "false"),
    "use_tls": $([ -v USE_TLS ] && echo "true" || echo "false"),
    "hot_key": $([ -v HOT_KEY ] && echo "true" || echo "false"),
    "numa_node": $([ -v NUMA_NODE ] && echo "\"${NUMA_NODE}\"" || echo "null"),
    "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
}
EOF
else
    ARTIFACT_DIR="$(mktemp -d)"
fi

mkdir -p "${ARTIFACT_DIR}"
echo '#!/bin/bash' > "${ARTIFACT_DIR}/run_asbench"
echo "ARTIFACT_DIR=\"${ARTIFACT_DIR}\"" >> "${ARTIFACT_DIR}/run_asbench"

# Remove the collect_artifacts function and update run_asbench script
cat >> "${ARTIFACT_DIR}/run_asbench" << 'EOF'

ASBENCH_DIR="${ARTIFACT_DIR}/asbench_$(date +%Y-%m-%d_%H-%M-%S)_$(petname)"

mkdir -p "${ASBENCH_DIR}"

EXTRAS=""
echo "$@" |grep -- '--latency' >/dev/null 2>&1
[ $? -ne 0 ] && EXTRAS="--latency"
echo "$@" |grep -- '--percentiles' >/dev/null 2>&1
if [ $? -ne 0 ]
then
  EXTRAS="${EXTRAS} --percentiles 50,90,99,99.9,99.99"
else
  echo "$@" |grep ' 50,90,99,99.9,99.99' >/dev/null 2>&1
  if [ $? -ne 0 ]
  then
    echo "WARNING: changing the first 5 percentile buckets will cause asbench latency graphs in AMS dashboard to be incorrect"
  fi
fi

echo "$@" |grep -- '--output-file' >/dev/null 2>&1
[ $? -ne 0 ] && EXTRAS="${EXTRAS} --output-file ${ASBENCH_DIR}/latencies.out"

echo "$@" |grep -- '--hdr-hist' >/dev/null 2>&1
[ $? -ne 0 ] && EXTRAS="${EXTRAS} --hdr-hist ${ASBENCH_DIR}"

touch "${ASBENCH_DIR}/asbench.log"
nohup asbench "$@" ${EXTRAS} >> "${ASBENCH_DIR}/asbench.log" 2>&1 &
EOF

chmod +x "${ARTIFACT_DIR}/run_asbench"
pdsh -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" "mkdir -p '${ARTIFACT_DIR}'"
pdcp -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" "${ARTIFACT_DIR}/run_asbench" "${ARTIFACT_DIR}/"

#########################################
#          START WORKLOAD
#########################################
echo "starting ${WORKLOAD_BINARY} workload at $(date -u)..."

for CLIENT_NUM in $(seq 1 "${CLIENT_COUNT}")
do
  #########################################
  #                Hydrate
  #########################################
  if [ "${WORKLOAD_TYPE}" == "hydrate" ]; then
    KEYS=$((TOTAL_KEYS/CLIENT_SERVER_COUNT/CLIENT_COUNT))
    for NODE in $(nodeattr -f "${GENDERS_FILE}" -n "${CLIENT_CLUSTER_NAME}"); do
      CMD="${PIN_NUMA_COMMAND} ${ARTIFACT_DIR}/run_asbench -h ${CLUSTER_HOST} -n ${NAMESPACE} -s testset -k ${KEYS} -K $(( (DATA_SLICE*KEYS) + START_KEY )) -o B${BIN_SIZE} -w I -z ${THREAD_COUNT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} --batch-size ${BATCH_SIZE} --expiration-time ${EXPIRATION_TIME} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
      echo "+ ${CMD}"

      ssh "${SSH_USERNAME}"@"${NODE}" -x "/bin/bash -c '${CMD} </dev/null > /dev/null 2>&1 &'"

      DATA_SLICE=$((DATA_SLICE+1))
    done

  #########################################
  #                Workload
  #########################################
  elif [ "${WORKLOAD_TYPE}" == "workload" ]; then
    CMD="${PIN_NUMA_COMMAND} ${ARTIFACT_DIR}/run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -k ${TOTAL_KEYS} -K ${START_KEY} -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${TPS_PER_CLIENT} --compression-ratio ${COMPRESSION_RATIO} --batch-size ${BATCH_SIZE} --expiration-time ${EXPIRATION_TIME} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
    # Run the workloads on each client node
    for NODE in $(nodeattr -f "${GENDERS_FILE}" -n "${CLIENT_CLUSTER_NAME}"); do
      echo "+ ${CMD}"
    done

    # pdsh runs the command on each client node in parallel
    pdsh -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" "/bin/bash -c '${CMD} </dev/null > /dev/null 2>&1' &"
    if [ -v HOT_KEY ]; then
      if [ "${DATA_SLICE}" -eq 0 ]; then
        CMD="${PIN_NUMA_COMMAND} ${ARTIFACT_DIR}/run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${START_KEY} -k 1 -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g $((TPS_PER_CLIENT/CLIENT_SERVER_COUNT)) --compression-ratio ${COMPRESSION_RATIO} --batch-size ${BATCH_SIZE} --expiration-time ${EXPIRATION_TIME} ${TLSOPTIONS} ${ASYNC_FLAGS} ${TIMEOUT_FLAGS} -d"
        echo "+ ${CMD}"

        ssh "${SSH_USERNAME}"@"$(nodeattr -f "${GENDERS_FILE}" -l ${CLIENT_CLUSTER_NAME} | head -1)" -x "/bin/bash -c '${CMD} </dev/null > /dev/null 2>&1 &'"
      fi
    fi

    DATA_SLICE=$((DATA_SLICE+1))

  #########################################
  #               Gaussian
  #########################################
  elif [ "${WORKLOAD_TYPE}" == "gaussian" ]; then

    for NODE in $(nodeattr -f "${GENDERS_FILE}" -n "${CLIENT_CLUSTER_NAME}"); do
    read -r start_key end_key tps <<< $(calculate_key_range ${START_KEY} $(( TOTAL_KEYS + START_KEY )) $STD_DEVIATION $TOTAL_ASBENCH $TOTAL_TPS $DATA_SLICE)

      if [ "${tps}" -gt 0 ] || [ "${TOTAL_TPS}" -eq 0 ]; then
        CMD="${PIN_NUMA_COMMAND} ${ARTIFACT_DIR}/run_asbench -h ${CLUSTER_HOST} -T 150 -n ${NAMESPACE} -s testset -K ${start_key} -k $((end_key-start_key)) -o B${BIN_SIZE} -w "RU,${READ_PERCENTAGE}" -z ${THREAD_COUNT} -t ${TIMEOUT} -g ${tps} --compression-ratio ${COMPRESSION_RATIO} --batch-size ${BATCH_SIZE} --expiration-time ${EXPIRATION_TIME} ${TLSOPTIONS} ${ASYNC_FLAGS} -d"
        echo "+ ${CMD}"

        ssh "${SSH_USERNAME}"@"${NODE}" -x "/bin/bash -c '${CMD} </dev/null > /dev/null 2>&1 &'"
      fi

      DATA_SLICE=$((DATA_SLICE+1))
    done

  else
    echo "invalid workload type ${WORKLOAD_TYPE}"
    exit 1
  fi

done

sleep 5

echo "started ${CLIENT_COUNT} ${WORKLOAD_BINARY} instances on ${CLIENT_SERVER_COUNT} nodes";

echo -n "waiting for ${WORKLOAD_BINARY} to complete..."

while pdsh -F "${GENDERS_FILE}" -g "${CLIENT_CLUSTER_NAME}" -N "ps -ef | grep -v grep" | grep -q "${WORKLOAD_BINARY}"; do
  echo -n "."
  sleep 10
done

echo
echo "finished ${WORKLOAD_BINARY} workload at $(date -u)"

exit 0
