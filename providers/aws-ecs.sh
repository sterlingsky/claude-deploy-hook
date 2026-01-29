#!/bin/bash
# AWS ECS/Fargate Provider
# Implements: fetch_live_env, fetch_live_secrets, deploy, detect
#
# SECURITY: Uses array-based command construction to avoid eval

# Provider metadata
PROVIDER_NAME="AWS ECS/Fargate"
PROVIDER_ID="aws-ecs"

# Default configuration
: "${AWS_REGION:=${AWS_DEFAULT_REGION:-us-east-1}}"
: "${AWS_ECS_CLUSTER:=}"
: "${AWS_ECS_SERVICE:=}"
: "${AWS_ECS_TASK_DEFINITION:=}"
: "${AWS_PROFILE:=}"

# Detect if this provider should be used
detect() {
  [ -f "${PROJECT_DIR}/ecs-task-def.json" ] && return 0
  [ -f "${PROJECT_DIR}/task-definition.json" ] && return 0
  [ -f "${PROJECT_DIR}/taskdef.json" ] && return 0
  [ -f "${PROJECT_DIR}/copilot" ] && return 0  # AWS Copilot
  [ -f "${PROJECT_DIR}/.ecs" ] && return 0
  return 1
}

# Validate required configuration
validate_config() {
  local errors=0

  if ! command -v aws &> /dev/null; then
    echo -e "${RED}Error: AWS CLI not found${NC}" >&2
    echo "  Install from: https://aws.amazon.com/cli/" >&2
    errors=1
  fi

  if [ -z "$AWS_ECS_CLUSTER" ]; then
    echo -e "${RED}Error: AWS_ECS_CLUSTER not set${NC}" >&2
    errors=1
  fi

  if [ -z "$AWS_ECS_SERVICE" ]; then
    echo -e "${RED}Error: AWS_ECS_SERVICE not set${NC}" >&2
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

# Check if service exists
service_exists() {
  $(aws_cmd) ecs describe-services \
    --cluster "$AWS_ECS_CLUSTER" \
    --services "$AWS_ECS_SERVICE" \
    --query 'services[0].serviceName' \
    --output text 2>/dev/null | grep -q "$AWS_ECS_SERVICE"
}

# Fetch live environment variables from task definition
fetch_live_env() {
  local aws=$(aws_cmd)
  local task_def

  # Get current task definition from service
  task_def=$($aws ecs describe-services \
    --cluster "$AWS_ECS_CLUSTER" \
    --services "$AWS_ECS_SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null)

  [ -z "$task_def" ] && return 1

  # Get env vars from task definition
  $aws ecs describe-task-definition \
    --task-definition "$task_def" \
    --query 'taskDefinition.containerDefinitions[0].environment' \
    --output json 2>/dev/null | jq -r '
    . // [] |
    map("\(.name)=\(.value)") |
    .[]' 2>/dev/null || true
}

# Fetch live secrets from task definition
fetch_live_secrets() {
  local aws=$(aws_cmd)
  local task_def

  task_def=$($aws ecs describe-services \
    --cluster "$AWS_ECS_CLUSTER" \
    --services "$AWS_ECS_SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null)

  [ -z "$task_def" ] && return 1

  $aws ecs describe-task-definition \
    --task-definition "$task_def" \
    --query 'taskDefinition.containerDefinitions[0].secrets' \
    --output json 2>/dev/null | jq -r '
    . // [] |
    map("\(.name)=\(.valueFrom)") |
    .[]' 2>/dev/null || true
}

# Deploy to ECS
deploy() {
  local env_vars="$1"
  local secrets="$2"
  local vars_to_remove="$3"
  local source_dir="$4"

  echo -e "${BLUE}Deploying to AWS ECS...${NC}"
  echo "  Cluster: $AWS_ECS_CLUSTER"
  echo "  Service: $AWS_ECS_SERVICE"
  echo "  Region:  $AWS_REGION"
  echo ""

  local aws=$(aws_cmd)

  # Get current task definition
  local task_def
  task_def=$($aws ecs describe-services \
    --cluster "$AWS_ECS_CLUSTER" \
    --services "$AWS_ECS_SERVICE" \
    --query 'services[0].taskDefinition' \
    --output text 2>/dev/null)

  if [ -z "$task_def" ]; then
    echo -e "${RED}Error: Could not get current task definition${NC}"
    return 1
  fi

  # Get full task definition
  local task_def_json
  task_def_json=$($aws ecs describe-task-definition \
    --task-definition "$task_def" \
    --query 'taskDefinition' \
    --output json 2>/dev/null)

  # Update environment variables in task definition
  if [ -n "$env_vars" ]; then
    echo -e "${BLUE}Updating environment variables...${NC}"
    IFS=',' read -ra PAIRS <<< "$env_vars"
    for pair in "${PAIRS[@]}"; do
      key="${pair%%=*}"
      value="${pair#*=}"
      task_def_json=$(echo "$task_def_json" | jq \
        --arg k "$key" --arg v "$value" \
        '.containerDefinitions[0].environment = (.containerDefinitions[0].environment // [] | map(select(.name != $k)) + [{"name": $k, "value": $v}])')
    done
  fi

  # Remove environment variables
  if [ -n "$vars_to_remove" ]; then
    echo -e "${YELLOW}Removing environment variables...${NC}"
    IFS=',' read -ra KEYS <<< "$vars_to_remove"
    for key in "${KEYS[@]}"; do
      task_def_json=$(echo "$task_def_json" | jq \
        --arg k "$key" \
        '.containerDefinitions[0].environment = (.containerDefinitions[0].environment // [] | map(select(.name != $k)))')
    done
  fi

  # Register new task definition
  echo -e "${BLUE}Registering new task definition...${NC}"
  local new_task_def_json
  new_task_def_json=$(echo "$task_def_json" | jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes, .compatibilities, .registeredAt, .registeredBy)')

  local new_task_def
  new_task_def=$($aws ecs register-task-definition \
    --cli-input-json "$new_task_def_json" \
    --query 'taskDefinition.taskDefinitionArn' \
    --output text 2>/dev/null)

  if [ -z "$new_task_def" ]; then
    echo -e "${RED}Error: Failed to register new task definition${NC}"
    return 1
  fi

  # Update service with new task definition
  echo -e "${BLUE}Updating service...${NC}"
  $aws ecs update-service \
    --cluster "$AWS_ECS_CLUSTER" \
    --service "$AWS_ECS_SERVICE" \
    --task-definition "$new_task_def" \
    --force-new-deployment

  # Wait for deployment
  echo -e "${BLUE}Waiting for deployment to stabilize...${NC}"
  $aws ecs wait services-stable \
    --cluster "$AWS_ECS_CLUSTER" \
    --services "$AWS_ECS_SERVICE"
}

# Print provider-specific info
print_info() {
  echo "Provider: $PROVIDER_NAME"
  echo "Cluster:  $AWS_ECS_CLUSTER"
  echo "Service:  $AWS_ECS_SERVICE"
  echo "Region:   $AWS_REGION"
  [ -n "$AWS_PROFILE" ] && echo "Profile:  $AWS_PROFILE"
}
