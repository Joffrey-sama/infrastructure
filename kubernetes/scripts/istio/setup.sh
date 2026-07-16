#!/bin/bash

CONFIG_FILE="clusters.yaml"
ISTIO_VERSION="1.28.0"

# Update Helm repository just in case
helm repo add istio https://istio-release.storage.googleapis.com/charts
helm repo update

NUM_CLUSTERS=$(yq eval '.clusters | length' "$CONFIG_FILE")

echo "--- Starting Multi-Primary installation ($NUM_CLUSTERS clusters) ---"

for ((i=0; i<$NUM_CLUSTERS; i++)); do
    NAME=$(yq eval ".clusters[$i].name" "$CONFIG_FILE")
    CTX=$(yq eval ".clusters[$i].context" "$CONFIG_FILE")
    NET=$(yq eval ".clusters[$i].network" "$CONFIG_FILE")

    echo "################################################"
    echo "  CLUSTER: $NAME (Kube-Context: $CTX)"
    echo "################################################"

    # 1. Base (CRDs)
    helm upgrade --install istio-base istio/base -n istio-system --kube-context "$CTX" --version "$ISTIO_VERSION" --wait

    # 2. Istiod
    helm upgrade --install istiod istio/istiod -n istio-system --kube-context "$CTX" --version "$ISTIO_VERSION" \
      --set global.meshID=mesh1 \
      --set global.multiCluster.clusterName="$NAME" \
      --set global.network="$NET" \
      --set meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_CAPTURE="true" \
      --set meshConfig.defaultConfig.proxyMetadata.ISTIO_META_DNS_AUTO_ALLOCATE="true" \
      --set pilot.resources.requests.cpu=250m \
      --set pilot.resources.requests.memory=512Mi \
      --wait

    # 3. East-West Gateway
    yq eval ".clusters[$i].helm_values" "$CONFIG_FILE" > temp_values.yaml
    
    # Crucial fix: use quotes and escaping for dots
    helm upgrade --install istio-eastwestgateway istio/gateway -n istio-system --kube-context "$CTX" --version "$ISTIO_VERSION" \
      -f temp_values.yaml \
      --set labels.istio=eastwestgateway \
      --set "labels.topology\.istio\.io/network=$NET" \
      --set "networkGateway=$NET" \
      --wait
    
    rm temp_values.yaml

    # 4. Expose Services
    kubectl --context "$CTX" apply -n istio-system -f https://raw.githubusercontent.com/istio/istio/release-1.28/samples/multicluster/expose-services.yaml
done

# 5. Remote secrets
echo "--- Configuring Cross-Cluster Secret Sharing ---"
for ((i=0; i<$NUM_CLUSTERS; i++)); do
    SRC_NAME=$(yq eval ".clusters[$i].name" "$CONFIG_FILE")
    SRC_CTX=$(yq eval ".clusters[$i].context" "$CONFIG_FILE")
    
    for ((j=0; j<$NUM_CLUSTERS; j++)); do
        if [ $i -eq $j ]; then continue; fi
        DEST_CTX=$(yq eval ".clusters[$j].context" "$CONFIG_FILE")
        
        echo "Linking $SRC_NAME to cluster in $DEST_CTX..."
        istioctl create-remote-secret --context="$SRC_CTX" --name="$SRC_NAME" | \
            kubectl apply -f - --context="$DEST_CTX"
    done

    # --- Namespace Labeling ---
    echo "Labeling namespaces for $NAME..."
    NS_LIST=$(yq eval ".clusters[$i].namespaces[]" "$CONFIG_FILE")
    
    for NS in $NS_LIST; do
        echo "  - Enabling injection for $NS"
        kubectl label namespace "$NS" istio-injection=enabled --context "$CTX" --overwrite
    done
done