# Loaders Reference

## git-context

Senses git repository state.

```bash
umwelt git-context                 # Branch, status, recent commits
umwelt git-context --minimal       # Branch and status only
umwelt git-context --full          # + staged and unstaged diffs
umwelt git-context --diff          # Alias for --full
```

**Output includes:** current branch, working tree status, last 5 commits, staged changes, unstaged changes, stash count.

**Skips when:** Not in a git repository.

**Estimated tokens:** 80-200 (varies by dirty state).

---

## test-status

Senses test framework state.

```bash
umwelt test-status                 # Framework detection + last results
umwelt test-status --last          # Check cached test results
umwelt test-status --run           # Actually run tests and report
umwelt test-status --coverage      # Show coverage summary
```

**Detects:** vitest, jest, mocha, npm test, pytest, cargo test, go test, swift test.

**Skips when:** No test framework detected.

**Estimated tokens:** 60-150.

---

## env-summary

Senses system environment.

```bash
umwelt env-summary                 # OS, shell, runtimes, project type
umwelt env-summary --minimal       # OS and runtimes only
umwelt env-summary --full          # + disk, memory, load, Claude env vars
```

**Output includes:** OS version, shell, Node/Python/Rust/Go versions, package managers, project type detection.

**Estimated tokens:** 100-250.

---

## docker-status

Senses Docker state.

```bash
umwelt docker-status               # Running containers, compose services
umwelt docker-status --minimal     # Container count only
umwelt docker-status --full        # + disk usage, recent logs
```

**Skips when:** Docker not installed or not running.

**Estimated tokens:** 80-200.

---

## deps-audit

Senses dependency health.

```bash
umwelt deps-audit                  # Lock freshness, dep counts
umwelt deps-audit --full           # + npm audit, outdated check
```

**Detects:** npm/pnpm/yarn/bun, pip/poetry, cargo, go modules.

**Skips when:** No package manager files found.

**Estimated tokens:** 60-150.

---

## project-summary

Senses project structure.

```bash
umwelt project-summary             # File counts, structure, entry points
umwelt project-summary --full      # + npm scripts, README excerpt
```

**Output includes:** file count by type, directory structure (depth 2), entry points, configuration files, tech stack.

**Estimated tokens:** 100-200.

---

## api-health

Senses network service state.

```bash
umwelt api-health                  # Scan common local ports
umwelt api-health --full           # + .env API URLs

# Custom endpoints
UMWELT_API_ENDPOINTS="https://api.example.com/health,http://localhost:4000/ping" umwelt api-health
```

**Scans:** Ports 3000, 3001, 4000, 5000, 5173, 8000, 8080, 8443.

**Skips when:** No services responding on common ports.

**Estimated tokens:** 50-120.
