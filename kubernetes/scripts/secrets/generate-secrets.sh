#!/bin/bash
set -e
set -o pipefail

# This script reads a central YAML file (secrets.yaml) and ensures the corresponding
# secrets exist in the cluster. If a secret does not exist, it generates a password
# and creates the SealedSecret object directly in the cluster.
#
# WARNING: This script is designed to be run for initial setup. Re-running it
# will not update existing secrets. To rotate a password, you must manually delete
# the corresponding Kubernetes Secret and SealedSecret first.
#
# Prerequisites:
# - 'kubectl', 'kubeseal', 'yq' command-line tools must be installed.
# - Your KUBECONFIG must be pointing to the cluster with the Sealed Secrets controller.
#
# Usage:
#   ./generate-secrets.sh [-c|--default-context <kube-context>]

SECRETS_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"
CONFIG_FILE="${SECRETS_DIR}/secrets.yaml"

# Parse arguments
DEFAULT_CONTEXT=""
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -c|--default-context) DEFAULT_CONTEXT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; exit 1 ;;
    esac
    shift
done

# --- Configuration for Sealed Secrets Controller ---
SEALED_SECRETS_NAMESPACE="kube-system"
SEALED_SECRETS_CONTROLLER_NAME="sealed-secrets-controller"

if ! command -v yq &> /dev/null; then
    echo "ERROR: 'yq' command not found. Please install it to continue."
    echo "Installation instructions: https://github.com/mikefarah/yq/#install"
    exit 1
fi

echo "🔑 Ensuring secrets exist in the cluster based on ${CONFIG_FILE}..."

# Use an associative array to store generated passwords for reuse
declare -A password_store

# Function to fetch and cache the cert for a specific context
fetch_cert_for_context() {
    local ctx="$1"
    local cert_file="/tmp/kubeseal-cert-${ctx:-default}.pem"
    local ctx_arg=""
    if [[ -n "$ctx" ]]; then ctx_arg="--context $ctx"; fi

    if [[ ! -f "$cert_file" ]]; then
        echo "   📥 Fetching Sealed Secrets certificate for context '${ctx:-current}'..." >&2
        if ! kubeseal $ctx_arg --controller-name "${SEALED_SECRETS_CONTROLLER_NAME}" --controller-namespace "${SEALED_SECRETS_NAMESPACE}" --fetch-cert > "$cert_file"; then
            echo "❌ ERROR: Failed to fetch certificate from context '${ctx}'." >&2
            return 1
        fi
    fi
    echo "$cert_file"
}

