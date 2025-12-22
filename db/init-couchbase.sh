#!/bin/sh
# Couchbase initialization script
# This script waits for Couchbase to be ready and creates the bucket

set -e

COUCHBASE_HOST="${COUCHBASE_HOST:-localhost}"
COUCHBASE_PORT="${COUCHBASE_PORT:-8091}"
COUCHBASE_USER="${COUCHBASE_USERNAME:-Administrator}"
COUCHBASE_PASS="${COUCHBASE_PASSWORD:-password}"
BUCKET_NAME="${COUCHBASE_BUCKET:-order_analytics}"

echo "Waiting for Couchbase to be ready..."
until curl -s -u "${COUCHBASE_USER}:${COUCHBASE_PASS}" "http://${COUCHBASE_HOST}:${COUCHBASE_PORT}/pools/default" > /dev/null 2>&1; do
    echo "Waiting for Couchbase..."
    sleep 2
done

echo "Couchbase is ready. Checking if bucket exists..."

# Check if bucket exists
BUCKET_EXISTS=$(curl -s -u "${COUCHBASE_USER}:${COUCHBASE_PASS}" \
    "http://${COUCHBASE_HOST}:${COUCHBASE_PORT}/pools/default/buckets/${BUCKET_NAME}" | grep -o '"name":"'${BUCKET_NAME}'"' || echo "")

if [ -z "$BUCKET_EXISTS" ]; then
    echo "Creating bucket: ${BUCKET_NAME}"
    curl -X POST -u "${COUCHBASE_USER}:${COUCHBASE_PASS}" \
        "http://${COUCHBASE_HOST}:${COUCHBASE_PORT}/pools/default/buckets" \
        -d "name=${BUCKET_NAME}" \
        -d "bucketType=couchbase" \
        -d "ramQuotaMB=100" \
        -d "authType=sasl" \
        -d "replicaNumber=0" \
        -d "flushEnabled=1"
    
    echo "Bucket ${BUCKET_NAME} created successfully"
else
    echo "Bucket ${BUCKET_NAME} already exists"
fi

echo "Couchbase initialization complete!"

