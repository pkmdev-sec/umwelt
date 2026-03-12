# Creating Custom Loaders

## Template

Create a new file in `~/.claude/umwelt/loaders/`:

```bash
#!/usr/bin/env bash
# umwelt: my-custom-loader
# Description: What this loader senses
set -euo pipefail

MODE="${1:-default}"

echo "=== MY CUSTOM CONTEXT ==="

case "$MODE" in
  minimal)
    # Minimal output — key facts only
    echo "key: value"
    ;;
  full)
    # Full output — everything
    echo "key: value"
    echo "detail: more info"
    ;;
  *)
    # Default — balanced
    echo "key: value"
    ;;
esac

echo "=== END MY CUSTOM CONTEXT ==="
```

## Setup

```bash
chmod +x ~/.claude/umwelt/loaders/my-custom-loader.sh
```

## Usage

```bash
# Direct
umwelt my-custom-loader
umwelt my-custom-loader --full

# In compose
umwelt compose git-context my-custom-loader

# With bang syntax
# !`umwelt my-custom-loader` Your question here
```

## Best Practices

1. **Support modes** — Implement `minimal`, `default`, and `full` variants
2. **Keep it fast** — Loaders run on every prompt in hook mode. Target <500ms
3. **Use section markers** — `=== SECTION ===` / `=== END SECTION ===` for structured parsing
4. **Skip when irrelevant** — Check prerequisites early and exit 0 with no output
5. **Estimate tokens** — Keep default mode under 200 tokens for budget-friendliness
