#!/bin/bash
# Vercel Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect

# Provider metadata
PROVIDER_NAME="Vercel"
PROVIDER_ID="vercel"

# Default configuration
: "${VERCEL_PROJECT:=}"
: "${VERCEL_ORG:=}"
: "${VERCEL_ENV:=production}"  # production, preview, development

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/vercel.json" ] && return 0
  [ -f "${PROJECT_DIR}/.vercel/project.json" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  # Check vercel CLI
  if ! command -v vercel &> /dev/null; then
    echo -e "${RED}Error: vercel CLI not found${NC}" >&2
    echo "  Install with: npm install -g vercel" >&2
    errors=1
  fi

  # Try to get project from .vercel/project.json if not set
  if [ -z "$VERCEL_PROJECT" ] && [ -f "${PROJECT_DIR}/.vercel/project.json" ]; then
    VERCEL_PROJECT=$(jq -r '.projectId // empty' "${PROJECT_DIR}/.vercel/project.json" 2>/dev/null)
  fi

  return $errors
}

# Check if project exists
service_exists() {
  vercel inspect 2>/dev/null | grep -q "Deployment"
}

# Fetch live environment variables
fetch_live_env() {
  # Vercel CLI can list env vars
  vercel env ls "$VERCEL_ENV" 2>/dev/null | \
    grep -v "^>" | \
    grep -v "^$" | \
    grep -v "Downloading" | \
    awk '{print $1"="$3}' | \
    grep "=" || true
}

# Fetch live secrets (Vercel treats secrets as encrypted env vars)
fetch_live_secrets() {
  # Vercel env vars marked as "Encrypted" are secrets
  vercel env ls "$VERCEL_ENV" 2>/dev/null | \
    grep "Encrypted" | \
    awk '{print $1}' || true
}

# Deploy to Vercel
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Vercel...${NC}"
  echo "  Environment: $VERCEL_ENV"
  echo ""

  # Set environment variables
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Setting environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      echo "$value" | vercel env add "$key" "$VERCEL_ENV" --force 2>/dev/null || \
        echo -e "${YELLOW}Warning: Could not set $key${NC}"
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      vercel env rm "$key" "$VERCEL_ENV" --yes 2>/dev/null || true
    done
  fi

  # Deploy
  local deploy_cmd="vercel"
  [ "$VERCEL_ENV" = "production" ] && deploy_cmd="$deploy_cmd --prod"

  cd "$source_dir" && $deploy_cmd
}

# Print provider-specific info
print_info() {
  echo "Provider:    $PROVIDER_NAME"
  echo "Project:     ${VERCEL_PROJECT:-auto-detect}"
  echo "Environment: $VERCEL_ENV"
}
