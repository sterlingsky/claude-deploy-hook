#!/bin/bash
# Kubernetes Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Kubernetes"
PROVIDER_ID="kubernetes"

# Default configuration
: "${K8S_NAMESPACE:=default}"
: "${K8S_DEPLOYMENT:=}"
: "${K8S_CONTEXT:=}"
: "${K8S_CONFIGMAP:=}"  # Optional: ConfigMap name for env vars

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/k8s/deployment.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/k8s/deployment.yml" ] && return 0
  [ -f "${PROJECT_DIR}/kubernetes/deployment.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/deployment.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/kustomization.yaml" ] && return 0
  [ -d "${PROJECT_DIR}/helm" ] && return 0
  [ -f "${PROJECT_DIR}/Chart.yaml" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  # Check kubectl CLI
  if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl CLI not found${NC}" >&2
    echo "  Install from: https://kubernetes.io/docs/tasks/tools/" >&2
    errors=1
  fi

  if [ -z "$K8S_DEPLOYMENT" ]; then
    echo -e "${RED}Error: K8S_DEPLOYMENT not set${NC}" >&2
    echo "  Set K8S_DEPLOYMENT environment variable to your deployment name" >&2
    errors=1
  fi

  # Verify context if specified
  if [ -n "$K8S_CONTEXT" ]; then
    if ! kubectl config get-contexts "$K8S_CONTEXT" &>/dev/null; then
      echo -e "${RED}Error: Kubernetes context '$K8S_CONTEXT' not found${NC}" >&2
      errors=1
    fi
  fi

  return $errors
}

# Get kubectl command with optional context
kubectl_cmd() {
  local -a cmd=(kubectl)
  [ -n "$K8S_CONTEXT" ] && cmd+=(--context "$K8S_CONTEXT")
  [ -n "$K8S_NAMESPACE" ] && cmd+=(--namespace "$K8S_NAMESPACE")
  echo "${cmd[@]}"
}

# Check if deployment exists
service_exists() {
  $(kubectl_cmd) get deployment "$K8S_DEPLOYMENT" &>/dev/null
}

# Fetch live environment variables from deployment
# Output: KEY=VALUE per line to stdout
fetch_live_env() {
  local config

  # Get env vars from deployment spec
  config=$($(kubectl_cmd) get deployment "$K8S_DEPLOYMENT" -o json 2>/dev/null) || return 1

  # Extract env vars from containers
  echo "$config" | jq -r '
    .spec.template.spec.containers[0].env // [] |
    map(select(.value != null)) |
    map("\(.name)=\(.value)") |
    .[]' 2>/dev/null || true

  # Also check ConfigMap if specified
  if [ -n "$K8S_CONFIGMAP" ]; then
    $(kubectl_cmd) get configmap "$K8S_CONFIGMAP" -o json 2>/dev/null | jq -r '
      .data // {} |
      to_entries |
      map("\(.key)=\(.value)") |
      .[]' 2>/dev/null || true
  fi
}

# Fetch live secrets references
# Output: KEY=SECRET_NAME:KEY per line to stdout
fetch_live_secrets() {
  local config
  config=$($(kubectl_cmd) get deployment "$K8S_DEPLOYMENT" -o json 2>/dev/null) || return 1

  # Extract secret refs from containers
  echo "$config" | jq -r '
    .spec.template.spec.containers[0].env // [] |
    map(select(.valueFrom.secretKeyRef != null)) |
    map("\(.name)=\(.valueFrom.secretKeyRef.name):\(.valueFrom.secretKeyRef.key)") |
    .[]' 2>/dev/null || true
}

# Deploy to Kubernetes
# Args: env_vars secrets vars_to_remove source_dir
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Kubernetes...${NC}"
  echo "  Deployment: $K8S_DEPLOYMENT"
  echo "  Namespace:  $K8S_NAMESPACE"
  [ -n "$K8S_CONTEXT" ] && echo "  Context:    $K8S_CONTEXT"
  echo ""

  local kubectl=$(kubectl_cmd)

  # Update ConfigMap if specified
  if [ -n "$K8S_CONFIGMAP" ] && [ -n "$env_vars" ]; then
    echo -e "${BLUE}Updating ConfigMap $K8S_CONFIGMAP...${NC}"

    # Build configmap from env vars
    local -a cm_cmd=($kubectl create configmap "$K8S_CONFIGMAP" --dry-run=client -o yaml)

    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      cm_cmd+=(--from-literal="$key=$value")
    done

    # Apply the configmap
    "${cm_cmd[@]}" | $kubectl apply -f -
  fi

  # Set env vars directly on deployment if no ConfigMap
  if [ -z "$K8S_CONFIGMAP" ] && [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      $kubectl set env deployment/"$K8S_DEPLOYMENT" "$key=$value"
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      $kubectl set env deployment/"$K8S_DEPLOYMENT" "$key-" 2>/dev/null || true
    done
  fi

  # Apply manifests if they exist
  if [ -d "$source_dir/k8s" ]; then
    echo -e "${BLUE}Applying k8s manifests...${NC}"
    $kubectl apply -f "$source_dir/k8s/"
  elif [ -d "$source_dir/kubernetes" ]; then
    echo -e "${BLUE}Applying kubernetes manifests...${NC}"
    $kubectl apply -f "$source_dir/kubernetes/"
  elif [ -f "$source_dir/kustomization.yaml" ]; then
    echo -e "${BLUE}Applying kustomization...${NC}"
    $kubectl apply -k "$source_dir"
  elif [ -f "$source_dir/deployment.yaml" ]; then
    echo -e "${BLUE}Applying deployment.yaml...${NC}"
    $kubectl apply -f "$source_dir/deployment.yaml"
  fi

  # Rollout status
  echo ""
  echo -e "${BLUE}Waiting for rollout...${NC}"
  $kubectl rollout status deployment/"$K8S_DEPLOYMENT" --timeout=300s
}

# Print provider-specific info
print_info() {
  echo "Provider:   $PROVIDER_NAME"
  echo "Deployment: $K8S_DEPLOYMENT"
  echo "Namespace:  $K8S_NAMESPACE"
  [ -n "$K8S_CONTEXT" ] && echo "Context:    $K8S_CONTEXT"
  [ -n "$K8S_CONFIGMAP" ] && echo "ConfigMap:  $K8S_CONFIGMAP"
}
