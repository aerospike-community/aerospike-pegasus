#!/bin/bash
# Setup TLS certificate for Perseus

# Create directory for certificates
mkdir -p /root/.aerospike

# Create Java truststore with the certificate
# Import the certificate into a Java keystore
if [ -f /root/ca.pem ]; then
    # Delete existing alias if it exists to avoid errors
    keytool -delete -alias aerospike-cloud \
        -keystore /root/.aerospike/truststore.jks \
        -storepass 123456 -noprompt 2>/dev/null || true
    
    # Convert PEM to Java truststore
    # Perseus uses "123456" as the default truststore password
    keytool -import -trustcacerts -alias aerospike-cloud -file /root/ca.pem \
        -keystore /root/.aerospike/truststore.jks \
        -storepass 123456 -noprompt 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo "✓ TLS truststore created successfully at /root/.aerospike/truststore.jks"
    else
        echo "❌ Failed to create truststore"
        exit 1
    fi
else
    echo "❌ ERROR: Certificate file not found at /root/ca.pem"
    exit 1
fi

