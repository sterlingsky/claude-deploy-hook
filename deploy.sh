#!/bin/bash
# Claude Deploy Hook - Universal Deployment with Smart Env Var Management
# https://github.com/sterlingsky/claude-deploy-hook
#
# SECURITY FEATURES:
# - Never prints env var values (only key names and lengths)
# - Secure temp files with 600 permissions
# - Shred temp files on cleanup
# - --strict mode for CI/CD (fails on unknown vars)
# - No eval of user-controlled strings

set -e

# Determine script location (works even when symlinked)
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")")" && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(pwd)}"

# Create secure temp directory
TEMP_DIR=$(mktemp -d)
chmod 700 "$TEMP_DIR"

# Source shared library
if [ -f "$SCRIPT_DIR/lib/env-compare.sh" ]; then
  source "$SCRIPT_DIR/lib/env-compare.sh"
else
  echo "Error: lib/env-compare.sh not found" >&2
  exit 1
fi

# Secure cleanup - shred temp files if possible
cleanup() {
  if [ -d "$TEMP_DIR" ]; then
    # Securely delete all files in temp dir
    for f in "$TEMP_DIR"/*; do
      [ -f "$f" ] && secure_delete "$f"
    done
    rmdir "$TEMP_DIR" 2>/dev/null || rm -rf "$TEMP_DIR"
  fi
}
trap cleanup EXIT INT TERM

# Show usage
usage() {
  cat << 'EOF'
Claude Deploy Hook - Universal Deployment with Smart Env Var Management

Usage: deploy.sh [OPTIONS]

Options:
  --provider=NAME    Use specific provider (auto-detects if not set)
  --list-providers   List available providers
  --dry-run          Show what would be deployed without deploying
  --env-file=PATH    Use specific env file (auto-detects if not set)
  --strict           Fail if there are env vars to remove (for CI/CD)
  --help             Show this help

Environment Variables:
  DEPLOY_PROVIDER    Same as --provider
  DEPLOY_ENV_FILE    Same as --env-file
  DEPLOY_DRY_RUN     Set to 1 for dry run
  DEPLOY_STRICT      Set to 1 for strict mode

Security:
  - Env var values are NEVER printed (only key names and lengths)
  - Temp files are created with 600 permissions and shredded on exit
  - Use --strict in CI/CD to fail on unknown vars instead of keeping them

Examples:
  deploy.sh                              # Auto-detect and deploy
  deploy.sh --provider=gcp-cloud-run     # Use specific provider
  deploy.sh --dry-run                    # Preview changes
  deploy.sh --strict                     # Fail on unknown vars (CI/CD)

For provider-specific variables, run: deploy.sh --list-providers
EOF
}

# List available providers
list_providers() {
  echo -e "${BLUE}Available Providers:${NC}"
  echo ""
  for provider_file in "$SCRIPT_DIR/providers/"*.sh; do
    [ -f "$provider_file" ] || continue
    (
      source "$provider_file"
      echo -e "${GREEN}$PROVIDER_ID${NC}"
      echo "  Name: $PROVIDER_NAME"
      if declare -f print_info > /dev/null; then
        print_info 2>/dev/null | sed 's/^/  /'
      fi
      echo ""
    )
  done
}

# Auto-detect provider based on project files
detect_provider() {
  for provider_file in "$SCRIPT_DIR/providers/"*.sh; do
    [ -f "$provider_file" ] || continue
    (
      source "$provider_file"
      if declare -f detect > /dev/null && detect; then
        echo "$PROVIDER_ID"
        exit 0
      fi
    ) && return 0
  done
  return 1
}

# Load provider
load_provider() {
  local provider_id="$1"
  local provider_file="$SCRIPT_DIR/providers/${provider_id}.sh"

  if [ ! -f "$provider_file" ]; then
    echo -e "${RED}Error: Provider '$provider_id' not found${NC}" >&2
    echo "Available providers:" >&2
    ls "$SCRIPT_DIR/providers/"*.sh 2>/dev/null | xargs -n1 basename | sed 's/\.sh$//' | sed 's/^/  /' >&2
    return 1
  fi

  source "$provider_file"
}

# Parse arguments
PROVIDER=""
DRY_RUN="${DEPLOY_DRY_RUN:-0}"
ENV_FILE="${DEPLOY_ENV_FILE:-}"
STRICT_MODE="${DEPLOY_STRICT:-0}"

for arg in "$@"; do
  case $arg in
    --provider=*)
      PROVIDER="${arg#*=}"
      ;;
    --list-providers)
      list_providers
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      ;;
    --env-file=*)
      ENV_FILE="${arg#*=}"
      ;;
    --strict)
      STRICT_MODE=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo -e "${RED}Unknown option: $arg${NC}" >&2
      usage
      exit 1
      ;;
  esac
done

# Export STRICT_MODE for use in env-compare.sh
export STRICT_MODE

# Header
echo -e "${BLUE}╔══════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║    Claude Deploy Hook                    ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════╝${NC}"
echo ""

[ "$STRICT_MODE" = "1" ] && echo -e "${YELLOW}STRICT MODE enabled - will fail on unknown vars${NC}" && echo ""

# Detect or use specified provider
if [ -z "$PROVIDER" ]; then
  PROVIDER="${DEPLOY_PROVIDER:-}"
fi

if [ -z "$PROVIDER" ]; then
  echo -e "${CYAN}Auto-detecting provider...${NC}"
  PROVIDER=$(detect_provider) || {
    echo -e "${RED}Could not auto-detect provider${NC}" >&2
    echo ""
    echo "Use --provider=NAME to specify, or --list-providers to see options" >&2
    exit 1
  }
  echo -e "${GREEN}Detected: $PROVIDER${NC}"
fi

# Load provider
load_provider "$PROVIDER" || exit 1

# Validate provider config
echo ""
if ! validate_config; then
  exit 1
fi

# Print provider info
print_info
echo ""

# Check if service exists
if ! service_exists 2>/dev/null; then
  echo -e "${YELLOW}Service doesn't exist yet. Will create new deployment.${NC}"
  LIVE_ENV_COUNT=0
  touch "$TEMP_DIR/live_env.txt"
  chmod 600 "$TEMP_DIR/live_env.txt"
  LIVE_SECRETS=""
else
  # Fetch live config
  echo -e "${BLUE}Fetching live configuration...${NC}"

  fetch_live_env > "$TEMP_DIR/live_env.txt" 2>/dev/null || touch "$TEMP_DIR/live_env.txt"
  chmod 600 "$TEMP_DIR/live_env.txt"
  LIVE_SECRETS=$(fetch_live_secrets 2>/dev/null || echo "")

  LIVE_ENV_COUNT=$(wc -l < "$TEMP_DIR/live_env.txt" | tr -d ' ')
  LIVE_SECRET_COUNT=$(echo "$LIVE_SECRETS" | tr ',' '\n' | grep -c . 2>/dev/null || echo 0)

  echo -e "${GREEN}Found $LIVE_ENV_COUNT env vars and $LIVE_SECRET_COUNT secrets${NC}"
fi

# Find and parse local env file
if [ -z "$ENV_FILE" ]; then
  ENV_FILE=$(find_local_env_file "$PROJECT_DIR") || {
    echo -e "${YELLOW}No local .env file found. Using live config only.${NC}"
    touch "$TEMP_DIR/local_env.txt"
    chmod 600 "$TEMP_DIR/local_env.txt"
  }
fi

if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  echo -e "${BLUE}Reading local env file: $ENV_FILE${NC}"
  parse_env_file "$ENV_FILE" "$TEMP_DIR/local_env.txt"
  LOCAL_ENV_COUNT=$(wc -l < "$TEMP_DIR/local_env.txt" | tr -d ' ')
  echo -e "${GREEN}Found $LOCAL_ENV_COUNT env vars in local file${NC}"
else
  touch "$TEMP_DIR/local_env.txt"
  chmod 600 "$TEMP_DIR/local_env.txt"
fi

# Compare environments
echo ""
echo -e "${BLUE}=== Comparing Env Vars ===${NC}"
compare_env_vars "$TEMP_DIR/live_env.txt" "$TEMP_DIR/local_env.txt"

# Handle removals (may exit with code 3 in strict mode)
handle_removals

# Merge vars
merge_env_vars

# Print summary
print_summary "$LIVE_SECRETS"

# Dry run check
if [ "$DRY_RUN" = "1" ]; then
  echo ""
  echo -e "${YELLOW}╔══════════════════════════════════════════╗${NC}"
  echo -e "${YELLOW}║    DRY RUN - No changes made             ║${NC}"
  echo -e "${YELLOW}╚══════════════════════════════════════════╝${NC}"
  echo ""
  echo "Would deploy with:"
  [ -n "$FINAL_ENV_VARS" ] && echo "  Env vars: $(echo "$FINAL_ENV_VARS" | tr ',' '\n' | wc -l | tr -d ' ') variables"
  [ -n "$LIVE_SECRETS" ] && echo "  Secrets: $(echo "$LIVE_SECRETS" | tr ',' '\n' | grep -c . || echo 0) secrets"
  [ -n "$VARS_TO_REMOVE" ] && echo "  Remove: $(echo "$VARS_TO_REMOVE" | tr ',' '\n' | wc -l | tr -d ' ') variables"
  exit 0
fi

# Deploy
echo ""
echo -e "${BLUE}=== Deploying ===${NC}"

# Call provider's deploy function (provider handles command construction safely)
if deploy "$FINAL_ENV_VARS" "$LIVE_SECRETS" "$VARS_TO_REMOVE" "$PROJECT_DIR"; then
  echo ""
  echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
  echo -e "${GREEN}║    Deployment Successful!                ║${NC}"
  echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
  exit 0
else
  echo ""
  echo -e "${RED}╔══════════════════════════════════════════╗${NC}"
  echo -e "${RED}║    Deployment Failed                     ║${NC}"
  echo -e "${RED}╚══════════════════════════════════════════╝${NC}"
  exit 2
fi
