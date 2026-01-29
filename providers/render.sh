#!/bin/bash
# Render Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Render"
PROVIDER_ID="render"

# Default configuration
: "${RENDER_SERVICE_ID:=}"
: "${RENDER_API_KEY:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/render.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/render.yml" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if [ -z "$RENDER_SERVICE_ID" ]; then
    echo -e "${RED}Error: RENDER_SERVICE_ID not set${NC}" >&2
    echo "  Set RENDER_SERVICE_ID from your Render dashboard" >&2
    errors=1
  fi

  if [ -z "$RENDER_API_KEY" ]; then
    echo -e "${RED}Error: RENDER_API_KEY not set${NC}" >&2
    echo "  Get API key from: https://dashboard.render.com/u/settings#api-keys" >&2
    errors=1
  fi

  return $errors
}

# Check if service exists
service_exists() {
  curl -s "https://api.render.com/v1/services/$RENDER_SERVICE_ID" \
    -H "Authorization: Bearer $RENDER_API_KEY" | \
    jq -e '.id' &>/dev/null
}

# Fetch live environment variables
fetch_live_env() {
  curl -s "https://api.render.com/v1/services/$RENDER_SERVICE_ID/env-vars" \
    -H "Authorization: Bearer $RENDER_API_KEY" 2>/dev/null | jq -r '
    . // [] |
    map(select(.value != null)) |
    map("\(.key)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Fetch live secrets
fetch_live_secrets() {
  # Render marks some env vars as "generateValue" which are secrets
  curl -s "https://api.render.com/v1/services/$RENDER_SERVICE_ID/env-vars" \
    -H "Authorization: Bearer $RENDER_API_KEY" 2>/dev/null | jq -r '
    . // [] |
    map(select(.generateValue != null)) |
    map(.key) |
    .[]' 2>/dev/null || true
}

# Deploy to Render
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Render...${NC}"
  echo "  Service ID: $RENDER_SERVICE_ID"
  echo ""

  # Update environment variables
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Updating environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"

      # Upsert env var
      curl -s -X PUT "https://api.render.com/v1/services/$RENDER_SERVICE_ID/env-vars/$key" \
        -H "Authorization: Bearer $RENDER_API_KEY" \
        -H "Content-Type: application/json" \
        -d "{\"value\": \"$value\"}" > /dev/null
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      curl -s -X DELETE "https://api.render.com/v1/services/$RENDER_SERVICE_ID/env-vars/$key" \
        -H "Authorization: Bearer $RENDER_API_KEY" > /dev/null
    done
  fi

  # Trigger deploy
  echo -e "${BLUE}Triggering deployment...${NC}"
  local deploy_response
  deploy_response=$(curl -s -X POST "https://api.render.com/v1/services/$RENDER_SERVICE_ID/deploys" \
    -H "Authorization: Bearer $RENDER_API_KEY" \
    -H "Content-Type: application/json" \
    -d '{"clearCache": false}')

  local deploy_id
  deploy_id=$(echo "$deploy_response" | jq -r '.id // empty')

  if [ -n "$deploy_id" ]; then
    echo "  Deploy ID: $deploy_id"
    echo "  View at: https://dashboard.render.com/web/$RENDER_SERVICE_ID/deploys/$deploy_id"
  else
    echo -e "${RED}Error: Failed to trigger deployment${NC}"
    echo "$deploy_response"
    return 1
  fi
}

# Print provider-specific info
print_info() {
  echo "Provider:   $PROVIDER_NAME"
  echo "Service ID: $RENDER_SERVICE_ID"
}