# --- Helper Function ---
# This function processes a single secret definition from the YAML file.
# It iterates through each key defined for the secret, determines its value
# (generated, prompted, static, or from another secret), and then seals
# the complete secret with all its key-value pairs.
generate_and_seal() {
  local secret_yaml="$1"
  local secret_name=$(echo "$secret_yaml" | yq e '.name' -)
  local namespace=$(echo "$secret_yaml" | yq e '.namespace' -)
  local context=$(echo "$secret_yaml" | yq e '.context // ""' -)

  # Determine target context (YAML > Argument > Current)
  local target_context="${context:-$DEFAULT_CONTEXT}"
  local context_arg=""
  if [[ -n "$target_context" ]]; then context_arg="--context $target_context"; fi

  # Fetch existing secret as JSON to ensure proper parsing of the data map.
  # We use -o json because -o jsonpath='{.data}' returns a non-standard map[k:v] format.
  local existing_secret_data="{}"
  if kubectl $context_arg get secret "${secret_name}" -n "${namespace}" &>/dev/null; then
    existing_secret_data=$(kubectl $context_arg get secret "${secret_name}" -n "${namespace}" -o json | yq e '.data // {}' -)
  fi

  # Fetch cert for this context
  local cert_file
  cert_file=$(fetch_cert_for_context "$target_context") || exit 1

  echo "   - Syncing SealedSecret '${secret_name}' in namespace '${namespace}' (${target_context:-current})..."

  local needs_update=false
  
  # Create a temporary file for the Secret manifest
  local secret_manifest_file=$(mktemp)
  cat <<EOF > "$secret_manifest_file"
apiVersion: v1
kind: Secret
metadata:
  name: ${secret_name}
  namespace: ${namespace}
type: Opaque
stringData: {}
EOF

  # Prepare annotations
  local ann_file=$(mktemp)
  echo "{}" > "$ann_file"

  # 1. Load explicit annotations from YAML
  local annotations_yaml=$(echo "$secret_yaml" | yq e '.annotations' -)
  if [[ "$annotations_yaml" != "null" ]]; then
    echo "$annotations_yaml" > "$ann_file"
  fi

  # 2. Handle 'namespaces_allowed' helper for Reflector
  local namespaces_allowed=$(echo "$secret_yaml" | yq e '.namespaces_allowed // ""' -)
  if [[ -n "$namespaces_allowed" ]]; then
    yq e -i '.["replicator.v1.mittwald.de/replicate-to"] = "'"$namespaces_allowed"'"' "$ann_file"
  fi

  # Apply annotations if any exist
  if [[ "$(cat "$ann_file")" != "{}" ]]; then
    yq e -i ".metadata.annotations = load(\"$ann_file\")" "$secret_manifest_file"
  fi
  rm "$ann_file"

  local current_keys_in_yaml=()
  # Loop through each key defined for the current secret
  while read -r key_item; do
    local key_name=$(echo "$key_item" | yq e '.name' - | tr -d '"')
    local static_value=$(echo "$key_item" | yq e '.value // ""' -)
    local prompt_for_value=$(echo "$key_item" | yq e '.prompt // "false"' -)
    local value_from_name=$(echo "$key_item" | yq e '.valueFromSecret.name // ""' -)
    local value_from_namespace=$(echo "$key_item" | yq e '.valueFromSecret.namespace // ""' -)
    local value_from_context=$(echo "$key_item" | yq e '.valueFromSecret.context // ""' -)
    local value_from_key=$(echo "$key_item" | yq e '.valueFromSecret.key // ""' -)
    local format=$(echo "$key_item" | yq e '.format // "base64"' -)
    local final_value=""
    current_keys_in_yaml+=("$key_name")

    # Check if the key already exists in the cluster
    local existing_b64_value=$(echo "$existing_secret_data" | yq e ".[\"${key_name}\"] // \"\"" -)
    local existing_value=""
    if [[ -z "$existing_b64_value" || "$existing_b64_value" == "null" ]]; then
        existing_value=""
    else
        # Remove potential quotes and newlines before decoding
        existing_value=$(echo "$existing_b64_value" | tr -d '"\n ' | base64 -d)
    fi

    if [[ -n "$static_value" ]]; then
      # Use the static value provided in secrets.yaml
      final_value="$static_value"
      echo "     - Using static value for key '${key_name}'."

    elif [[ -n "$value_from_name" ]]; then
      # Use a value from another secret
      local source_key="${value_from_key}"
      local store_key="${value_from_namespace}_${value_from_name}_${source_key}"
      
      # Determine source context for the referenced secret
      local src_ctx="${value_from_context:-$target_context}"
      local src_ctx_arg=""
      if [[ -n "$src_ctx" ]]; then src_ctx_arg="--context $src_ctx"; fi

      # 1. Check our in-memory store first (for secrets generated in this run)
      if [[ -n "${password_store[$store_key]}" ]]; then
        final_value="${password_store[$store_key]}"
        echo "     - Reusing password from in-memory store for key '${key_name}'..."
      # 2. If not in memory, check if the source secret exists in the cluster
      elif kubectl $src_ctx_arg get secret "${value_from_name}" -n "${value_from_namespace}" &> /dev/null; then
        echo "     - Source secret '${value_from_name}' exists in context '${src_ctx:-current}'. Fetching value for key '${source_key}'..."
        final_value=$(kubectl $src_ctx_arg get secret "${value_from_name}" -n "${value_from_namespace}" -o go-template="{{index .data \"${source_key}\"}}" | base64 --decode)
        if [[ -z "$final_value" ]]; then
          echo "ERROR: Failed to retrieve key '${source_key}' from existing secret '${value_from_name}' in namespace '${value_from_namespace}'."
          exit 1
        fi
      # 3. If it's not in memory and not in the cluster, it's an error
      else
        echo "ERROR: Could not find value for source secret '${value_from_name}' (key: ${source_key})."
        echo "       It was not generated in this run, and it does not exist in the cluster."
        echo "       Ensure it is defined before the secret that references it in secrets.yaml."
        exit 1
      fi

    elif [[ "$prompt_for_value" == "true" ]]; then
      if [[ -n "$existing_value" ]]; then
        final_value="$existing_value"
        echo "     - Preserving existing manual value for key '${key_name}' (skipping prompt)."
      else
        # Prompt the user for the value
        echo "     - Prompting for value for key '${key_name}'..."
        # The -r flag prevents backslash escapes from being interpreted.
        # We redirect from /dev/tty to ensure we are reading from the keyboard, not a pipe.
        read -rsp "       -> Enter value: " final_value < /dev/tty
        echo "" # Newline after prompt
        if [[ -z "$final_value" ]]; then
          echo "     ❌ ERROR: Value provided for key '${key_name}' cannot be empty."
          exit 1
        fi
      fi

    elif [[ -n "$existing_value" ]]; then
      # PRESERVE: If the key exists in the cluster, we keep it
      final_value="$existing_value"
      echo "     - Preserving existing value for key '${key_name}'."

    elif [[ "$format" == "hex" ]]; then
      # Generate a 32-byte hex string (64 characters)
      final_value=$(openssl rand -hex 32)
      echo "     - Generating new hex value for '${key_name}'."
    elif [[ "$format" == "privkey" ]]; then
      # Generate a 32-byte hex string prefixed with "privkey:" for Headscale/Tailscale
      final_value="privkey:$(openssl rand -hex 32)"
      echo "     - Generating new privkey value for '${key_name}'."

    else
      # Generate a new random password as the default action
      final_value=$(openssl rand -base64 48 | tr -d '\n+/=')
      echo "     - Generating new random password for key '${key_name}'."
    fi

    # Check if we are actually changing anything
    if [[ "$final_value" != "$existing_value" ]]; then
        needs_update=true
    fi

    # Store the newly generated password in memory for potential reuse by other secrets in this run.
    # This is safe to do for all value types (prompted, static, etc.).
    local store_key="${namespace}_${secret_name}_${key_name}"
    password_store[$store_key]=$final_value

    # Update the manifest file using yq to ensure valid YAML (handles multiline strings, etc.)
    export SECRET_VALUE="$final_value"
    yq e -i ".stringData[\"${key_name}\"] = env(SECRET_VALUE)" "$secret_manifest_file"

  done < <(echo "$secret_yaml" | yq e -o=j -I=0 '.keys[]' -)

  # Check if any keys were removed from YAML that exist in the cluster
  if [[ "$existing_secret_data" != "{}" ]]; then
      while read -r existing_key; do
          if [[ ! " ${current_keys_in_yaml[@]} " =~ " ${existing_key} " ]]; then
              echo "     - Key '${existing_key}' removed from definition. Updating secret."
              needs_update=true
          fi
      done < <(echo "$existing_secret_data" | yq e 'keys | .[]' -)
  fi

  if [[ "$needs_update" == "true" ]]; then
    # Seal and Apply
    echo "   📥 Content changed or new keys found. Applying SealedSecret..."
    kubeseal --cert "$cert_file" --format=yaml < "$secret_manifest_file" | kubectl $context_arg apply -f - >/dev/null
    echo "   ✅ SealedSecret for '${secret_name}' updated."
  else
    echo "   ✨ SealedSecret for '${secret_name}' is already up to date. No changes applied."
  fi

  rm "$secret_manifest_file"
}

# Read the yaml file and capture all secret definitions first.
# This avoids potential file descriptor conflicts when `read < /dev/tty` is used inside the loop.
ALL_SECRET_DEFINITIONS=$(yq e -o=j -I=0 '.secrets[]' "$CONFIG_FILE")

# Loop through each secret definition
while IFS= read -r secret_definition; do
    generate_and_seal "$secret_definition"
done <<< "$ALL_SECRET_DEFINITIONS"

echo "✨ Secret check complete."