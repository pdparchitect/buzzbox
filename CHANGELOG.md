# Changelog

All notable changes to Buzzbox are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0] - 2026-07-24

### Added

- Add a browser-accessible Buzz desktop based on the Pantalk example's
  Openbox/KasmVNC environment.
- Bundle Buzz Desktop 0.4.24 and the matching relay from upstream commit
  `710ed9f`.
- Boot PostgreSQL, Redis, MinIO, and the Buzz relay inside the Buzzbox
  container.
- Preinstall Codex, Claude Code, and both Buzz-supported ACP adapters.
- Persist the relay, desktop, workspace, Codex, and Claude state in named
  Docker volumes.
