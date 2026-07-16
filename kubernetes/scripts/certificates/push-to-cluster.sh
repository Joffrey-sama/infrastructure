#!/bin/bash
set -e

# Load .env
if [ -f .env ]; then
    source .env
else
    echo "Error: Missing .env."
    exit 1
fi

OUTPUT_DIR="./certs"

usage() {
    echo "Usage: $0 <cluster_prefix> <kube_context> <network_name>"
    echo "Example: $0 oci context-oci network-oci"
    exit 1
}

PREFIX=$1
CONTEXT=$2
NETWORK_NAME=$3 # Pass as argument to be precise

if [ -z "$PREFIX" ] || [ -z "$CONTEXT" ] || [ -z "$NETWORK_NAME" ]; then
    usage
fi

echo "--- Preparing cluster [$CONTEXT] (Prefix: $PREFIX) ---"

# 1. Namespace and Label (Add safety and network label)
kubectl --context "$CONTEXT" create namespace istio-system --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -
kubectl --context "$CONTEXT" label namespace istio-system topology.istio.io/network=$NETWORK_NAME --overwrite

# 2. Verify certificate files
if [ ! -f "$OUTPUT_DIR/${PREFIX}-ca-cert.pem" ]; then
    echo "Error: Certificates for $PREFIX not found in $OUTPUT_DIR"
    exit 1
fi

# 3. Secret cacerts (Apply method to avoid 'already exists' errors)
kubectl --context "$CONTEXT" create secret generic cacerts -n istio-system \
    --from-file=ca-cert.pem="$OUTPUT_DIR/${PREFIX}-ca-cert.pem" \
    --from-file=ca-key.pem="$OUTPUT_DIR/${PREFIX}-ca-key.pem" \
    --from-file=root-cert.pem="$OUTPUT_DIR/root-cert.pem" \
    --from-file=cert-chain.pem="$OUTPUT_DIR/${PREFIX}-cert-chain.pem" \
    --dry-run=client -o yaml | kubectl --context "$CONTEXT" apply -f -

echo "✅ Namespace prepared and secret 'cacerts' injected in $CONTEXT"