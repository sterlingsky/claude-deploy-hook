#!/bin/bash
# Railway Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect

# Provider metadata
PROVIDER_NAME="Railway"
PROVIDER_ID="railway"

# Default configuration
: "${RAILWAY_PROJECT:=}"
: "${RAILWAY_SERVICE:=}"
: "${RAILWAY_ENVIRONMENT:=production}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/railway.json" ] && return 0
  [ -f "${PROJECT_DIR}/railway.toml" ] && return 0
  [ -f "${PROJECT_DIR}/.railway" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  # Check railway CLI
  if ! command -v railway &> /dev/null; then
    echo -e "${RED}Error: railway CLI not found${NC}" >&2
    echo "  Install with: npm install -g @railway/cli" >&2
    echo "  Or: brew install railway" >&2
    errors=1
  fi

  # Check if logged in
  if ! railway whoami &>/dev/null; then
    echo -e "${RED}Error: Not logged in to Railway${NC}" >&2
    echo "  Run: railway login" >&2
    errors=1
  fi

  return $errors
}

# Check if project is linked
service_exists() {
  railway status 2>/dev/null | grep -q "Project"
}

# Fetch live environment variables
fetch_live_env() {
  # Railway CLI can list env vars
  railway variables 2>/dev/null | \
    grep "=" | \
    grep -v "^>" || true
}

# Fetch live secrets (Railway doesn't distinguish - all are encrypted)
fetch_live_secrets() {
  # Railway treats all vars as secrets (encrypted at rest)
  # Return empty as we handle all via fetch_live_env
  echo ""
}

# Deploy to Railway
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Railway...${NC}"
  echo "  Environment: $RAILWAY_ENVIRONMENT"
  echo ""

  cd "$source_dir"

  # Set environment variables
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      railway variables set "$key=$value" 2>/dev/null || \
        echo -e "${YELLOW}Warning: Could not set $key${NC}"
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      railway variables delete "$key" --yes 2>/dev/null || true
    done
  fi

  # Deploy
  railway up --detach
}

# Print provider-specific info
print_info() {
  echo "Provider:    $PROVIDER_NAME"
  echo "Environment: $RAILWAY_ENVIRONMENT"

  # Try to get project info
  local project_info
  project_info=$(railway status 2>/dev/null | grep "Project:" | cut -d':' -f2 | tr -d ' ')
  [ -n "$project_info" ] && echo "Project:     $project_info"
}
