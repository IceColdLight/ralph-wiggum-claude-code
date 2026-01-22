# Ralph Wiggum for Claude Code

An implementation of [Geoffrey Huntley's Ralph Wiggum technique](https://ghuntley.com/ralph/) for **Claude Code CLI**, enabling autonomous AI development with deliberate context management.

Forked from [agrimsingh/ralph-wiggum-cursor](https://github.com/agrimsingh/ralph-wiggum-cursor) and adapted for Claude Code with additional features:

- **Quality Checks (QC)**: Verification pass after each task to ensure criteria are actually implemented
- **Task Linking**: Chain multiple tasks via `next_task` frontmatter for complex workflows
- **Refined Flow**: Improved prompts, better guardrails, and watchdog for blocking processes
- **Claude Models**: Native support for Claude model aliases (opus, sonnet)

> "That's the beauty of Ralph - the technique is deterministically bad in an undeterministic world."

## What is Ralph?

Ralph is a technique for autonomous AI development that treats LLM context like memory:

```shell
while :; do cat PROMPT.md | agent ; done
```

The same prompt is fed repeatedly to an AI agent. Progress persists in files and git, not in the LLM's context window. When context fills up, you get a fresh agent with fresh context.

### The malloc/free Problem

In LLM context:
- Reading files, tool outputs, conversation = `malloc()`
- There is no `free()` - context cannot be selectively released
- Only way to free: start a new conversation

This creates two problems:
- **Context pollution** - Failed attempts, unrelated code, and mixed concerns accumulate and confuse the model
- **The gutter** - Once polluted, the model keeps referencing bad context. Like a bowling ball in the gutter, there's no saving it.

Ralph's solution: Deliberately rotate to fresh context before pollution builds up. State lives in files and git, not in the LLM's memory.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      ralph-setup.sh                          │
│                           │                                  │
│              ┌────────────┴────────────┐                    │
│              ▼                         ▼                    │
│         [gum UI]                  [fallback]                │
│     Model selection            Simple prompts               │
│     Max iterations                                          │
│     Options (branch, PR)                                    │
│              │                         │                    │
│              └────────────┬────────────┘                    │
│                           ▼                                  │
│    claude -p --dangerously-skip-permissions                  │
│           --verbose --output-format stream-json              │
│                           │                                  │
│                           ▼                                  │
│                   stream-parser.sh                           │
│                      │        │                              │
│     ┌────────────────┴────────┴────────────────┐            │
│     ▼                                           ▼            │
│  .ralph/state/                              Signals          │
│  ├── activity.log  (tool calls)            ├── WARN at 80k  │
│  ├── errors.log    (failures)              ├── ROTATE at 100k│
│  ├── progress.md   (agent writes)          ├── COMPLETE     │
│  └── guardrails.md (lessons learned)       └── GUTTER       │
│                           │                                  │
│                           ▼                                  │
│                    Quality Check (QC)                        │
│              Verifies criteria before advancing              │
│                           │                                  │
│                           ▼                                  │
│                    Task Chaining                             │
│              Follows next_task to continue                   │
└─────────────────────────────────────────────────────────────┘
```

### Key Features

- **Quality Checks (QC)** - After all criteria are checked, a separate QC agent verifies each was actually implemented
- **Task Chaining** - Define `next_task: filename.md` in frontmatter to chain multiple tasks
- **Interactive setup** - Beautiful gum-based UI for model selection and options
- **Accurate token tracking** - Parser counts actual API-reported tokens
- **Gutter detection** - Detects when agent is stuck (same command failed 3x, file thrashing)
- **Watchdog** - Kills blocking interactive processes (npm init, python REPL, etc.)
- **Command shims** - Prevents interactive commands from hanging the loop
- **Learning from failures** - Agent updates `.ralph/state/guardrails.md` with lessons
- **State in git** - Commits frequently so next agent picks up from git history
- **Branch/PR workflow** - Optionally work on a branch and open PR when complete

## Prerequisites

| Requirement | Check | How to Install |
|-------------|-------|----------------|
| Git repo | `git status` works | `git init` |
| Claude CLI | `which claude` | `npm install -g @anthropic-ai/claude-code` |
| jq | `which jq` | `apt install jq` / `brew install jq` |
| gum (optional) | `which gum` | `brew install gum` or [see installation](https://github.com/charmbracelet/gum#installation) |

## Installation

### Option 1: Copy Scripts Directly

```bash
# Clone this repo
git clone https://github.com/IceColdLight/ralph-wiggum-claude-code.git

# Copy to your project
cp -r ralph-wiggum-claude-code/scripts your-project/.ralph/scripts
chmod +x your-project/.ralph/scripts/*.sh
chmod +x your-project/.ralph/scripts/shims/*

# Initialize
cd your-project
./.ralph/scripts/init-ralph.sh
```

### Option 2: Manual Setup

```bash
cd your-project
mkdir -p .ralph/scripts .ralph/state .ralph/tasks

# Download scripts
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/ralph-common.sh -o .ralph/scripts/ralph-common.sh
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/ralph-setup.sh -o .ralph/scripts/ralph-setup.sh
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/ralph-loop.sh -o .ralph/scripts/ralph-loop.sh
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/ralph-once.sh -o .ralph/scripts/ralph-once.sh
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/stream-parser.sh -o .ralph/scripts/stream-parser.sh
curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/init-ralph.sh -o .ralph/scripts/init-ralph.sh

# Download shims
mkdir -p .ralph/scripts/shims
for shim in git node npm python python3; do
  curl -fsSL https://raw.githubusercontent.com/IceColdLight/ralph-wiggum-claude-code/main/scripts/shims/$shim -o .ralph/scripts/shims/$shim
done

# Make executable
chmod +x .ralph/scripts/*.sh .ralph/scripts/shims/*

# Initialize
./.ralph/scripts/init-ralph.sh
```

## Quick Start

### 1. Define Your Task

Edit `.ralph/tasks/RALPH_TASK.md`:

```markdown
---
task: Build a REST API
test_command: "npm test"
---

# Task: REST API

Build a REST API with user management.

## Success Criteria

1. [ ] GET /health returns 200
2. [ ] POST /users creates a user
3. [ ] GET /users/:id returns user
4. [ ] All tests pass

## Context

- Use Express.js
- Store users in memory (no database needed)
```

**Important**: Use `[ ]` checkboxes. Ralph tracks completion by counting unchecked boxes.

### 2. Start the Loop

```bash
./.ralph/scripts/ralph-setup.sh
```

Ralph will:
1. Show interactive UI for model and options
2. Run `claude` with your task
3. Parse output in real-time, tracking token usage
4. At 80k tokens: warn agent to wrap up
5. At 100k tokens: rotate to fresh context
6. Run **Quality Check** after all criteria are marked complete
7. Follow `next_task` chain if defined
8. Repeat until truly complete (or max iterations)

### 3. Monitor Progress

```bash
# Watch activity in real-time
tail -f .ralph/state/activity.log

# Example output:
# [12:34:56] 📖 TOOL READ: src/index.ts (started)
# [12:34:58] ✏️ TOOL Write: src/routes/users.ts (started)
# [12:35:01] 💻 TOOL Bash: npm test... (started)
# [12:35:10] 🟢 TOKENS: 45230 / 100000 (45%)
```

## Commands

| Command | Description |
|---------|-------------|
| `ralph-setup.sh` | **Primary** - Interactive setup + run loop |
| `ralph-once.sh` | Test single iteration before going AFK |
| `ralph-loop.sh` | CLI mode for scripting (see flags below) |
| `init-ralph.sh` | Re-initialize Ralph state |

### ralph-loop.sh Flags

```bash
./ralph-loop.sh [options] [workspace]

Options:
  -n, --iterations N     Max iterations (default: 20)
  -m, --model MODEL      Model to use (default: opus)
  --branch NAME          Create and work on a new branch
  --pr                   Open PR when complete (requires --branch)
  -y, --yes              Skip confirmation prompt
```

### Model Options

```bash
# Use model aliases
./ralph-loop.sh -m opus      # Claude Opus 4.5 (most capable)
./ralph-loop.sh -m sonnet    # Claude Sonnet 4.5 (faster)

# Or full model names
./ralph-loop.sh -m claude-opus-4-5-20251101
```

## Task Chaining

Chain multiple tasks for complex workflows:

**`.ralph/tasks/RALPH_TASK.md`**:
```markdown
---
task: Set up project structure
next_task: 02-implement-api.md
---

## Success Criteria
1. [ ] Initialize npm project
2. [ ] Set up TypeScript
3. [ ] Create folder structure
```

**`.ralph/tasks/02-implement-api.md`**:
```markdown
---
task: Implement API endpoints
next_task: 03-add-tests.md
---

## Success Criteria
1. [ ] Implement GET /users
2. [ ] Implement POST /users
```

When `RALPH_TASK.md` completes (and passes QC), Ralph automatically moves to `02-implement-api.md`.

## Quality Checks (QC)

After all criteria in a task are marked `[x]`, Ralph runs a **Quality Check**:

1. A separate QC agent verifies each checked criterion was actually implemented
2. If verification fails, the criterion is unchecked and work continues
3. Only after QC passes does Ralph advance to the next task or complete

This prevents the agent from marking criteria done without actually implementing them.

QC verification is tracked in frontmatter:
```markdown
---
task: My task
quality_check_passed: true  # Added by Ralph after QC passes
---
```

## Command Shims

Ralph includes shims that prevent interactive commands from blocking:

| Shim | What it does |
|------|--------------|
| `git` | Auto-adds `-m "ralph: checkpoint"` to commit, `--no-edit` to amend |
| `npm` | Auto-adds `-y` to `npm init`, skips if package.json exists |
| `node` | Blocks bare `node` REPL |
| `python` | Blocks bare `python` REPL |
| `python3` | Blocks bare `python3` REPL |

## Watchdog

A background watchdog monitors for blocking interactive processes:

- `npm init` (without `-y`)
- `git commit` (without `-m`)
- `node` (bare REPL)
- `python`/`python3` (bare REPL)

If detected, the process is killed and GUTTER is signaled.

## File Reference

| File | Purpose | Who Uses It |
|------|---------|-------------|
| `.ralph/tasks/RALPH_TASK.md` | Task definition + success criteria | You define, agent reads |
| `.ralph/tasks/*.md` | Chained task files | You define, agent reads |
| `.ralph/state/progress.md` | What's been accomplished | Agent writes after work |
| `.ralph/state/guardrails.md` | Lessons learned (Signs) | Agent reads first, writes after failures |
| `.ralph/state/activity.log` | Tool call log with token counts | Parser writes, you monitor |
| `.ralph/state/errors.log` | Failures + gutter detection | Parser writes, agent reads |
| `.ralph/state/.iteration` | Current iteration number | Loop reads/writes |

## Configuration

Default thresholds in `ralph-common.sh`:

```bash
MAX_ITERATIONS=20        # Max rotations before giving up
WARN_THRESHOLD=80000     # Tokens: send wrapup warning
ROTATE_THRESHOLD=100000  # Tokens: force rotation
DEFAULT_MODEL="opus"     # Claude Opus 4.5
```

Override via environment:
```bash
RALPH_MODEL=sonnet MAX_ITERATIONS=50 ./ralph-loop.sh
```

## Troubleshooting

### "claude CLI not found"

```bash
npm install -g @anthropic-ai/claude-code
```

### Agent keeps failing on same thing

Check `.ralph/state/errors.log` for the pattern. Either:
- Fix the underlying issue manually
- Add a guardrail to `.ralph/state/guardrails.md`

### Context rotates too frequently

The agent might be reading too many large files. Add a guardrail:
> "Don't read entire large files. Use grep to find relevant sections, then read specific line ranges."

### QC keeps failing

Check if criteria are verifiable. Each criterion should be:
- Specific and testable
- Produce observable artifacts (files, functions, tests)
- Not dependent on subjective assessment

### Task never completes

Ensure criteria are:
- Achievable in a reasonable number of iterations
- Not dependent on manual steps
- Clear enough to verify programmatically

## Workflows

### Basic (default)

```bash
./ralph-setup.sh  # Interactive setup → runs loop → done
```

### Human-in-the-loop (recommended for new tasks)

```bash
./ralph-once.sh   # Run ONE iteration
# Review changes...
./ralph-setup.sh  # Continue with full loop
```

### Scripted/CI

```bash
./ralph-loop.sh --branch feature/foo --pr -y
```

### Multi-task workflow

```bash
# Define task chain in RALPH_TASK.md with next_task links
./ralph-setup.sh  # Automatically processes entire chain
```

## Credits

- **Original technique**: [Geoffrey Huntley](https://ghuntley.com/ralph/) - the Ralph Wiggum methodology
- **Cursor implementation**: [Agrim Singh](https://github.com/agrimsingh/ralph-wiggum-cursor) - the Cursor port this is based on
- **Claude Code adaptation**: Additions include QC verification, task chaining, watchdog, and refined prompts

## License

MIT
