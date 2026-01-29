#!/usr/bin/env bats
# Tests for environment variable comparison logic

load 'test_helper'

setup() {
  setup_mocks
  source "$PROJECT_ROOT/lib/env-compare.sh"
}

teardown() {
  teardown_mocks
}

@test "identifies new variables to add" {
  # Live env has: API_KEY, DATABASE_URL
  # Local env has: API_KEY, DATABASE_URL, NEW_VAR

  declare -A LIVE_VARS=(
    ["API_KEY"]="live_value"
    ["DATABASE_URL"]="live_db"
  )

  declare -A LOCAL_VARS=(
    ["API_KEY"]="live_value"
    ["DATABASE_URL"]="live_db"
    ["NEW_VAR"]="new_value"
  )

  run compare_env_vars

  assert_output_contains "NEW_VAR"
  assert_output_contains "ADD"
}

@test "identifies changed variables to update" {
  declare -A LIVE_VARS=(
    ["API_KEY"]="old_value"
  )

  declare -A LOCAL_VARS=(
    ["API_KEY"]="new_value"
  )

  run compare_env_vars

  assert_output_contains "API_KEY"
  assert_output_contains "UPDATE"
}

@test "identifies variables to potentially remove" {
  declare -A LIVE_VARS=(
    ["API_KEY"]="live_value"
    ["OLD_VAR"]="should_remove"
  )

  declare -A LOCAL_VARS=(
    ["API_KEY"]="live_value"
  )

  run compare_env_vars

  assert_output_contains "OLD_VAR"
  assert_output_contains "REMOVE"
}

@test "does not show actual values in output (security)" {
  declare -A LIVE_VARS=(
    ["SECRET_KEY"]="super_secret_password_123"
  )

  declare -A LOCAL_VARS=(
    ["SECRET_KEY"]="different_secret_456"
  )

  run compare_env_vars

  # Should NOT contain actual secret values
  assert_output_not_contains "super_secret_password_123"
  assert_output_not_contains "different_secret_456"

  # Should show character count instead
  assert_output_contains "chars"
}

@test "handles empty live environment" {
  declare -A LIVE_VARS=()

  declare -A LOCAL_VARS=(
    ["API_KEY"]="new_value"
    ["DATABASE_URL"]="new_db"
  )

  run compare_env_vars

  assert_output_contains "API_KEY"
  assert_output_contains "DATABASE_URL"
  assert_output_contains "ADD"
}

@test "handles empty local environment" {
  declare -A LIVE_VARS=(
    ["API_KEY"]="live_value"
    ["DATABASE_URL"]="live_db"
  )

  declare -A LOCAL_VARS=()

  run compare_env_vars

  assert_output_contains "REMOVE"
}

@test "no changes when environments match" {
  declare -A LIVE_VARS=(
    ["API_KEY"]="same_value"
    ["DATABASE_URL"]="same_db"
  )

  declare -A LOCAL_VARS=(
    ["API_KEY"]="same_value"
    ["DATABASE_URL"]="same_db"
  )

  run compare_env_vars

  assert_output_contains "No changes"
}
