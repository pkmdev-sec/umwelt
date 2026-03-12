# Template: Code Review

## Bang Syntax (paste into Claude Code)
```
!`~/.claude/bang-framework/bang profile review main` Review my changes for this PR.
```

## What This Does
1. Loads git state with full diff
2. Compares current branch against base branch (default: main)
3. Lists all commits and changed files
4. Checks test status

## Example
```
!`~/.claude/bang-framework/bang profile review develop` Review these changes. Focus on security and error handling.
```

## Review Focus Options
```
# Security review
!`~/.claude/bang-framework/bang profile review main` Review for security issues — injection, auth, data exposure.

# Performance review
!`~/.claude/bang-framework/bang profile review main` Review for performance — N+1 queries, unnecessary renders, memory leaks.

# API review
!`~/.claude/bang-framework/bang profile review main` Review the API changes — backward compatibility, error codes, validation.
```
