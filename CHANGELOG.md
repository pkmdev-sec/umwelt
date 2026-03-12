# Changelog

## [2.1.0] — 2026-03-12

### Added
- Diff-based injection engine (80-90% token savings on repeated scans)
- Token-aware profiling with auto-downgrade
- Cache-friendly STABLE/VOLATILE output splitting
- Event-optimized loading (full scan → diff-only on subsequent calls)
- Model-aware profiles (Opus/Sonnet/Haiku auto-selection)
- Cost-conscious scanning with session budget tracking
- Intelligent loaders with self-relevance detection
- Predictive context loading from user message analysis
- Smart PreCompact for context compaction survival
- Unified context engine (Umwelt + Sigil integration)
- Minimal profile (<200 tokens)
- Adaptive routing script
- Cache warming script for SessionStart
- PreCompact preservation script

### Changed
- Rebranded from bang-framework to Umwelt
- Renamed all CLI commands and environment variables
- Updated documentation with methodology-backed naming

## [1.0.0] — 2026-03-10

### Added
- Initial release
- 7 environment loaders (git, test, env, docker, deps, project, api)
- 4 profiles (dev, debug, review, deploy)
- Parallel execution engine
- Hook integration system
- Self-test suite (100+ assertions)
- Bang syntax support
- Custom slash commands
- Template prompts
