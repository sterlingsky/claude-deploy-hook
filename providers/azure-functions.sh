#!/bin/bash
# Azure Functions Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="Azure Functions"
PROVIDER_ID="azure-functions"

# Default configuration
: "${AZURE_SUBSCRIPTION:=}"
: "${AZURE_RESOURCE_GROUP:=}"
: "${AZURE_FUNCTION_APP:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/host.json" ] && [ -f "${PROJECT_DIR}/local.settings.json" ] && return 0
  [ -f "${PROJECT_DIR}/.funcignore" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v az &> /dev/null; then
    echo -e "${RED}Error: Azure CLI not found${NC}" >&2
    echo "  Install from: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli" >&2
    errors=1
  fi

  if ! command -v func &> /dev/null; then
    echo -e "${RED}Error: Azure Functions Core Tools not found${NC}" >&2
    echo "  Install from: https://docs.microsoft.com/en-us/azure/azure-functions/functions-run-local" >&2
    errors=1
  fi

  if [ -z "$AZURE_FUNCTION_APP" ]; then
    echo -e "${RED}Error: AZURE_FUNCTION_APP not set${NC}" >&2
    errors=1
  fi

  if [ -z "$AZURE_RESOURCE_GROUP" ]; then
    echo -e "${RED}Error: AZURE_RESOURCE_GROUP not set${NC}" >&2
    errors=1
  fi

  return $errors
}

# Check if function app exists
service_exists() {
  az functionapp show \
    --name "$AZURE_FUNCTION_APP" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --query "name" \
    --output tsv 2>/dev/null | grep -q "$AZURE_FUNCTION_APP"
}

# Fetch live environment variables
fetch_live_env() {
  az functionapp config appsettings list \
    --name "$AZURE_FUNCTION_APP" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --output json 2>/dev/null | jq -r '
    . // [] |
    map(select(.name | startswith("WEBSITE_") | not)) |
    map(select(.name | startswith("FUNCTIONS_") | not)) |
    map(select(.name | startswith("AzureWeb") | not)) |
    map("\(.name)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Fetch live secrets (Key Vault references)
fetch_live_secrets() {
  az functionapp config appsettings list \
    --name "$AZURE_FUNCTION_APP" \
    --resource-group "$AZURE_RESOURCE_GROUP" \
    --output json 2>/dev/null | jq -r '
    . // [] |
    map(select(.value | contains("@Microsoft.KeyVault"))) |
    map("\(.name)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Deploy to Azure Functions
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to Azure Functions...${NC}"
  echo "  Function App:    $AZURE_FUNCTION_APP"
  echo "  Resource Group:  $AZURE_RESOURCE_GROUP"
  echo ""

  # Update app settings
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Updating app settings...${NC}"
    local settings=""
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      [ -n "$settings" ] && settings="$settings "
      settings="$settings$pair"
    done

    az functionapp config appsettings set \
      --name "$AZURE_FUNCTION_APP" \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --settings $settings
  fi

  # Remove app settings
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing app settings...${NC}"
    local keys=""
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      [ -n "$keys" ] && keys="$keys "
      keys="$keys$key"
    done

    az functionapp config appsettings delete \
      --name "$AZURE_FUNCTION_APP" \
      --resource-group "$AZURE_RESOURCE_GROUP" \
      --setting-names $keys
  fi

  # Deploy function code
  echo -e "${BLUE}Deploying function code...${NC}"
  cd "$source_dir"
  func azure functionapp publish "$AZURE_FUNCTION_APP"
}

# Print provider-specific info
print_info() {
  echo "Provider:       $PROVIDER_NAME"
  echo "Function App:   $AZURE_FUNCTION_APP"
  echo "Resource Group: $AZURE_RESOURCE_GROUP"
  [ -n "$AZURE_SUBSCRIPTION" ] && echo "Subscription:   $AZURE_SUBSCRIPTION"
}
