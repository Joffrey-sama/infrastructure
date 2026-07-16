#!/bin/bash

# This script updates the /etc/hosts file to point all
# HTTPRoute hostnames to the NGINX Gateway IP.
# Must be run with sudo or by a user with write permissions on /etc/hosts.

set -e

# --- Configuration ---
GATEWAY_NAMESPACE="common-services"
GATEWAY_NAME="main-gateway-nginx"
# Target Windows hosts file from WSL
HOSTS_FILE="/mnt/c/Windows/System32/drivers/etc/hosts"
MARKER="# K3S_GATEWAY_ENTRIES_MARKER"

# --- Script ---

# When running with sudo, kubectl might not find the user's kubeconfig.
# We explicitly point to the config of the user who invoked sudo.
if [ -n "$SUDO_USER" ]; then
    export KUBECONFIG="/home/$SUDO_USER/.kube/config"
fi

echo "INFO: Retrieving Gateway IP..."
GATEWAY_IP=$(kubectl get svc -n "$GATEWAY_NAMESPACE" "$GATEWAY_NAME" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')

if [ -z "$GATEWAY_IP" ]; then
    echo "ERROR: Unable to find IP address for Gateway '$GATEWAY_NAME' in namespace '$GATEWAY_NAMESPACE'."
    exit 1
fi
echo "INFO: Gateway IP found: $GATEWAY_IP"

echo "INFO: Retrieving hostnames from HTTPRoutes..."
HOSTNAMES=$(kubectl get httproute --all-namespaces -o jsonpath='{range .items[*]}{.spec.hostnames[*]}{" "}{end}')

if [ -z "$HOSTNAMES" ]; then
    echo "WARNING: No hostnames found in HTTPRoutes."
    HOSTS_LINE=""
else
    # Remove duplicates and format the line
    UNIQUE_HOSTNAMES=$(echo "$HOSTNAMES" | tr ' ' '\n' | sort -u | tr '\n' ' ')
    HOSTS_LINE="$GATEWAY_IP $UNIQUE_HOSTNAMES"
fi

echo "INFO: Line to add/update is: '$HOSTS_LINE'"

echo "INFO: Updating file $HOSTS_FILE..."
# Use sed to delete old marked entries and add the new one
if grep -q "$MARKER" "$HOSTS_FILE"; then
    # Remove the existing line
    sed -i "/$MARKER/d" "$HOSTS_FILE"
fi

# Add the new line at the end of the file
echo "$HOSTS_LINE $MARKER" >> "$HOSTS_FILE"

echo "SUCCESS: File $HOSTS_FILE has been updated."