#!/bin/bash

# Load configuration
if [ -z "$PREFIX" ]; then
    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    PREFIX="${SCRIPT_DIR}/../aeropsike-cloud"
    . $PREFIX/configure.sh
else
    # When sourced from setup.sh, compute SCRIPT_DIR relative to PREFIX
    SCRIPT_DIR="${PREFIX}/../client"
fi

echo "Uploading Perseus Configuration"

# Configure aerolab backend
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" &>/dev/null

# Get cluster configuration from Aerospike Cloud
if [ -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    source "${ACS_CONFIG_DIR}/current_cluster.sh"
    
    # Load cluster config
    CLUSTER_CONFIG="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/cluster_config.sh"
    if [ -f "$CLUSTER_CONFIG" ]; then
        source "$CLUSTER_CONFIG"
        
        # Upload TLS certificate if it exists
        TLS_CERT_PATH="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/ca.pem"
        if [ -f "$TLS_CERT_PATH" ]; then
            echo "Uploading TLS certificate..."
            aerolab files upload -c -n ${CLIENT_NAME} "$TLS_CERT_PATH" /root/ca.pem || exit 1
            aerolab files upload -c -n ${CLIENT_NAME} "${SCRIPT_DIR}/templates/setup_tls.sh" /root/setup_tls.sh || exit 1
            aerolab client attach -n ${CLIENT_NAME} -l all --parallel -- bash /root/setup_tls.sh
        else
            echo "⚠️  WARNING: TLS certificate not found at: $TLS_CERT_PATH"
            echo "Perseus may fail to connect without TLS certificate."
        fi
        
        # Aerospike Cloud uses TLS by default on port 4000
        # Always use the hostname for TLS connections
        nip="${ACS_CLUSTER_HOSTNAME}"
        echo "Using cluster hostname (TLS): ${nip}"
    else
        echo "❌ ERROR: Cluster configuration not found!"
        exit 1
    fi
    
    # Upload Perseus script
    aerolab files upload -c -n ${CLIENT_NAME} "${SCRIPT_DIR}/templates/perseus.sh" /root/perseus.sh || exit 1
    
    # Load database user credentials
    DB_USER_CONFIG="${ACS_CONFIG_DIR}/${ACS_CLUSTER_NAME}/${ACS_CLUSTER_ID}/db_user.sh"
    if [ -f "$DB_USER_CONFIG" ]; then
        source "$DB_USER_CONFIG"
        echo "Using DB user: ${DB_USER}"
    else
        echo "❌ ERROR: Database user configuration not found!"
        exit 1
    fi
else
    echo "❌ ERROR: Cluster not configured!"
    exit 1
fi

# Set Aerospike Cloud connection parameters
AEROSPIKE_PORT="${SERVICE_PORT}"  # Will be 3000 for non-TLS or 4000 for TLS
AEROSPIKE_TLS_NAME="${ACS_CLUSTER_TLSNAME}"
AEROSPIKE_USERNAME="${DB_USER}"
AEROSPIKE_PASSWORD="${DB_PASSWORD}"

for (( i=1; i  <= ${CLIENT_NUMBER_OF_NODES}; i++ ))
  do
    Perseus_Conf="${SCRIPT_DIR}/templates/perseus_configuration_template.yaml"
    sed "s/_NAMESPACE_NAME_/${NAMESPACE_NAME}/g" ${Perseus_Conf} | \
    sed "s/_IP_/${nip}/g" | \
    sed "s/_PORT_/${AEROSPIKE_PORT}/g" | \
    sed "s/_USERNAME_/${AEROSPIKE_USERNAME}/g" | \
    sed "s/_PASSWORD_/${AEROSPIKE_PASSWORD}/g" | \
    sed "s/_TLS_NAME_/${AEROSPIKE_TLS_NAME}/g" | \
    sed "s/_STRING_INDEX_/${STRING_INDEX}/g" | \
    sed "s/_NUMERIC_INDEX_/${NUMERIC_INDEX}/g"| \
    sed "s/_GEO_SPATIAL_INDEX_/${GEO_SPATIAL_INDEX}/g" | \
    sed "s/_UDF_AFFREGATION_/${UDF_AFFREGATION}/g" | \
    sed "s/_RANGE_QUERY_/${RANGE_QUERY}/g" | \
    sed "s/_NORMAL_RANGE_/${NORMAL_RANGE}/g" | \
    sed "s/_MAX_RANGE_/${MAX_RANGE}/g" | \
    sed "s/_CHANCE_OF_MAX_/${CHANCE_OF_MAX}/g" | \
    sed "s/_RECORD_SIZE_/${RECORD_SIZE}/g" |  \
    sed "s/_BATCH_READ_SIZE_/${BATCH_READ_SIZE}/g" | \
    sed "s/_BATCH_WRITE_SIZE_/${BATCH_WRITE_SIZE}/g" | \
    sed "s/_TRUNCATE_SET_/${TRUNCATE_SET}/g" | \
    sed "s/_PERSEUS_ID_/$(expr $i - 1)/g" | \
    sed "s/_READ_HIT_RATIO_/${READ_HIT_RATIO}/g" > configuration.yaml

    aerolab files upload -c -n ${CLIENT_NAME} --nodes=${i} configuration.yaml /root/configuration.yaml || exit 1
    rm -rf configuration.yaml
  done

echo "Running Perseus"
aerolab client attach -n ${CLIENT_NAME} -l all --detach --parallel -- bash /root/perseus.sh

echo ""
echo "✓ Perseus started on all client nodes"
echo ""
echo "To view logs, run:"
for (( i=1; i  <= ${CLIENT_NUMBER_OF_NODES}; i++ ))
  do
    echo "  Node ${i}: aerolab client attach -n ${CLIENT_NAME} -l ${i} -- tail -f /root/out.log"
  done
echo ""
