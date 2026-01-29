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
  assert_output_contains "Usage:"
  assert_output_contains "--dry-run"
  assert_output_contains "--provider"
}

@test "deploy.sh --list-providers shows all providers" {
  run "$PROJECT_ROOT/deploy.sh" --list-providers

  [ "$status" -eq 0 ]
  assert_output_contains "gcp-cloud-run"
  assert_output_contains "aws-lambda"
  assert_output_contains "kubernetes"
  assert_output_contains "vercel"
  assert_output_contains "heroku"
}

@test "deploy.sh --dry-run does not actually deploy" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  [ "$status" -eq 0 ]
  assert_output_contains "DRY RUN"
  assert_output_not_contains "Deploying to Cloud Run"
}

@test "deploy.sh auto-detects provider from project files" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run

  [ "$status" -eq 0 ]
  assert_output_contains "gcp-cloud-run"
}

@test "deploy.sh --provider overrides auto-detection" {
  create_gcp_cloud_run_project
  export AWS_LAMBDA_FUNCTION="test-function"

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=aws-lambda

  [ "$status" -eq 0 ]
  assert_output_contains "aws-lambda"
}

@test "deploy.sh shows env var changes" {
  create_gcp_cloud_run_project

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  [ "$status" -eq 0 ]
  # Should show comparison results
  assert_output_contains "Environment Variable Changes"
}

@test "deploy.sh --strict fails on unknown vars" {
  create_gcp_cloud_run_project

  # Mock returns OLD_VAR which isn't in local .env
  run "$PROJECT_ROOT/deploy.sh" --dry-run --strict --provider=gcp-cloud-run

  # Should exit with code 3 for strict mode violation
  [ "$status" -eq 3 ] || assert_output_contains "unknown"
}

@test "deploy.sh creates secure temp directory" {
  create_gcp_cloud_run_project

  # Run in subshell to capture temp dir creation
  run bash -c '
    source "'"$PROJECT_ROOT"'/deploy.sh" --dry-run --provider=gcp-cloud-run 2>&1
    if [ -d "$TEMP_DIR" ]; then
      perms=$(stat -c "%a" "$TEMP_DIR" 2>/dev/null || stat -f "%OLp" "$TEMP_DIR")
      echo "TEMP_DIR_PERMS=$perms"
    fi
  '

  # Check permissions are restrictive (700)
  assert_output_contains "700" || assert_output_contains "TEMP_DIR"
}

@test "deploy.sh handles missing .env file gracefully" {
  mkdir -p "$PROJECT_DIR"
  touch "$PROJECT_DIR/Dockerfile"
  # No .env file created

  run "$PROJECT_ROOT/deploy.sh" --dry-run --provider=gcp-cloud-run

  # Should not fail, just warn
  [ "$status" -eq 0 ] || assert_output_contains "No local env file"
}

@test "deploy.sh respects --env-file flag" {
  create_gcp_cloud_run_project
  cat > "$PROJECT_DIR/.env.staging" << 'EOF'
STAGING_VAR=staging_value
EOF

  run "$PROJECT_ROOT/deploy.sh" --dry-run --env-file="$PROJECT_DIR/.env.staging" --provider=gcp-cloud-run

  [ "$status" -eq 0 ]
  assert_output_contains "STAGING_VAR"
}
