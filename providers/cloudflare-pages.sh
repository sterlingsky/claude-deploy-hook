#!/bin/bash
# Cloudflare Pages Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect

# Provider metadata
PROVIDER_NAME="Cloudflare Pages"
PROVIDER_ID="cloudflare-pages"

# Default configuration
: "${CF_ACCOUNT_ID:=}"
: "${CF_API_TOKEN:=}"
: "${CF_PAGES_PROJECT:=}"
: "${CF_PAGES_BRANCH:=main}"

# Detect if this provider should be used
detect() {
  # Pages projects often have wrangler.toml with pages_build_output_dir
  if [ -f "${PROJECT_DIR}/wrangler.toml" ]; then
    grep -q "pages_build_output_dir" "${PROJECT_DIR}/wrangler.toml" && return 0
  fi
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v wrangler &> /dev/null; then
    echo -e "${RED}Error: wrangler CLI not found${NC}" >&2
    echo "  Install with: npm install -g wrangler" >&2
    errors=1
  fi

  if [ -z "$CF_PAGES_PROJECT" ]; then
    # Try to get from wrangler.toml
    if [ -f "${PROJECT_DIR}/wrangler.toml" ]; then
      CF_PAGES_PROJECT=$(grep "^name" "${PROJECT_DIR}/wrangler.toml" | head -1 | cut -d'"' -f2 | cut -d"'" -f2)
    fi
  fi

  if [ -z "$CF_PAGES_PROJECT" ]; then
    echo -e "${RED}Error: CF_PAGES_PROJECT not set${NC}" >&2
    errors=1
  fi

  return $errors
}

service_exists() {
  wrangler pages project list 2>/dev/null | grep -q "$CF_PAGES_PROJECT"
}

# Fetch live environment variables
fetch_live_env() {
  if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ]; then
    # Get production env vars
    curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT" \
      -H "Authorization: Bearer $CF_API_TOKEN" | \
      jq -r '.result.deployment_configs.production.env_vars // {} | to_entries | map("\(.key)=\(.value.value // .value)") | .[]' 2>/dev/null || true
  fi
}

fetch_live_secrets() {
  # Pages secrets are env vars marked as secret
  if [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ]; then
    curl -s "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT" \
      -H "Authorization: Bearer $CF_API_TOKEN" | \
      jq -r '.result.deployment_configs.production.env_vars // {} | to_entries | map(select(.value.type == "secret_text")) | map(.key) | .[]' 2>/dev/null || true
  fi
}

deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Cloudflare Pages...${NC}"
  echo "  Project: $CF_PAGES_PROJECT"
  echo "  Branch:  $CF_PAGES_BRANCH"
  echo ""

  cd "$source_dir"

  # Note: Cloudflare Pages env vars must be set via dashboard or API
  # wrangler pages deploy doesn't support --var flags yet
  if [ -n "$env_vars" ] && [ -n "$CF_API_TOKEN" ] && [ -n "$CF_ACCOUNT_ID" ]; then
    echo -e "${BLUE}Setting environment variables via API...${NC}"

    # Build JSON payload for env vars
    local env_json="{"
    local first=true
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      [ "$first" = true ] && first=false || env_json="$env_json,"
      env_json="$env_json\"$key\":{\"value\":\"$value\"}"
    done
    env_json="$env_json}"

    curl -s -X PATCH "https://api.cloudflare.com/client/v4/accounts/$CF_ACCOUNT_ID/pages/projects/$CF_PAGES_PROJECT" \
      -H "Authorization: Bearer $CF_API_TOKEN" \
      -H "Content-Type: application/json" \
      --data "{\"deployment_configs\":{\"production\":{\"env_vars\":$env_json}}}" > /dev/null
  fi

  # Deploy
  wrangler pages deploy --project-name "$CF_PAGES_PROJECT" --branch "$CF_PAGES_BRANCH"
}

print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Project:  $CF_PAGES_PROJECT"
  echo "Branch:   $CF_PAGES_BRANCH"
}
