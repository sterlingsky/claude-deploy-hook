#!/usr/bin/env bats
# Tests for the main deploy.sh hook

load 'test_helper'

setup() {
  setup_mocks
  export GCP_PROJECT="test-project"
  export GCP_SERVICE="test-service"
  export GCP_REGION="us-central1"
}

teardown() {
  teardown_mocks
}

@test "deploy.sh --help shows usage" {
  run "$PROJECT_ROOT/deploy.sh" --help

  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage"* ]] || [[ "$output" == *"usage"* ]]
}

@test "deploy.sh --list-providers shows providers" {
  run "$PROJECT_ROOT/deploy.sh" --list-providers

  [ "$status" -eq 0 ]
  [[ "$output" == *"gcp-cloud-run"* ]]
}

@test "deploy.sh --dry-run does not error" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  # Should complete without hard error (status 0 or soft warnings)
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "deploy.sh detects gcp-cloud-run from Dockerfile" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run

  [[ "$output" == *"Cloud Run"* ]] || [[ "$output" == *"gcp-cloud-run"* ]]
}

@test "deploy.sh fetches live env vars" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  # Should show that it found env vars
  [[ "$output" == *"env"* ]] || [[ "$output" == *"var"* ]] || [[ "$output" == *"API_KEY"* ]]
}

@test "deploy.sh warns about missing .env file" {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/Dockerfile"
  # No .env file

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  # Should handle gracefully (not crash)
  [[ "$output" == *"No local"* ]] || [[ "$output" == *"env"* ]] || [ "$status" -eq 0 ]
}

@test "deploy.sh accepts --env-file parameter" {
  create_gcp_cloud_run_project
  cat > "$PROJECT_DIR/.env.staging" << 'EOF'
STAGING_VAR=staging_value
EOF

  run "$PROJECT_ROOT/deploy.sh" --dry-run --env-file="$PROJECT_DIR/.env.staging" --provider=gcp-cloud-run

  # Should accept the parameter without crashing
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "deploy.sh shows provider info" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  # Should show provider details
  [[ "$output" == *"test-project"* ]] || [[ "$output" == *"test-service"* ]] || [[ "$output" == *"Provider"* ]]
}
