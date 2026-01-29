#!/bin/bash
# GCP Cloud Functions Provider (standalone, not Firebase)
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="GCP Cloud Functions"
PROVIDER_ID="gcp-cloud-functions"

# Default configuration
: "${GCP_PROJECT:=${GOOGLE_CLOUD_PROJECT:-}}"
: "${GCP_REGION:=${CLOUD_FUNCTIONS_REGION:-us-central1}}"
: "${GCP_FUNCTION_NAME:=${CLOUD_FUNCTION_NAME:-}}"
: "${GCP_FUNCTION_GEN:=2}"  # 1 or 2
: "${GCP_FUNCTION_RUNTIME:=nodejs20}"

# Detect if this provider should be used
# Returns 0 if detected, 1 otherwise
detect() {
  # Check for Cloud Functions specific files (not Firebase)
  # Don't detect if firebase.json exists (use firebase provider instead)
  [ -f "${PROJECT_DIR}/firebase.json" ] && return 1

  # Check for standalone Cloud Functions markers
  [ -f "${PROJECT_DIR}/cloudfunctions.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/.gcloudignore" ] && [ -f "${PROJECT_DIR}/index.js" ] && return 0
  [ -f "${PROJECT_DIR}/.gcloudignore" ] && [ -f "${PROJECT_DIR}/main.py" ] && return 0
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

  if [ -z "$GCP_FUNCTION_NAME" ]; then
    echo -e "${RED}Error: GCP_FUNCTION_NAME not set${NC}" >&2
    echo "  Set CLOUD_FUNCTION_NAME or GCP_FUNCTION_NAME environment variable" >&2
    errors=1
  fi

  # Check gcloud CLI
  if ! command -v gcloud &> /dev/null; then
    echo -e "${RED}Error: gcloud CLI not found${NC}" >&2
    echo "  Install from: https://cloud.google.com/sdk/docs/install" >&2
    errors=1
  fi

  return $errors
}

# Check if function exists
service_exists() {
  if [ "$GCP_FUNCTION_GEN" = "1" ]; then
    gcloud functions describe "$GCP_FUNCTION_NAME" \
      --project "$GCP_PROJECT" \
      --region "$GCP_REGION" \
      --format "value(name)" 2>/dev/null
  else
    gcloud functions describe "$GCP_FUNCTION_NAME" \
      --project "$GCP_PROJECT" \
      --region "$GCP_REGION" \
      --gen2 \
      --format "value(name)" 2>/dev/null
  fi
}

# Fetch live environment variables
# Output: KEY=VALUE per line to stdout
fetch_live_env() {
  local config

  if [ "$GCP_FUNCTION_GEN" = "1" ]; then
    config=$(gcloud functions describe "$GCP_FUNCTION_NAME" \
      --project "$GCP_PROJECT" \
      --region "$GCP_REGION" \
      --format json 2>/dev/null) || return 1

    echo "$config" | jq -r '
      .environmentVariables // {} |
      to_entries |
      map("\(.key)=\(.value)") |
      .[]' 2>/dev/null || true
  else
    config=$(gcloud functions describe "$GCP_FUNCTION_NAME" \
      --project "$GCP_PROJECT" \
      --region "$GCP_REGION" \
      --gen2 \
      --format json 2>/dev/null) || return 1

    echo "$config" | jq -r '
      .serviceConfig.environmentVariables // {} |
      to_entries |
      map("\(.key)=\(.value)") |
      .[]' 2>/dev/null || true
  fi
}

# Fetch live secrets
# Output: KEY=SECRET:VERSION per line to stdout
fetch_live_secrets() {
  local config

  if [ "$GCP_FUNCTION_GEN" = "1" ]; then
    # Gen 1 doesn't have native secret support
    echo ""
  else
    config=$(gcloud functions describe "$GCP_FUNCTION_NAME" \
      --project "$GCP_PROJECT" \
      --region "$GCP_REGION" \
      --gen2 \
      --format json 2>/dev/null) || return 1

    echo "$config" | jq -r '
      .serviceConfig.secretEnvironmentVariables // [] |
      map("\(.key)=\(.secret):\(.version // "latest")") |
      .[]' 2>/dev/null || true
  fi
}

# Deploy Cloud Function
# Args: env_vars secrets vars_to_remove source_dir
# SECURITY: Uses array-based command construction instead of eval
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying Cloud Function...${NC}"
  echo "  Project:  $GCP_PROJECT"
  echo "  Function: $GCP_FUNCTION_NAME"
  echo "  Region:   $GCP_REGION"
  echo "  Gen:      $GCP_FUNCTION_GEN"
  echo ""

  # Build command as array to avoid eval
  local -a cmd=(
    gcloud functions deploy "$GCP_FUNCTION_NAME"
    --project "$GCP_PROJECT"
    --region "$GCP_REGION"
    --source "$source_dir"
    --runtime "$GCP_FUNCTION_RUNTIME"
  )

  # Add gen2 flag if needed
  [ "$GCP_FUNCTION_GEN" = "2" ] && cmd+=(--gen2)

  # Add optional arguments
  [ -n "$env_vars" ] && cmd+=(--set-env-vars "$env_vars")
  [ -n "$secrets" ] && cmd+=(--set-secrets "$secrets")
  [ -n "$vars_to_remove" ] && cmd+=(--remove-env-vars "$vars_to_remove")

  # Add trigger (default to HTTP)
  : "${GCP_FUNCTION_TRIGGER:=http}"
  case "$GCP_FUNCTION_TRIGGER" in
    http)
      cmd+=(--trigger-http --allow-unauthenticated)
      ;;
    pubsub)
      [ -n "$GCP_FUNCTION_TOPIC" ] && cmd+=(--trigger-topic "$GCP_FUNCTION_TOPIC")
      ;;
    storage)
      [ -n "$GCP_FUNCTION_BUCKET" ] && cmd+=(--trigger-bucket "$GCP_FUNCTION_BUCKET")
      ;;
    *)
      cmd+=(--trigger-http)
      ;;
  esac

  # Execute command directly from array (no eval needed)
  "${cmd[@]}"
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Project:  $GCP_PROJECT"
  echo "Function: $GCP_FUNCTION_NAME"
  echo "Region:   $GCP_REGION"
  echo "Gen:      $GCP_FUNCTION_GEN"
  echo "Runtime:  $GCP_FUNCTION_RUNTIME"
}
