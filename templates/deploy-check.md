# Template: Deploy Check

## Bang Syntax (paste into Claude Code)
```
!`~/.claude/bang-framework/bang profile deploy` Is this safe to ship to production?
```

## What This Does
1. Checks git working tree is clean
2. Verifies branch is pushed to remote
3. Audits dependencies (lock freshness, vulnerabilities)
4. Checks Docker containers and compose services
5. Pings API endpoints
6. Verifies build output exists
7. Gives READY/NOT READY verdict

## Example
```
!`~/.claude/bang-framework/bang profile deploy` We're deploying v2.3.0 to production. Check everything.
```

## Variations
```
# Quick check (git + build only)
!`~/.claude/bang-framework/bang compose git-context deps-audit` Quick deploy check — anything blocking a release?

# With API health
!`BANG_API_ENDPOINTS="https://api.staging.example.com/health,https://api.prod.example.com/health" ~/.claude/bang-framework/bang profile deploy` Check staging and prod APIs before deploy.
```
