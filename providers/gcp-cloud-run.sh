#!/bin/bash
# GCP Cloud Run Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="GCP Cloud Run"
PROVIDER_ID="gcp-cloud-run"

# Default configuration
: "${GCP_PROJECT:=${GOOGLE_CLOUD_PROJECT:-}}"
: "${GCP_REGION:=${CLOUD_RUN_REGION:-us-central1}}"
: "${GCP_SERVICE:=${CLOUD_RUN_SERVICE:-}}"

# Detect if this provider should be used
# Returns 0 if detected, 1 otherwise
detect() {
  # Check for Dockerfile or Cloud Run service.yaml
  [ -f "${PROJECT_DIR}/Dockerfile" ] && return 0
  [ -f "${PROJECT_DIR}/service.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/cloudbuild.yaml" ] && grep -q "cloud-run" "${PROJECT_DIR}/cloudbuild.yaml" 2>/dev/null && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if [ -z "$GCP_PROJECT" ]; then
    echo -e "${RED}Error: GCP_PROJECT not set${NC}" >&2
    echo "  Set GOOGLE_CLOUD_PROJECT or GCP_PROJECT environment variable" >&2
    errors=1
  fi

  if [ -z "$GCP_SERVICE" ]; then
    echo -e "${RED}Error: GCP_SERVICE not set${NC}" >&2
    echo "  Set CLOUD_RUN_SERVICE or GCP_SERVICE environment variable" >&2
    errors=1
  fi

  return $errors
}

# Check if service exists
service_exists() {
  gcloud run services describe "$GCP_SERVICE" \
    --project "$GCP_PROJECT" \
    --region "$GCP_REGION" \
    --format "value(name)" 2>/dev/null
}

# Fetch live environment variables
# Output: KEY=VALUE per line to stdout
fetch_live_env() {
  local config
  config=$(gcloud run services describe "$GCP_SERVICE" \
    --project "$GCP_PROJECT" \
    --region "$GCP_REGION" \
    --format json 2>/dev/null) || return 1

  echo "$config" | jq -r '
    .spec.template.spec.containers[0].env // []
    | map(select(.value != null))
    | map("\(.name)=\(.value)")
    | .[]' 2>/dev/null || true
}

# Fetch live secrets
# Output: KEY=SECRET:VERSION per line to stdout
fetch_live_secrets() {
  local config
  config=$(gcloud run services describe "$GCP_SERVICE" \
    --project "$GCP_PROJECT" \
    --region "$GCP_REGION" \
    --format json 2>/dev/null) || return 1

  echo "$config" | jq -r '
    .spec.template.spec.containers[0].env // []
    | map(select(.valueFrom.secretKeyRef != null))
    | map("\(.name)=\(.valueFrom.secretKeyRef.name):\(.valueFrom.secretKeyRef.key // "latest")")
    | .[]' 2>/dev/null || true
}

# Deploy to Cloud Run
# Args: env_vars secrets vars_to_remove source_dir
# SECURITY: Uses array-based command construction instead of eval
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  # Build command as array to avoid eval
  local -a cmd=(
    gcloud run deploy "$GCP_SERVICE"
    --project "$GCP_PROJECT"
    --region "$GCP_REGION"
    --source "$source_dir"
    --platform managed
  )

  # Add optional arguments
  [ -n "$env_vars" ] && cmd+=(--set-env-vars "$env_vars")
  [ -n "$secrets" ] && cmd+=(--set-secrets "$secrets")
  [ -n "$vars_to_remove" ] && cmd+=(--remove-env-vars "$vars_to_remove")

  echo -e "${BLUE}Deploying to Cloud Run...${NC}"
  echo "  Project: $GCP_PROJECT"
  echo "  Service: $GCP_SERVICE"
  echo "  Region:  $GCP_REGION"
  echo ""

  # Execute command directly from array (no eval needed)
  "${cmd[@]}"
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Project:  $GCP_PROJECT"
  echo "Service:  $GCP_SERVICE"
  echo "Region:   $GCP_REGION"
}
