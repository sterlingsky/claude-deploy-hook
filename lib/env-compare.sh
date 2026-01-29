#!/bin/bash
# Shared environment variable comparison library
# Sourced by deploy.sh - do not run directly

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Compare environment variables between live and local
# Sets: VARS_TO_ADD, VARS_TO_UPDATE, VARS_TO_REMOVE, VARS_UNCHANGED
compare_env_vars() {
  local live_file="$1"
  local local_file="$2"

  # Build associative arrays
  declare -gA LIVE_VARS
  declare -gA LOCAL_VARS

  LIVE_VARS=()
  LOCAL_VARS=()

  # Parse live env vars
  while IFS='=' read -r key value; do
    [ -n "$key" ] && LIVE_VARS["$key"]="$value"
  done < "$live_file"

  # Parse local env vars
  while IFS='=' read -r key value; do
    [ -n "$key" ] && LOCAL_VARS["$key"]="$value"
  done < "$local_file"

  # Reset result variables
  VARS_TO_ADD=""
  VARS_TO_UPDATE=""
  VARS_TO_REMOVE=""
  VARS_UNCHANGED=""
  REMOVAL_CANDIDATES=()

  # Find new and updated vars
  for key in "${!LOCAL_VARS[@]}"; do
    if [ -z "${LIVE_VARS[$key]+x}" ]; then
      echo -e "${GREEN}+ ADD:${NC} $key"
      [ -n "$VARS_TO_ADD" ] && VARS_TO_ADD="$VARS_TO_ADD,"
      VARS_TO_ADD="$VARS_TO_ADD$key=${LOCAL_VARS[$key]}"
    elif [ "${LIVE_VARS[$key]}" != "${LOCAL_VARS[$key]}" ]; then
      echo -e "${YELLOW}~ UPDATE:${NC} $key"
      echo "    Live:  ${LIVE_VARS[$key]:0:50}$([ ${#LIVE_VARS[$key]} -gt 50 ] && echo '...')"
      echo "    Local: ${LOCAL_VARS[$key]:0:50}$([ ${#LOCAL_VARS[$key]} -gt 50 ] && echo '...')"
      [ -n "$VARS_TO_UPDATE" ] && VARS_TO_UPDATE="$VARS_TO_UPDATE,"
      VARS_TO_UPDATE="$VARS_TO_UPDATE$key=${LOCAL_VARS[$key]}"
    else
      VARS_UNCHANGED="$VARS_UNCHANGED $key"
    fi
  done

  # Find removal candidates
  for key in "${!LIVE_VARS[@]}"; do
    if [ -z "${LOCAL_VARS[$key]+x}" ]; then
      REMOVAL_CANDIDATES+=("$key")
    fi
  done
}

