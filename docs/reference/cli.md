# CLI Reference

## Synopsis

```
umwelt <command> [options]
```

## Commands

### Loaders

```bash
umwelt git-context [--full|--minimal|--diff]
umwelt test-status [--run|--last|--coverage]
umwelt env-summary [--full|--minimal]
umwelt docker-status [--full|--minimal]
umwelt deps-audit [--full]
umwelt project-summary [--full]
umwelt api-health [--full]
```

### Profiles

```bash
umwelt profile dev [--full]
umwelt profile debug
umwelt profile review [base-branch]
umwelt profile deploy
umwelt profile minimal
```

### Smart Loading

```bash
umwelt event <event> [bash_cmd]        # Event-optimized loading
umwelt predict <message>               # Message-based loader prediction
umwelt smart <event> [message]         # Combined event + prediction
umwelt cached-context                  # Cache-split output
umwelt unified [event] [message]       # Unified Umwelt+Sigil assembly
```

### Compose

```bash
umwelt compose <loader1> <loader2> ... # Ad-hoc loader combination
```

### Cost Management

```bash
umwelt cost status                     # Current session cost
umwelt cost profile                    # Current cost mode
umwelt cost reset                      # Reset session cost
```

### Hook Management

```bash
umwelt install-hook <event> <loader|profile>
umwelt uninstall-hook <event> <loader>
umwelt hook-config [event] [profile]   # Generate hook JSON
umwelt hook-vars [event]               # Show hook template variables
```

### Management

```bash
umwelt list                            # List loaders and profiles
umwelt install                         # Symlink to ~/.local/bin/
umwelt test [loaders|profiles|cli|all] # Run self-tests
umwelt env-config [category]           # Generate .env configuration
umwelt --help, -h                      # Show help
umwelt --version, -v                   # Show version
```

## Global Flags

| Flag | Description |
|------|-------------|
| `--diff` | Enable diff-based injection (skip unchanged) |
| `--model <tier>` | Set model tier: `opus`, `sonnet`, `haiku` |
| `--budget <N>` | Set token budget (default: 10000) |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `UMWELT_DIR` | `~/.claude/umwelt` | Framework directory |
| `UMWELT_PROJECT_DIR` | `.` | Project directory for loaders |
| `UMWELT_API_ENDPOINTS` | — | Comma-separated API URLs |
| `CLAUDE_MODEL` | — | Model tier for auto-profile selection |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 2 | Invalid arguments |
| 3 | Loader not found |
| 4 | Profile not found |
