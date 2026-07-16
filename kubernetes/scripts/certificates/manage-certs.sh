#!/bin/bash
set -e

# Load configuration
if [ -f .env ]; then
    export $(grep -v '^#' .env | xargs)
else
    echo "Error: Missing .env file."
    exit 1
fi

# Force output directory to match .gitignore
OUTPUT_DIR="./certs"
mkdir -p "$OUTPUT_DIR"

usage() {
    echo "Usage: $0 {init-all|renew-root|renew-intermediates|check-expiry}"
    exit 1
}

generate_root() {
    echo "[ROOT] Generating a new Root CA..."
    openssl genrsa -out "$OUTPUT_DIR/root-key.pem" 4096
    openssl req -x509 -new -nodes -key "$OUTPUT_DIR/root-key.pem" \
        -days "$ROOT_DAYS" -out "$OUTPUT_DIR/root-cert.pem" \
        -subj "/O=$ORG_NAME/CN=Root-CA"
}

generate_intermediates() {
    clean_clusters=$(echo $CLUSTERS | tr -d '"' | tr ',' ' ')

    for CLUSTER in $clean_clusters; do
        echo "[$CLUSTER] Generating intermediate with CA extensions..."
        
        # 1. Key
        openssl genrsa -out "$OUTPUT_DIR/${CLUSTER}-ca-key.pem" 2048
        
        # 2. CSR
        openssl req -new -key "$OUTPUT_DIR/${CLUSTER}-ca-key.pem" \
            -out "$OUTPUT_DIR/${CLUSTER}-ca-csr.pem" \
            -subj "/O=$ORG_NAME/CN=$CLUSTER-CA"
        
        # 3. Create temporary extension file
        cat > "$OUTPUT_DIR/ext.conf" <<EOF
[ v3_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, digitalSignature, cRLSign, keyCertSign
EOF

        # 4. Sign with CA extensions
        openssl x509 -req -days "$INTERMEDIATE_DAYS" \
            -in "$OUTPUT_DIR/${CLUSTER}-ca-csr.pem" \
            -CA "$OUTPUT_DIR/root-cert.pem" \
            -CAkey "$OUTPUT_DIR/root-key.pem" \
            -CAcreateserial \
            -out "$OUTPUT_DIR/${CLUSTER}-ca-cert.pem" \
            -extfile "$OUTPUT_DIR/ext.conf" \
            -extensions v3_ca
            
        cat "$OUTPUT_DIR/${CLUSTER}-ca-cert.pem" "$OUTPUT_DIR/root-cert.pem" > "$OUTPUT_DIR/${CLUSTER}-cert-chain.pem"
        
        rm "$OUTPUT_DIR/${CLUSTER}-ca-csr.pem" "$OUTPUT_DIR/ext.conf"
        echo "[$CLUSTER] OK."
    done
}

check_expiry() {
    echo "--- Certificate status in $OUTPUT_DIR ---"
    for cert in "$OUTPUT_DIR"/*.pem; do
        if [[ $cert == *"cert.pem"* ]]; then
            echo -n "$(basename $cert): "
            openssl x509 -noout -enddate -in "$cert"
        fi
    done
}

case "$1" in
    init-all|renew-root)
        generate_root
        generate_intermediates
        ;;
    renew-intermediates)
        if [ ! -f "$OUTPUT_DIR/root-key.pem" ]; then
            echo "Error: root-key.pem not found in $OUTPUT_DIR. Run init-all first."
            exit 1
        fi
        generate_intermediates
        ;;
    check-expiry)
        check_expiry
        ;;
    *)
        usage
        ;;
esac

echo "--- Certificates successfully generated in $OUTPUT_DIR ---"