# Template: Fix Bug

## Bang Syntax (paste into Claude Code)
```
!`~/.claude/bang-framework/bang compose git-context test-status` I need to fix a bug: [DESCRIBE BUG HERE]
```

## What This Does
1. Loads current git state (branch, uncommitted changes, recent commits)
2. Loads test status (framework, last results, failures)
3. Feeds everything to Claude before your bug description

## Example
```
!`~/.claude/bang-framework/bang compose git-context test-status` The login form crashes when the email field is empty. It throws a TypeError in the validation handler.
```

## Variations
- **With full diff**: `!`\`bang git-context --diff\` to include the actual diff
- **With env**: `!`\`bang compose git-context test-status env-summary\` for env-related bugs
- **Run tests first**: `!`\`bang test-status --run\` to get fresh test results
