#!/bin/bash
# Fly.io Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Fly.io"
PROVIDER_ID="flyio"

# Default configuration
: "${FLY_APP:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/fly.toml" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v fly &> /dev/null && ! command -v flyctl &> /dev/null; then
    echo -e "${RED}Error: Fly CLI (flyctl) not found${NC}" >&2
    echo "  Install from: https://fly.io/docs/hands-on/install-flyctl/" >&2
    errors=1
  fi

  # Try to get app name from fly.toml if not set
  if [ -z "$FLY_APP" ] && [ -f "${PROJECT_DIR}/fly.toml" ]; then
    FLY_APP=$(grep "^app" "${PROJECT_DIR}/fly.toml" | head -1 | cut -d'"' -f2 | cut -d"'" -f2)
  fi

  if [ -z "$FLY_APP" ]; then
    echo -e "${RED}Error: FLY_APP not set${NC}" >&2
    echo "  Set FLY_APP or add 'app' to fly.toml" >&2
    errors=1
  fi

  return $errors
}

# Get fly command (flyctl or fly)
fly_cmd() {
  if command -v flyctl &> /dev/null; then
    echo "flyctl"
  else
    echo "fly"
  fi
}

# Check if app exists
service_exists() {
  $(fly_cmd) apps list 2>/dev/null | grep -q "$FLY_APP"
}

# Fetch live environment variables
fetch_live_env() {
  $(fly_cmd) secrets list --app "$FLY_APP" 2>/dev/null | \
    tail -n +2 | \
    awk '{print $1"=[REDACTED]"}' || true

  # Note: Fly.io doesn't expose secret values, only names
}

# Fetch live secrets
fetch_live_secrets() {
  $(fly_cmd) secrets list --app "$FLY_APP" 2>/dev/null | \
    tail -n +2 | \
    awk '{print $1}' || true
}

# Deploy to Fly.io
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Fly.io...${NC}"
  echo "  App: $FLY_APP"
  echo ""

  local fly=$(fly_cmd)
  cd "$source_dir"

  # Set secrets (Fly uses secrets for env vars)
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting secrets...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      echo "$value" | $fly secrets set "$key" --app "$FLY_APP" --stage
    done
  fi

  # Remove secrets
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing secrets...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      $fly secrets unset "$key" --app "$FLY_APP" --stage 2>/dev/null || true
    done
  fi

  # Deploy (this also applies staged secrets)
  echo -e "${BLUE}Deploying application...${NC}"
  $fly deploy --app "$FLY_APP"
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "App:      $FLY_APP"
}
