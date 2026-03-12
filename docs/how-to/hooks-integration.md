# Hook Integration

## Overview

Umwelt integrates with Claude Code's hooks system to automatically inject environment context at key moments — no bang syntax needed.

## Available Hook Events

| Event | When It Fires | Best Loader |
|-------|--------------|-------------|
| `SessionStart` | New Claude Code session | `project-summary` or `profile dev` |
| `UserPromptSubmit` | Every user message | `git-context` (with diff mode) |
| `SubagentStart` | Sub-agent spawned | `git-context --minimal` |
| `PreCompact` | Before context compaction | `profile minimal` |

## Install a Hook

```bash
# Single loader on an event
umwelt install-hook UserPromptSubmit git-context

# Profile on an event
umwelt install-hook SessionStart "profile dev"
```

This modifies `~/.claude/settings.json` to add the appropriate hook configuration.

## Uninstall a Hook

```bash
umwelt uninstall-hook UserPromptSubmit git-context
```

## Manual Hook Configuration

Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "umwelt --diff git-context",
        "statusMessage": "umwelt: scanning environment",
        "timeout": 10
      }]
    }]
  }
}
```

## Unified Hook (Umwelt + Sigil)

If you use both Umwelt and Sigil, install the unified hook:

```json
{
  "hooks": {
    "UserPromptSubmit": [{
      "hooks": [{
        "type": "command",
        "command": "umwelt unified UserPromptSubmit",
        "statusMessage": "umwelt: unified context",
        "timeout": 30
      }]
    }]
  }
}
```

The unified engine auto-detects Sigil templates and combines both into a single optimized injection.

## Recommended Setup

```bash
# Full scan on session start
umwelt install-hook SessionStart "profile dev"

# Lightweight diffs on every prompt
umwelt install-hook UserPromptSubmit "git-context --diff"

# Preserve state before compaction
umwelt install-hook PreCompact "profile minimal"
```
