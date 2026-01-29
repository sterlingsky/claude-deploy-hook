#!/bin/bash
# Test runner for claude-deploy-hook
#
# Usage:
#   ./tests/run_tests.sh           # Run all tests
#   ./tests/run_tests.sh -v        # Run with verbose output
#   ./tests/run_tests.sh FILE.bats # Run specific test file

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Claude Deploy Hook Test Suite${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

# Check for BATS
if ! command -v bats &> /dev/null; then
  echo -e "${YELLOW}BATS not found. Installing...${NC}"

  # Try different installation methods
  if command -v brew &> /dev/null; then
    brew install bats-core
  elif command -v npm &> /dev/null; then
    npm install -g bats
  elif command -v apt-get &> /dev/null; then
    sudo apt-get install -y bats
  else
    echo -e "${RED}Could not install BATS. Please install manually:${NC}"
    echo "  - macOS: brew install bats-core"
    echo "  - npm: npm install -g bats"
    echo "  - Linux: apt-get install bats"
    echo "  - Manual: https://github.com/bats-core/bats-core#installation"
    exit 1
  fi
fi

# Make mocks executable
echo -e "${BLUE}Setting up mocks...${NC}"
chmod +x "$SCRIPT_DIR"/mocks/* 2>/dev/null || true

# Parse arguments
VERBOSE=""
TEST_FILES=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--verbose)
      VERBOSE="--verbose-run"
      shift
      ;;
    -t|--tap)
      VERBOSE="--tap"
      shift
      ;;
    *.bats)
      TEST_FILES+=("$1")
      shift
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Default to all test files if none specified
if [ ${#TEST_FILES[@]} -eq 0 ]; then
  TEST_FILES=("$SCRIPT_DIR"/*.bats)
fi

# Run tests
echo ""
echo -e "${BLUE}Running tests...${NC}"
echo ""

FAILED=0
PASSED=0

for test_file in "${TEST_FILES[@]}"; do
  if [ -f "$test_file" ]; then
    echo -e "${BLUE}Testing: $(basename "$test_file")${NC}"
    echo "----------------------------------------"

    if bats $VERBOSE "$test_file"; then
      ((PASSED++))
    else
      ((FAILED++))
    fi

    echo ""
  fi
done

# Summary
echo -e "${BLUE}======================================${NC}"
echo -e "${BLUE}  Test Summary${NC}"
echo -e "${BLUE}======================================${NC}"
echo ""

if [ $FAILED -eq 0 ]; then
  echo -e "${GREEN}✓ All test files passed!${NC}"
  echo -e "  Files tested: $PASSED"
  exit 0
else
  echo -e "${RED}✗ Some tests failed${NC}"
  echo -e "  Passed: ${GREEN}$PASSED${NC}"
  echo -e "  Failed: ${RED}$FAILED${NC}"
  exit 1
fi
