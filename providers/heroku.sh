#!/bin/bash
# Heroku Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Heroku"
PROVIDER_ID="heroku"

# Default configuration
: "${HEROKU_APP:=}"
: "${HEROKU_REMOTE:=heroku}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/Procfile" ] && return 0
  [ -f "${PROJECT_DIR}/app.json" ] && return 0
  [ -f "${PROJECT_DIR}/heroku.yml" ] && return 0
  # Check for heroku git remote
  git remote -v 2>/dev/null | grep -q "heroku" && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v heroku &> /dev/null; then
    echo -e "${RED}Error: Heroku CLI not found${NC}" >&2
    echo "  Install from: https://devcenter.heroku.com/articles/heroku-cli" >&2
    errors=1
  fi

  # Try to get app name from git remote if not set
  if [ -z "$HEROKU_APP" ]; then
    HEROKU_APP=$(git remote -v 2>/dev/null | grep heroku | head -1 | sed 's/.*heroku.com[:/]\([^.]*\).*/\1/')
  fi

  if [ -z "$HEROKU_APP" ]; then
    echo -e "${RED}Error: HEROKU_APP not set${NC}" >&2
    echo "  Set HEROKU_APP or link a Heroku remote" >&2
    errors=1
  fi

  return $errors
}

# Check if app exists
service_exists() {
  heroku apps:info --app "$HEROKU_APP" &>/dev/null
}

# Fetch live environment variables
fetch_live_env() {
  heroku config --app "$HEROKU_APP" --shell 2>/dev/null | \
    grep -v "^#" | \
    grep "=" || true
}

# Fetch live secrets (Heroku treats all config vars the same)
fetch_live_secrets() {
  # Heroku doesn't distinguish secrets from env vars
  echo ""
}

# Deploy to Heroku
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Heroku...${NC}"
  echo "  App: $HEROKU_APP"
  echo ""

  cd "$source_dir"

  # Set environment variables
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting config vars...${NC}"
    local config_vars=""
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      [ -n "$config_vars" ] && config_vars="$config_vars "
      config_vars="$config_vars$pair"
    done

    heroku config:set $config_vars --app "$HEROKU_APP"
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing config vars...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    heroku config:unset "${KEYS[@]}" --app "$HEROKU_APP"
  fi

  # Deploy via git push
  echo -e "${BLUE}Deploying code...${NC}"
  if git remote | grep -q "$HEROKU_REMOTE"; then
    git push "$HEROKU_REMOTE" HEAD:main
  else
    heroku git:remote --app "$HEROKU_APP"
    git push heroku HEAD:main
  fi
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "App:      $HEROKU_APP"
}
