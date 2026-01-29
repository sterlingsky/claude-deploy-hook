#!/bin/bash
# Test helper functions for BATS tests

# Get the directory of the test file
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"

# Setup mock environment
setup_mocks() {
  export PATH="$TEST_DIR/mocks:$PATH"
  export MOCK_MODE=1
  export PROJECT_DIR="$TEST_DIR/fixtures/sample-project"

  # Create sample project directory
  mkdir -p "$PROJECT_DIR"
}

# Cleanup after tests
teardown_mocks() {
  unset MOCK_MODE
  rm -rf "$TEST_DIR/fixtures/sample-project"
}

# Create a sample .env file
create_env_file() {
  local env_file="${1:-$PROJECT_DIR/.env}"
  cat > "$env_file" << 'EOF'
API_KEY=local_api_key_123
DATABASE_URL=postgres://localhost/mydb
DEBUG=true
NEW_VAR=added_locally
EOF
}

# Create provider-specific project files
create_gcp_cloud_run_project() {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/Dockerfile"
  create_env_file
}

create_firebase_project() {
  mkdir -p "$PROJECT_DIR/functions"
  echo '{"functions": {}}' > "$PROJECT_DIR/firebase.json"
  create_env_file "$PROJECT_DIR/functions/.env"
}

create_vercel_project() {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/vercel.json"
  create_env_file
}

create_cloudflare_project() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/wrangler.toml" << 'EOF'
name = "my-worker"
main = "src/index.js"
EOF
  create_env_file
}

create_railway_project() {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/railway.json"
  create_env_file
}

create_kubernetes_project() {
  mkdir -p "$PROJECT_DIR/k8s"
  cat > "$PROJECT_DIR/k8s/deployment.yaml" << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
EOF
  create_env_file
}

create_aws_lambda_project() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/serverless.yml" << 'EOF'
service: my-service
provider:
  name: aws
EOF
  create_env_file
}

create_aws_ecs_project() {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/ecs-task-def.json"
  create_env_file
}

create_azure_functions_project() {
  mkdir -p "$PROJECT_DIR"
  echo '{}' > "$PROJECT_DIR/host.json"
  echo '{}' > "$PROJECT_DIR/local.settings.json"
  create_env_file
}

create_heroku_project() {
  mkdir -p "$PROJECT_DIR"
  echo "web: node server.js" > "$PROJECT_DIR/Procfile"
  create_env_file
}

create_flyio_project() {
  mkdir -p "$PROJECT_DIR"
  cat > "$PROJECT_DIR/fly.toml" << 'EOF'
app = "my-fly-app"
EOF
  create_env_file
}

create_render_project() {
  mkdir -p "$PROJECT_DIR"
  echo 'services: []' > "$PROJECT_DIR/render.yaml"
  create_env_file
}

create_netlify_project() {
  mkdir -p "$PROJECT_DIR"
  echo '[build]' > "$PROJECT_DIR/netlify.toml"
  create_env_file
}

# Assert helpers
assert_output_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    echo "Expected output to contain: $expected"
    echo "Actual output: $output"
    return 1
  fi
}

assert_output_not_contains() {
  local unexpected="$1"
  if [[ "$output" == *"$unexpected"* ]]; then
    echo "Expected output NOT to contain: $unexpected"
    echo "Actual output: $output"
    return 1
  fi
}
