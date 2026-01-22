#!/bin/bash
# Ralph Wiggum for Claude Code - Installer
#
# One-liner installation:
#   curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/install.sh | bash
#
# With auto gum install:
#   curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/install.sh | INSTALL_GUM=1 bash

set -euo pipefail

REPO_URL="https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main"

echo "═══════════════════════════════════════════════════════════════════"
echo "🐛 Ralph Wiggum for Claude Code - Installer"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# =============================================================================
# PREREQUISITES CHECK
# =============================================================================

echo "Checking prerequisites..."

# Check for git repo
if ! git rev-parse --git-dir > /dev/null 2>&1; then
  echo "❌ Not in a git repository."
  echo "   Please run this from within a git repository:"
  echo "   git init && curl -fsSL $REPO_URL/install.sh | bash"
  exit 1
fi
echo "✓ Git repository detected"

# Check for claude CLI
if command -v claude &> /dev/null; then
  echo "✓ Claude CLI found"
else
  echo "⚠️  Claude CLI not found"
  echo "   Install via: npm install -g @anthropic-ai/claude-code"
  echo "   Continuing anyway..."
fi

# Check for jq
if command -v jq &> /dev/null; then
  echo "✓ jq found"
else
  echo "⚠️  jq not found (required for stream parsing)"
  echo "   Install via: apt install jq (Linux) or brew install jq (macOS)"
  echo "   Continuing anyway..."
fi

# Check for gum (optional)
if command -v gum &> /dev/null; then
  echo "✓ gum found (enhanced UI available)"
else
  echo "ℹ️  gum not found (will use simple prompts)"
  
  if [[ "${INSTALL_GUM:-}" == "1" ]]; then
    echo "   Installing gum..."
    if [[ "$OSTYPE" == "darwin"* ]]; then
      brew install gum 2>/dev/null || echo "   ⚠️  Could not install gum via brew"
    elif command -v apt &> /dev/null; then
      sudo mkdir -p /etc/apt/keyrings
      curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg 2>/dev/null || true
      echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list > /dev/null 2>/dev/null || true
      sudo apt update && sudo apt install -y gum 2>/dev/null || echo "   ⚠️  Could not install gum via apt"
    else
      echo "   ⚠️  Could not auto-install gum. See: https://github.com/charmbracelet/gum#installation"
    fi
  else
    echo "   To install: brew install gum (macOS) or see https://github.com/charmbracelet/gum#installation"
    echo "   Or re-run with: curl ... | INSTALL_GUM=1 bash"
  fi
fi

echo ""

# =============================================================================
# CREATE DIRECTORY STRUCTURE
# =============================================================================

echo "Creating directory structure..."

mkdir -p .ralph/scripts/shims
mkdir -p .ralph/state
mkdir -p .ralph/tasks

echo "✓ Created .ralph/scripts/"
echo "✓ Created .ralph/state/"
echo "✓ Created .ralph/tasks/"

# =============================================================================
# DOWNLOAD SCRIPTS
# =============================================================================

echo ""
echo "Downloading scripts..."

SCRIPTS=(
  "ralph-common.sh"
  "ralph-setup.sh"
  "ralph-loop.sh"
  "ralph-once.sh"
  "stream-parser.sh"
  "init-ralph.sh"
)

for script in "${SCRIPTS[@]}"; do
  echo "  Downloading $script..."
  curl -fsSL "$REPO_URL/scripts/$script" -o ".ralph/scripts/$script"
  chmod +x ".ralph/scripts/$script"
done

echo "✓ Scripts downloaded"

# =============================================================================
# DOWNLOAD SHIMS
# =============================================================================

echo ""
echo "Downloading shims..."

SHIMS=(
  "git"
  "node"
  "npm"
  "python"
  "python3"
)

for shim in "${SHIMS[@]}"; do
  echo "  Downloading shim: $shim..."
  curl -fsSL "$REPO_URL/scripts/shims/$shim" -o ".ralph/scripts/shims/$shim"
  chmod +x ".ralph/scripts/shims/$shim"
done

echo "✓ Shims downloaded"

# =============================================================================
# INITIALIZE STATE FILES
# =============================================================================

echo ""
echo "Initializing state files..."

# Create guardrails.md
cat > .ralph/state/guardrails.md << 'EOF'
# Guardrails

> STOP. Read these before every action.

