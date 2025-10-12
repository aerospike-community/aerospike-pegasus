#!/bin/bash

if [ -z "$PREFIX" ]; then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

# Source common functions
. $PREFIX/api-scripts/common.sh

echo "============================================"
echo "Aerospike Cloud - Database User Setup"
echo "============================================"
echo ""

# ============================================
# Validation
# ============================================

# Check if cluster exists
if [ ! -f "${ACS_CONFIG_DIR}/current_cluster.sh" ]; then
    echo "❌ ERROR: No cluster found!"
    echo "Please run './setup.sh' first to create a cluster."
    exit 1
fi

source "${ACS_CONFIG_DIR}/current_cluster.sh"

# Check if cluster is active
if [ "$ACS_CLUSTER_STATUS" != "active" ]; then
    echo "❌ ERROR: Cluster is not active yet!"
    echo "Current status: ${ACS_CLUSTER_STATUS}"
    echo "Please wait for cluster to become active."
    exit 1
fi

echo "Creating database user for cluster: ${ACS_CLUSTER_NAME}"
echo "  Cluster ID: ${ACS_CLUSTER_ID}"
echo "  Username: ${DB_USER}"
echo ""

# ============================================
# Check if user already exists
# ============================================

echo "Checking if user '${DB_USER}' already exists..."

EXISTING_CREDS=$(curl -sX GET \
    "${REST_API_URI}/${ACS_CLUSTER_ID}/credentials" \
    -H "@${ACS_AUTH_HEADER}")

EXISTING_USER=$(echo "$EXISTING_CREDS" | jq -r ".credentials[] | select(.name == \"${DB_USER}\") | .id")

if [ -n "$EXISTING_USER" ] && [ "$EXISTING_USER" != "null" ]; then
    echo "✓ User '${DB_USER}' already exists with ID: ${EXISTING_USER}"
    echo ""
    echo "User Details:"
    echo "$EXISTING_CREDS" | jq ".credentials[] | select(.name == \"${DB_USER}\")"
    echo ""
    echo "To reset password, delete the user and run this script again:"
    echo "  curl -X DELETE '${REST_API_URI}/${ACS_CLUSTER_ID}/credentials/${EXISTING_USER}' -H '@${ACS_AUTH_HEADER}'"
    echo ""
    
    # Get roles from API response
    USER_ROLES=$(echo "$EXISTING_CREDS" | jq -r ".credentials[] | select(.name == \"${DB_USER}\") | .roles | join(\", \")")
    
    # Save user info (including password from config for convenience)
    USER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh"
    cat > "${USER_CONFIG_FILE}" <<EOF
export DB_USER="${DB_USER}"
export DB_PASSWORD="${DB_PASSWORD}"
export DB_USER_ID="${EXISTING_USER}"
export DB_USER_ROLES="${USER_ROLES}"
export DB_USER_EXISTS="true"
EOF
    
    echo "✓ User configuration saved to: ${USER_CONFIG_FILE}"
    exit 0
fi

echo "User does not exist, creating..."
echo ""

# ============================================
# Create database user
# ============================================

echo "Creating database user with roles: data-admin, read-write-udf, truncate, sindex-admin, udf-admin"
echo ""

# Construct JSON payload
PAYLOAD=$(cat <<EOF
{
  "name": "${DB_USER}",
  "password": "${DB_PASSWORD}",
  "roles": [
    "data-admin",
    "read-write-udf",
    "truncate",
    "sindex-admin",
    "udf-admin"
  ]
}
EOF
)

# Make API call
RESPONSE=$(curl -sX POST \
    "${REST_API_URI}/${ACS_CLUSTER_ID}/credentials" \
    -H "@${ACS_AUTH_HEADER}" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD")

# Check for errors
if echo "$RESPONSE" | jq -e '.code' > /dev/null 2>&1; then
    echo "❌ ERROR: Failed to create database user!"
    echo ""
    echo "API Response:"
    echo "$RESPONSE" | jq '.'
    echo ""
    exit 1
fi

# Extract user ID
USER_ID=$(echo "$RESPONSE" | jq -r '.id')
USER_NAME=$(echo "$RESPONSE" | jq -r '.name')
USER_ROLES=$(echo "$RESPONSE" | jq -r '.roles | join(", ")')
USER_STATUS=$(echo "$RESPONSE" | jq -r '.status')

if [ -z "$USER_ID" ] || [ "$USER_ID" == "null" ]; then
    echo "❌ ERROR: Failed to extract user ID from response!"
    echo ""
    echo "API Response:"
    echo "$RESPONSE" | jq '.'
    exit 1
fi

echo "✓ Database user created successfully!"
echo ""
echo "User Details:"
echo "  Username: ${USER_NAME}"
echo "  User ID: ${USER_ID}"
echo "  Roles: ${USER_ROLES}"
echo "  Status: ${USER_STATUS}"
echo ""

# ============================================
# Save user configuration
# ============================================

USER_CONFIG_FILE="${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/db_user.sh"
cat > "${USER_CONFIG_FILE}" <<EOF
export DB_USER="${USER_NAME}"
export DB_PASSWORD="${DB_PASSWORD}"
export DB_USER_ID="${USER_ID}"
export DB_USER_ROLES="${USER_ROLES}"
export DB_USER_STATUS="${USER_STATUS}"
EOF

echo "✓ User configuration saved to: ${USER_CONFIG_FILE}"
echo ""

# ============================================
# Display connection information
# ============================================

if [ -f "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh" ]; then
    source "${ACS_CONFIG_DIR}/${ACS_CLUSTER_ID}/cluster_config.sh"
    
    echo "============================================"
    echo "Connection Information"
    echo "============================================"
    echo ""
    echo "You can now connect to the database with these credentials:"
    echo ""
    echo "  Hostname: ${ACS_CLUSTER_HOSTNAME}"
    echo "  Port: ${SERVICE_PORT}"
    echo "  Username: ${DB_USER}"
    echo "  Password: ${DB_PASSWORD}"
    echo ""
    echo "Example using aql (from client):"
    echo "  aql --tls-enable --tls-name ${ACS_CLUSTER_TLSNAME} \\"
    echo "      -h ${ACS_CLUSTER_HOSTNAME}:${SERVICE_PORT} \\"
    echo "      -U ${DB_USER} -P ${DB_PASSWORD}"
    echo ""
    echo "Example using asadm (from client):"
    echo "  asadm --tls-enable --tls-name ${ACS_CLUSTER_TLSNAME} \\"
    echo "      -h ${ACS_CLUSTER_HOSTNAME}:${SERVICE_PORT} \\"
    echo "      --user ${DB_USER} --password ${DB_PASSWORD}"
    echo ""
fi

echo "============================================"
echo "✓ Database User Setup Complete!"
echo "============================================"
echo ""

