#!/usr/bin/env bats
# Tests for environment variable comparison logic

load 'test_helper'

setup() {
  setup_mocks
}

teardown() {
  teardown_mocks
}

@test "env-compare.sh loads without errors" {
  run bash -c "source '$PROJECT_ROOT/lib/env-compare.sh' 2>&1"
  [ "$status" -eq 0 ]
}

@test "parse_env_file extracts KEY=VALUE pairs to output file" {
  create_env_file "$PROJECT_DIR/.env"
  local output_file="$PROJECT_DIR/parsed.txt"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  parse_env_file "$PROJECT_DIR/.env" "$output_file"

  [ -f "$output_file" ]
  grep -q "API_KEY" "$output_file"
  grep -q "DATABASE_URL" "$output_file"
}

@test "parse_env_file ignores comments" {
  cat > "$PROJECT_DIR/.env" << 'EOF'
# This is a comment
API_KEY=test123
# Another comment
DATABASE_URL=postgres://localhost/db
EOF
  local output_file="$PROJECT_DIR/parsed.txt"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  parse_env_file "$PROJECT_DIR/.env" "$output_file"

  # Should not contain comments
  ! grep -q "^#" "$output_file"
  # Should contain variables
  grep -q "API_KEY" "$output_file"
}

@test "parse_env_file handles empty lines" {
  cat > "$PROJECT_DIR/.env" << 'EOF'
API_KEY=test123

DATABASE_URL=postgres://localhost/db

EOF
  local output_file="$PROJECT_DIR/parsed.txt"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  parse_env_file "$PROJECT_DIR/.env" "$output_file"

  # Should have both vars
  grep -q "API_KEY" "$output_file"
  grep -q "DATABASE_URL" "$output_file"
  # Should not have empty lines
  ! grep -q "^$" "$output_file"
}

@test "find_local_env_file finds .env" {
  mkdir -p "$PROJECT_DIR"
  echo "TEST=value" > "$PROJECT_DIR/.env"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  result=$(find_local_env_file "$PROJECT_DIR")

  [[ "$result" == *".env"* ]]
}

@test "find_local_env_file prefers .env.production" {
  mkdir -p "$PROJECT_DIR"
  echo "TEST=value" > "$PROJECT_DIR/.env"
  echo "PROD=value" > "$PROJECT_DIR/.env.production"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  result=$(find_local_env_file "$PROJECT_DIR")

  [[ "$result" == *".env.production"* ]]
}

@test "secure_delete removes file" {
  local testfile="$PROJECT_DIR/testfile.txt"
  mkdir -p "$PROJECT_DIR"
  echo "secret data" > "$testfile"

  source "$PROJECT_ROOT/lib/env-compare.sh"
  secure_delete "$testfile"

  [ ! -f "$testfile" ]
}

@test "create_secure_temp creates file with 600 permissions" {
  source "$PROJECT_ROOT/lib/env-compare.sh"
  tmpfile=$(create_secure_temp)

  [ -f "$tmpfile" ]
  perms=$(stat -f "%OLp" "$tmpfile" 2>/dev/null || stat -c "%a" "$tmpfile" 2>/dev/null)
  [ "$perms" = "600" ]

  rm -f "$tmpfile"
}
