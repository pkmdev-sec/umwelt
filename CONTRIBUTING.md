# Contributing to Umwelt

## Getting Started

1. Fork the repository
2. Clone your fork: `git clone https://github.com/YOUR_USERNAME/umwelt.git`
3. Create a feature branch: `git checkout -b feature/my-feature`

## Development

### Project Structure

- `umwelt` — Main CLI executable
- `lib/` — Shared libraries
- `loaders/` — Environment sensors (one per file)
- `profiles/` — Task-specific loader combinations
- `tests/` — Test suites

### Running Tests

```bash
./umwelt test              # Everything
./umwelt test loaders      # Loaders only
./umwelt test profiles     # Profiles only
./umwelt test cli          # CLI commands only
```

### Code Style

- Shell scripts use `set -euo pipefail`
- Use `#!/usr/bin/env bash` shebang
- 2-space indentation
- Functions use lowercase with underscores: `my_function_name`
- Constants use uppercase: `MY_CONSTANT`
- Add mode support (`minimal`, `default`, `full`) to all loaders

### Adding a New Loader

1. Create `loaders/my-loader.sh`
2. Follow the template in [custom loaders docs](docs/how-to/custom-loaders.md)
3. Add tests in `tests/test_loaders.sh`
4. Update the loader count in README

### Adding a New Profile

1. Create `profiles/my-profile.sh`
2. Define which loaders to run and at what detail level
3. Add tests in `tests/test_profiles.sh`
4. Document in README and `docs/reference/profiles.md`

## Submitting Changes

1. Run `./umwelt test` and ensure all tests pass
2. Commit with a clear message: `feat: add redis loader`
3. Push to your fork
4. Open a pull request against `main`

## Commit Convention

- `feat:` — New feature
- `fix:` — Bug fix
- `docs:` — Documentation only
- `test:` — Test additions/changes
- `refactor:` — Code restructuring
- `perf:` — Performance improvement
