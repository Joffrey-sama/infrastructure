#!/bin/bash
CONTEXT=$1
if [ -z "$CONTEXT" ]; then echo "Usage: ./clean.sh <kube-context>"; exit 1; fi

echo "--- Cleaning context $CONTEXT ---"

# 1. Uninstall Helm releases
helm uninstall istio-eastwestgateway -n istio-system --kube-context "$CONTEXT"
helm uninstall istiod -n istio-system --kube-context "$CONTEXT"
helm uninstall istio-base -n istio-system --kube-context "$CONTEXT"

echo "--- Forced correction of Helm ownership ---"

# 2. Remove old annotations (ignore errors if already deleted)
kubectl annotate crd -l app.kubernetes.io/managed-by=Helm meta.helm.sh/release-name- meta.helm.sh/release-namespace- --overwrite --context "$CONTEXT" 2>/dev/null

# 3. Force CRD ownership assignment to 'istio-base'
kubectl get crd -l app.kubernetes.io/managed-by=Helm -o name | xargs -I {} kubectl annotate {} meta.helm.sh/release-name="istio-base" meta.helm.sh/release-namespace="istio-system" --overwrite --context "$CONTEXT"

# 4. Force ClusterRole ownership assignment to 'istiod'
kubectl annotate clusterrole istio-reader-clusterrole-istio-system meta.helm.sh/release-name="istiod" meta.helm.sh/release-namespace="istio-system" --overwrite --context "$CONTEXT" 2>/dev/null
kubectl annotate clusterrolebinding istio-reader-clusterrole-istio-system meta.helm.sh/release-name="istiod" meta.helm.sh/release-namespace="istio-system" --overwrite --context "$CONTEXT" 2>/dev/null

echo "--- Cleaning complete for $CONTEXT ---"