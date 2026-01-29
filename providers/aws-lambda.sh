#!/bin/bash
# AWS Lambda Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="AWS Lambda"
PROVIDER_ID="aws-lambda"

# Default configuration
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-us-east-1}}"
: "${AWS_LAMBDA_FUNCTION:=}"
: "${AWS_PROFILE:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/serverless.yml" ] && return 0
  [ -f "${PROJECT_DIR}/serverless.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/template.yaml" ] && grep -q "AWS::Serverless" "${PROJECT_DIR}/template.yaml" 2>/dev/null && return 0
  [ -f "${PROJECT_DIR}/template.yml" ] && grep -q "AWS::Serverless" "${PROJECT_DIR}/template.yml" 2>/dev/null && return 0
  [ -f "${PROJECT_DIR}/sam.yaml" ] && return 0
  [ -f "${PROJECT_DIR}/lambda.json" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  # Check AWS CLI
  if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}" >&2
    echo "  Install from: https://aws.amazon.com/cli/" >&2
    errors=1
  fi

  if [ -z "$AWS_LAMBDA_FUNCTION" ]; then
    echo -e "${RED}Error: AWS_LAMBDA_FUNCTION not set${NC}" >&2
    echo "  Set AWS_LAMBDA_FUNCTION environment variable" >&2
    errors=1
  fi

  return $errors
}

# Get AWS CLI with optional profile
aws_cmd() {
  local -a cmd=(aws)
  [ -n "$AWS_PROFILE" ] && cmd+=(--profile "$AWS_PROFILE")
  [ -n "$AWS_REGION" ] && cmd+=(--region "$AWS_REGION")
  echo "${cmd[@]}"
}

# Check if function exists
service_exists() {
  $(aws_cmd) lambda get-function --function-name "$AWS_LAMBDA_FUNCTION" &>/dev/null
}

# Fetch live environment variables
fetch_live_env() {
  local config
  config=$($(aws_cmd) lambda get-function-configuration \
    --function-name "$AWS_LAMBDA_FUNCTION" \
    --output json 2>/dev/null) || return 1

  echo "$config" | jq -r '
    .Environment.Variables // {} |
    to_entries |
    map("\(.key)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Fetch live secrets (Lambda doesn't have native secrets, but check for SSM refs)
fetch_live_secrets() {
  # Lambda uses SSM Parameter Store or Secrets Manager
  # We can detect references but not list them directly
  echo ""
}

# Deploy to AWS Lambda
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to AWS Lambda...${NC}"
  echo "  Function: $AWS_LAMBDA_FUNCTION"
  echo "  Region:   $AWS_REGION"
  echo ""

  local aws=$(aws_cmd)

  # Update environment variables
  if [ -n "$env_vars" ] || [ -n "$vars_to_remove" ]; then
    echo -e "${BLUE}Updating environment variables...${NC}"

    # Get current env vars
    local current_env
    current_env=$($aws lambda get-function-configuration \
      --function-name "$AWS_LAMBDA_FUNCTION" \
      --query 'Environment.Variables' \
      --output json 2>/dev/null) || current_env="{}"

    # Build new env vars JSON
    local new_env="$current_env"

    # Add/update vars
    if [ -n "$env_vars" ]; then
      IFS=',' read -ra PAIRS <<< "$env_vars"
      for pair in "${PAIRS[@]}"; do
        key="${pair%%=*}"
        value="${pair#*=}"
        new_env=$(echo "$new_env" | jq --arg k "$key" --arg v "$value" '. + {($k): $v}')
      done
    fi

    # Remove vars
    if [ -n "$vars_to_remove" ]; then
      IFS=',' read -ra KEYS <<< "$vars_to_remove"
      for key in "${KEYS[@]}"; do
        new_env=$(echo "$new_env" | jq --arg k "$key" 'del(.[$k])')
      done
    fi

    # Apply env vars
    $aws lambda update-function-configuration \
      --function-name "$AWS_LAMBDA_FUNCTION" \
      --environment "Variables=$new_env"
  fi

  # Check for SAM or Serverless Framework
  if [ -f "$source_dir/template.yaml" ] || [ -f "$source_dir/template.yml" ]; then
    echo -e "${BLUE}Deploying with SAM...${NC}"
    sam deploy --no-confirm-changeset
  elif [ -f "$source_dir/serverless.yml" ] || [ -f "$source_dir/serverless.yaml" ]; then
    echo -e "${BLUE}Deploying with Serverless Framework...${NC}"
    serverless deploy
  else
    # Direct Lambda update
    echo -e "${BLUE}Updating function code...${NC}"
    if [ -f "$source_dir/function.zip" ]; then
      $aws lambda update-function-code \
        --function-name "$AWS_LAMBDA_FUNCTION" \
        --zip-file "fileb://$source_dir/function.zip"
    else
      echo -e "${YELLOW}Warning: No deployment package found${NC}"
      echo "  Create function.zip or use SAM/Serverless Framework"
    fi
  fi
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Function: $AWS_LAMBDA_FUNCTION"
  echo "Region:   $AWS_REGION"
  [ -n "$AWS_PROFILE" ] && echo "Profile:  $AWS_PROFILE"
}