## Non-Interactive Commands Only

**NEVER** run commands that wait for input. Always use flags:
- `npm init -y` (not `npm init`)
- `git commit -m "msg"` (not `git commit`)
- `python script.py` (not `python`)
- `node script.js` (not `node`)

## Safe Workflow

1. **Read before write** - Check file contents before editing
2. **Test after changes** - Run tests to verify
3. **Commit checkpoints** - Save state before risky changes

---

## Learned Failures

_(Added automatically when errors occur)_

EOF

# Create progress.md
cat > .ralph/state/progress.md << 'EOF'
# Progress Log

> Updated by the agent after significant work.

## Summary

- Iterations completed: 0
- Current status: Initialized

## How This Works

Progress is tracked in THIS FILE, not in LLM context.
When context is rotated (fresh agent), the new agent reads this file.
This is how Ralph maintains continuity across iterations.

## Session History

EOF

# Create errors.log
cat > .ralph/state/errors.log << 'EOF'
# Error Log

> Failures detected by stream-parser. Use to update guardrails.

EOF

# Create activity.log
cat > .ralph/state/activity.log << 'EOF'
# Activity Log

> Real-time tool call logging from stream-parser.

EOF

# Create iteration counter
echo "0" > .ralph/state/.iteration

echo "✓ State files initialized"

# =============================================================================
# CREATE TASK TEMPLATE
# =============================================================================

echo ""
echo "Creating task template..."

if [[ ! -f ".ralph/tasks/RALPH_TASK.md" ]]; then
  cat > .ralph/tasks/RALPH_TASK.md << 'EOF'
---
task: Your task description here
test_command: "npm test"
---

# Task

Describe what you want to accomplish.

## Success Criteria

1. [ ] First thing to complete
2. [ ] Second thing to complete
3. [ ] Third thing to complete

## Context

Any additional context the agent should know.
EOF
  echo "✓ Created .ralph/tasks/RALPH_TASK.md"
else
  echo "ℹ️  .ralph/tasks/RALPH_TASK.md already exists, skipping"
fi

# =============================================================================
# UPDATE .gitignore
# =============================================================================

echo ""
echo "Updating .gitignore..."

if [[ -f ".gitignore" ]]; then
  if ! grep -q "ralph-config.json" .gitignore 2>/dev/null; then
    echo "" >> .gitignore
    echo "# Ralph config (may contain API keys)" >> .gitignore
    echo ".cursor/ralph-config.json" >> .gitignore
    echo "✓ Updated .gitignore"
  else
    echo "ℹ️  .gitignore already configured"
  fi
else
  cat > .gitignore << 'EOF'
# Ralph config (may contain API keys)
.cursor/ralph-config.json
EOF
  echo "✓ Created .gitignore"
fi

# =============================================================================
# SUMMARY
# =============================================================================

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ Ralph Wiggum installed successfully!"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Directory structure:"
echo "  .ralph/"
echo "  ├── scripts/              - Shell scripts"
echo "  │   ├── ralph-setup.sh    - Interactive setup (main entry point)"
echo "  │   ├── ralph-loop.sh     - CLI mode for scripting"
echo "  │   ├── ralph-once.sh     - Single iteration for testing"
echo "  │   └── shims/            - Command wrappers (git, npm, etc.)"
echo "  ├── state/"
echo "  │   ├── guardrails.md     - Lessons learned (agent updates)"
echo "  │   ├── progress.md       - Progress log (agent updates)"
echo "  │   ├── activity.log      - Tool call log (parser updates)"
echo "  │   └── errors.log        - Failure log (parser updates)"
echo "  └── tasks/"
echo "      └── RALPH_TASK.md     - Define your task here"
echo ""
echo "Next steps:"
echo "  1. Edit .ralph/tasks/RALPH_TASK.md to define your task"
echo "  2. Run: .ralph/scripts/ralph-setup.sh"
echo ""
echo "Quick commands:"
echo "  .ralph/scripts/ralph-setup.sh    # Interactive setup + loop"
echo "  .ralph/scripts/ralph-once.sh     # Test single iteration"
echo "  .ralph/scripts/ralph-loop.sh -y  # Non-interactive loop"
echo ""
echo "Monitor progress:"
echo "  tail -f .ralph/state/activity.log"
echo ""
echo "═══════════════════════════════════════════════════════════════════"
