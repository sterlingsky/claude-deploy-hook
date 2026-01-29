#!/bin/bash
# Netlify Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Netlify"
PROVIDER_ID="netlify"

# Default configuration
: "${NETLIFY_SITE_ID:=}"
: "${NETLIFY_AUTH_TOKEN:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/netlify.toml" ] && return 0
  [ -f "${PROJECT_DIR}/.netlify/state.json" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v netlify &> /dev/null; then
    echo -e "${RED}Error: Netlify CLI not found${NC}" >&2
    echo "  Install with: npm install -g netlify-cli" >&2
    errors=1
  fi

  # Try to get site ID from state file
  if [ -z "$NETLIFY_SITE_ID" ] && [ -f "${PROJECT_DIR}/.netlify/state.json" ]; then
    NETLIFY_SITE_ID=$(jq -r '.siteId // empty' "${PROJECT_DIR}/.netlify/state.json" 2>/dev/null)
  fi

  if [ -z "$NETLIFY_SITE_ID" ]; then
    echo -e "${RED}Error: NETLIFY_SITE_ID not set${NC}" >&2
    echo "  Run 'netlify link' or set NETLIFY_SITE_ID" >&2
    errors=1
  fi

  return $errors
}

# Check if site exists
service_exists() {
  netlify status 2>/dev/null | grep -q "Site"
}

# Fetch live environment variables
fetch_live_env() {
  netlify env:list --json 2>/dev/null | jq -r '
    . // [] |
    map(select(.value != null)) |
    map("\(.key)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Fetch live secrets
fetch_live_secrets() {
  # Netlify marks some vars as "secret" in the UI
  # The API doesn't expose which are secrets, so return empty
  echo ""
}

# Deploy to Netlify
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Netlify...${NC}"
  echo "  Site ID: $NETLIFY_SITE_ID"
  echo ""

  cd "$source_dir"

  # Set environment variables
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      netlify env:set "$key" "$value" 2>/dev/null || \
        echo -e "${YELLOW}Warning: Could not set $key${NC}"
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      netlify env:unset "$key" 2>/dev/null || true
    done
  fi

  # Deploy
  echo -e "${BLUE}Deploying site...${NC}"
  netlify deploy --prod
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Site ID:  $NETLIFY_SITE_ID"
}