# Handle removal candidates with user confirmation
# Sets: VARS_TO_REMOVE or adds to VARS_TO_UPDATE to preserve
handle_removals() {
  if [ ${#REMOVAL_CANDIDATES[@]} -eq 0 ]; then
    return 0
  fi

  echo ""
  echo -e "${RED}=== Vars in live service but NOT in local .env ===${NC}"
  for key in "${REMOVAL_CANDIDATES[@]}"; do
    echo -e "${RED}- REMOVE?:${NC} $key=${LIVE_VARS[$key]:0:50}$([ ${#LIVE_VARS[$key]} -gt 50 ] && echo '...')"
  done
  echo ""

  # Check if interactive
  if [ -t 0 ]; then
    read -p "Remove these ${#REMOVAL_CANDIDATES[@]} env var(s)? [y]es / [N]o (keep all) / [s]elect individually: " REMOVE_CHOICE
    case "$REMOVE_CHOICE" in
      y|Y)
        echo -e "${RED}Will remove ${#REMOVAL_CANDIDATES[@]} env var(s)${NC}"
        for key in "${REMOVAL_CANDIDATES[@]}"; do
          [ -n "$VARS_TO_REMOVE" ] && VARS_TO_REMOVE="$VARS_TO_REMOVE,"
          VARS_TO_REMOVE="$VARS_TO_REMOVE$key"
        done
        ;;
      s|S)
        for key in "${REMOVAL_CANDIDATES[@]}"; do
          read -p "  Remove '$key'? (y/N): " SINGLE_CHOICE
          if [[ "$SINGLE_CHOICE" =~ ^[Yy]$ ]]; then
            [ -n "$VARS_TO_REMOVE" ] && VARS_TO_REMOVE="$VARS_TO_REMOVE,"
            VARS_TO_REMOVE="$VARS_TO_REMOVE$key"
          else
            [ -n "$VARS_TO_UPDATE" ] && VARS_TO_UPDATE="$VARS_TO_UPDATE,"
            VARS_TO_UPDATE="$VARS_TO_UPDATE$key=${LIVE_VARS[$key]}"
          fi
        done
        ;;
      *)
        echo -e "${GREEN}Keeping all existing vars${NC}"
        for key in "${REMOVAL_CANDIDATES[@]}"; do
          [ -n "$VARS_TO_UPDATE" ] && VARS_TO_UPDATE="$VARS_TO_UPDATE,"
          VARS_TO_UPDATE="$VARS_TO_UPDATE$key=${LIVE_VARS[$key]}"
        done
        ;;
    esac
  else
    echo -e "${YELLOW}Non-interactive mode: Keeping all existing vars (safe default)${NC}"
    for key in "${REMOVAL_CANDIDATES[@]}"; do
      [ -n "$VARS_TO_UPDATE" ] && VARS_TO_UPDATE="$VARS_TO_UPDATE,"
      VARS_TO_UPDATE="$VARS_TO_UPDATE$key=${LIVE_VARS[$key]}"
    done
  fi
}

# Merge all env vars into FINAL_ENV_VARS
merge_env_vars() {
  FINAL_ENV_VARS=""
  [ -n "$VARS_TO_ADD" ] && FINAL_ENV_VARS="$VARS_TO_ADD"
  [ -n "$VARS_TO_UPDATE" ] && {
    [ -n "$FINAL_ENV_VARS" ] && FINAL_ENV_VARS="$FINAL_ENV_VARS,"
    FINAL_ENV_VARS="$FINAL_ENV_VARS$VARS_TO_UPDATE"
  }
}

# Print deployment summary
print_summary() {
  local secrets="$1"

  echo ""
  echo -e "${BLUE}=== Deployment Summary ===${NC}"
  [ -n "$VARS_TO_ADD" ] && echo -e "${GREEN}Adding:${NC} $(echo "$VARS_TO_ADD" | tr ',' '\n' | wc -l | tr -d ' ') var(s)"
  [ -n "$VARS_TO_UPDATE" ] && echo -e "${YELLOW}Updating/Preserving:${NC} $(echo "$VARS_TO_UPDATE" | tr ',' '\n' | wc -l | tr -d ' ') var(s)"
  [ -n "$VARS_TO_REMOVE" ] && echo -e "${RED}Removing:${NC} $(echo "$VARS_TO_REMOVE" | tr ',' '\n' | wc -l | tr -d ' ') var(s)"
  [ -n "$secrets" ] && echo -e "${CYAN}Preserving:${NC} $(echo "$secrets" | tr ',' '\n' | grep -c . || echo 0) secret(s)"
}

# Find local env file
find_local_env_file() {
  local project_dir="${1:-.}"
  local env_files=(".env.production" ".env" ".env.local" "functions/.env" "functions/.env.local")

  for env_file in "${env_files[@]}"; do
    if [ -f "$project_dir/$env_file" ]; then
      echo "$project_dir/$env_file"
      return 0
    fi
  done

  return 1
}

# Parse .env file (skip comments and empty lines)
parse_env_file() {
  local file="$1"
  local output="$2"

  if [ -f "$file" ]; then
    grep -v '^#' "$file" | grep -v '^[[:space:]]*$' | grep '=' > "$output" 2>/dev/null || touch "$output"
  else
    touch "$output"
  fi
}
