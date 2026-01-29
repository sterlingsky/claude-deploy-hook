#!/bin/bash
# Claude Deploy Hook - Installation Script
# Installs the hook into your project's .claude/hooks directory

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default target is current directory
TARGET_DIR="${1:-.}"
HOOKS_DIR="$TARGET_DIR/.claude/hooks"

echo -e "${BLUE}Claude Deploy Hook - Installer${NC}"
echo ""

# Check if target exists
if [ ! -d "$TARGET_DIR" ]; then
  echo -e "${RED}Error: Target directory '$TARGET_DIR' does not exist${NC}"
  exit 1
fi

# Create hooks directory
echo -e "${BLUE}Installing to: $HOOKS_DIR${NC}"
mkdir -p "$HOOKS_DIR/lib" "$HOOKS_DIR/providers"

# Copy files
echo "Copying files..."
cp "$SCRIPT_DIR/deploy.sh" "$HOOKS_DIR/"
cp "$SCRIPT_DIR/lib/env-compare.sh" "$HOOKS_DIR/lib/"
cp "$SCRIPT_DIR/providers/"*.sh "$HOOKS_DIR/providers/"

# Make executable
chmod +x "$HOOKS_DIR/deploy.sh" "$HOOKS_DIR/lib/"*.sh "$HOOKS_DIR/providers/"*.sh

echo -e "${GREEN}Files installed successfully${NC}"
echo ""

# Check for settings.json
SETTINGS_FILE="$TARGET_DIR/.claude/settings.json"
if [ -f "$SETTINGS_FILE" ]; then
  echo -e "${YELLOW}Note: .claude/settings.json exists${NC}"
  echo "You may want to add the hook configuration manually."
else
  echo -e "${BLUE}Creating .claude/settings.json...${NC}"
  cat > "$SETTINGS_FILE" << 'EOF'
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": "if echo \"$TOOL_INPUT\" | grep -qE '(gcloud run deploy|firebase deploy|vercel|wrangler deploy|railway up)'; then \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/deploy.sh; fi",
            "timeout": 600
          }
        ]
      }
    ]
  }
}
EOF
  echo -e "${GREEN}Created settings.json with hook configuration${NC}"
fi

echo ""
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Usage:"
echo "  $HOOKS_DIR/deploy.sh                    # Deploy with auto-detection"
echo "  $HOOKS_DIR/deploy.sh --dry-run          # Preview changes"
echo "  $HOOKS_DIR/deploy.sh --list-providers   # Show available providers"
echo ""
echo "The hook will also trigger automatically when you run deployment commands."
