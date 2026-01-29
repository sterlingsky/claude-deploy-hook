#!/bin/bash
# Cloudflare Workers Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect

# Provider metadata
PROVIDER_NAME="Cloudflare Workers"
PROVIDER_ID="cloudflare-workers"

# Default configuration
: "${CF_ACCOUNT_ID:=}"
: "${CF_API_TOKEN:=}"
: "${CF_WORKER_NAME:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/wrangler.toml" ] && return 0
  [ -f "${PROJECT_DIR}/wrangler.json" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  # Check wrangler CLI
  if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}Error: wrangler CLI not found${NC}" >&2
    echo "  Install with: npm install -g wrangler" >&2
    errors=1
  fi

  # Try to get worker name from wrangler.toml if not set
  if [ -z "$CF_WORKER_NAME" ] && [ -f "${PROJECT_DIR}/wrangler.toml" ]; then
    CF_WORKER_NAME=$(grep "^name" "${PROJECT_DIR}/wrangler.toml" | head -1 | cut -d'"' -f2 | cut -d"'" -f2)
  fi

  if [ -z "$CF_WORKER_NAME" ]; then
    echo -e "${RED}Error: CF_WORKER_NAME not set${NC}" >&2
    echo "  Set CF_WORKER_NAME or add 'name' to wrangler.toml" >&2
    errors=1
  fi

  return $errors
}

# Check if worker exists
service_exists() {
  wrangler deployments list 2>/dev/null | grep -q "Deployment"
}

# Fetch live environment variables
fetch_live_env() {
  # Parse vars from wrangler.toml [vars] section
  if [ -f "${PROJECT_DIR}/wrangler.toml" ]; then
    awk '/^\[vars\]/,/^\[/' "${PROJECT_DIR}/wrangler.toml" | \
      grep "=" | \
      grep -v "^\[" | \
      sed 's/[[:space:]]*=[[:space:]]*/=/' | \
      sed 's/"//g' | \
      sed "s/'//g" || true
  fi

  # Also try to get from deployed worker via API if token available
  if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ]; then
    curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$CF_WORKER_NAME/settings" \
      -H "Authorization: Bearer $CF_API_TOKEN" | \
      jq -r '.result.bindings // [] | map(select(.type == "plain_text")) | map("\(.name)=\(.text)") | .[]' 2>/dev/null || true
  fi
}

# Fetch live secrets
fetch_live_secrets() {
  # Secrets in Cloudflare are listed as secret_text bindings
  if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ]; then
    curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/workers/scripts/$CF_WORKER_NAME/settings" \
      -H "Authorization: Bearer $CF_API_TOKEN" | \
      jq -r '.result.bindings // [] | map(select(.type == "secret_text")) | map(.name) | .[]' 2>/dev/null || true
  fi
}

# Deploy to Cloudflare Workers
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Cloudflare Workers...${NC}"
  echo "  Worker: $CF_WORKER_NAME"
  echo ""

  cd "$source_dir"

  # Set secrets (vars are typically in wrangler.toml)
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting secrets...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      echo "$value" | wrangler secret put "$key" 2>/dev/null || \
        echo -e "${YELLOW}Warning: Could not set $key (may need to add to wrangler.toml [vars])${NC}"
    done
  fi

  # Delete secrets
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing secrets...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      wrangler secret delete "$key" --force 2>/dev/null || true
    done
  fi

  # Deploy
  wrangler deploy
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Worker:   $CF_WORKER_NAME"
  [ -n "$CF_ACCOUNT_ID" ] && echo "Account:  $CF_ACCOUNT_ID"
}
