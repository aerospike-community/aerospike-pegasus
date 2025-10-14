#!/bin/bash

if [ -z "$PREFIX" ];
  then
    PREFIX=$(pwd "$0")"/"$(dirname "$0")
    . $PREFIX/configure.sh
fi

echo "====================================="
echo "Aerospike Cloud - Client Destroy"
echo "====================================="
echo ""

# Check if client config exists
if [ ! -f "${CLIENT_CONFIG_DIR}/client_config.sh" ]; then
    echo "No client configuration found in tracker."
    echo "Looking for client by name '${CLIENT_NAME}'..."
    
    # Check if client exists in aerolab
    CLIENT_EXISTS=$(aerolab client list 2>/dev/null | grep -w "${CLIENT_NAME}" || true)
    
    if [ -z "$CLIENT_EXISTS" ]; then
        echo "⚠️  No client found with name '${CLIENT_NAME}' (may already be deleted)"
        return 0
    fi
    
    echo "Found client: ${CLIENT_NAME}"
else
    # Load client info from tracker
    source "${CLIENT_CONFIG_DIR}/client_config.sh"
    echo "Found tracked client:"
    echo "  Name: ${CLIENT_NAME}"
    echo "  VPC ID: ${CLIENT_VPC_ID}"
    echo "  Instance IDs: ${CLIENT_INSTANCE_IDS}"
fi

echo ""
echo "Deleting client..."

# Configure aerolab backend
aerolab config backend -t aws -r "${CLIENT_AWS_REGION}" &>/dev/null || true

# Destroy client using aerolab
aerolab client destroy -n "${CLIENT_NAME}" -f

if [ $? -eq 0 ]; then
    echo "✓ Client destroyed successfully"
    echo ""
    
    # Clean up tracker files
    echo "Cleaning up tracker files..."
    
    if [ -d "${CLIENT_CONFIG_DIR}" ]; then
        rm -rf "${CLIENT_CONFIG_DIR}"
        echo "✓ Removed ${CLIENT_CONFIG_DIR}/"
    fi
    
    echo ""
    echo "====================================="
    echo "✓ Client destruction complete!"
    echo "====================================="
    echo ""
    echo "Note: The AWS VPC created for the client will be automatically"
    echo "removed by aerolab. VPC peering connections (if any) should be"
    echo "manually verified in the AWS console."
    
else
    echo ""
    echo "⚠️  Failed to destroy client!"
    echo "You may need to manually clean up resources in AWS console."
    return 1
fi
