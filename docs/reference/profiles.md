# Profiles Reference

## dev

**Purpose:** General development context.

**Loaders:** git-context + test-status (--last) + env-summary (--minimal) + project-summary

```bash
umwelt profile dev          # Standard
umwelt profile dev --full   # All loaders at full detail
```

**Estimated tokens:** 400-800

**Best for:** "What should I work on?", "Fix the bug", "Add this feature"

---

## debug

**Purpose:** Deep debugging context.

**Loaders:** env-summary (--full) + docker-status (--full) + error scanning + process listing

```bash
umwelt profile debug
```

**Estimated tokens:** 600-1200

**Best for:** "Why is this crashing?", "Debug the connection issue", system-level problems

---

## review

**Purpose:** Code review context.

**Loaders:** git-context (--diff) + branch comparison + test-status

```bash
umwelt profile review              # Diff against main
umwelt profile review develop      # Diff against develop
```

**Estimated tokens:** 300-600

**Best for:** "Review my changes", "Is this PR ready?", code quality checks

---

## deploy

**Purpose:** Deployment readiness check.

**Loaders:** git-context + deps-audit (--full) + docker-status + api-health + build check

```bash
umwelt profile deploy
```

**Output:** Structured checklist with **READY** / **NOT READY** verdict.

**Estimated tokens:** 500-1000

**Best for:** "Is this ready to ship?", "Pre-deploy check", release validation

---

## minimal

**Purpose:** Ultra-light context for budget-constrained scenarios.

**Output:** Current working directory + git branch only.

```bash
umwelt profile minimal
```

**Estimated tokens:** <200

**Best for:** Haiku model, high budget usage, PreCompact preservation
