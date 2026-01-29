#!/bin/bash
# GCP Firebase Functions Provider
# Supports both Gen 1 (firebase config) and Gen 2 (env vars)
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect

# Provider metadata
PROVIDER_NAME="GCP Firebase Functions"
PROVIDER_ID="gcp-firebase-functions"

# Default configuration
: "${GCP_PROJECT:=${GOOGLE_CLOUD_PROJECT:-}}"
: "${FIREBASE_FUNCTIONS_GEN:=2}"  # 1 or 2

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/firebase.json" ] && return 0
  [ -d "${PROJECT_DIR}/functions" ] && return 0
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

  # Check firebase CLI
  if ! command -v firebase &> /dev/null; then
    echo -e "${RED}Error: firebase CLI not found${NC}" >&2
    echo "  Install with: npm install -g firebase-tools" >&2
    errors=1
  fi

  return $errors
}

# Check if functions are deployed
service_exists() {
  firebase functions:list --project "$GCP_PROJECT" 2>/dev/null | grep -q "function"
}

# Fetch live environment variables
# Gen 1: firebase functions:config:get
# Gen 2: gcloud functions describe
fetch_live_env() {
  if [ "$FIREBASE_FUNCTIONS_GEN" = "1" ]; then
    # Gen 1: Convert nested config to flat KEY=VALUE
    local config
    config=$(firebase functions:config:get --project "$GCP_PROJECT" 2>/dev/null) || return 1

    # Convert JSON like {"service":{"key":"value"}} to SERVICE_KEY=value
    echo "$config" | jq -r '
      . as $root |
      paths(scalars) as $p |
      ($p | map(ascii_upcase) | join("_")) + "=" + ($root | getpath($p) | tostring)
    ' 2>/dev/null || true
  else
    # Gen 2: Get from deployed function (pick first function)
    local function_name
    function_name=$(gcloud functions list --project "$GCP_PROJECT" --format="value(name)" --limit=1 2>/dev/null)

    if [ -n "$function_name" ]; then
      gcloud functions describe "$function_name" \
        --project "$GCP_PROJECT" \
        --format json 2>/dev/null | jq -r '
        .serviceConfig.environmentVariables // {} |
        to_entries |
        map("\(.key)=\(.value)") |
        .[]' 2>/dev/null || true
    fi
  fi
}

# Fetch live secrets
fetch_live_secrets() {
  # List secrets used by functions
  local function_name
  function_name=$(gcloud functions list --project "$GCP_PROJECT" --format="value(name)" --limit=1 2>/dev/null)

  if [ -n "$function_name" ]; then
    gcloud functions describe "$function_name" \
      --project "$GCP_PROJECT" \
      --format json 2>/dev/null | jq -r '
      .serviceConfig.secretEnvironmentVariables // [] |
      map("\(.key)=\(.secret):\(.version // "latest")") |
      .[]' 2>/dev/null || true
  fi
}

# Deploy Firebase Functions
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying Firebase Functions...${NC}"
  echo "  Project: $GCP_PROJECT"
  echo "  Gen:     $FIREBASE_FUNCTIONS_GEN"
  echo ""

  if [ "$FIREBASE_FUNCTIONS_GEN" = "1" ]; then
    deploy_gen1 "$env_vars" "$vars_to_remove" "$source_dir"
  else
    deploy_gen2 "$env_vars" "$secrets" "$vars_to_remove" "$source_dir"
  fi
}

# Deploy Gen 1 functions (uses firebase config)
deploy_gen1() {
  local env_vars="$1"
  local vars_to_remove="$2"
  local source_dir="$3"

  # Set config values
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting function config...${NC}"
    # Convert KEY=value to key.subkey=value format for firebase
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      # Convert UPPER_CASE to lower.case for firebase config
      config_key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/_/./g')
      firebase functions:config:set "$config_key=$value" --project "$GCP_PROJECT"
    done
  fi

  # Unset removed config values
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing function config...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      config_key=$(echo "$key" | tr '[:upper:]' '[:lower:]' | sed 's/_/./g')
      firebase functions:config:unset "$config_key" --project "$GCP_PROJECT" 2>/dev/null || true
    done
  fi

  # Deploy functions
  firebase deploy --only functions --project "$GCP_PROJECT"
}

# Deploy Gen 2 functions (uses env vars)
deploy_gen2() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  # Write env vars to .env file for firebase deploy
  local functions_dir="${source_dir}/functions"
  [ ! -d "$functions_dir" ] && functions_dir="$source_dir"

  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Writing .env for deployment...${NC}"
    # Backup existing .env
    [ -f "$functions_dir/.env" ] && cp "$functions_dir/.env" "$functions_dir/.env.backup"

    # Write new .env
    echo "# Auto-generated by deploy hook" > "$functions_dir/.env"
    echo "$env_vars" | tr ',' '\n' >> "$functions_dir/.env"
  fi

  # Deploy with secrets if specified
  local deploy_cmd="firebase deploy --only functions --project $GCP_PROJECT"

  firebase deploy --only functions --project "$GCP_PROJECT"
  local result=$?

  # Restore backup if exists
  if [ -f "$functions_dir/.env.backup" ]; then
    mv "$functions_dir/.env.backup" "$functions_dir/.env"
  fi

  return $result
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Project:  $GCP_PROJECT"
  echo "Gen:      $FIREBASE_FUNCTIONS_GEN"
}
