# Changelog

All notable changes to Buzzbox are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.2.0] - 2026-07-25

### Changed

- Update Buzz Desktop to 0.4.26 and the matching relay to upstream commit
  `0096d71`.
- Replace the rotating desktop wallpapers with the Buzz chartreuse dot grid
  and match the welcome screen's ASCII wordmark to the same yellow.
- Move Welcome to the top of the desktop menu and open it in a larger terminal
  sized for the wordmark.
- Disable Kitty's window-close confirmation prompt.
- Change the shell prompt label from green `@agent` to Buzz-yellow `@buzzbox`.
- Move the `agent` user's home directory from `/home/agent` to
  `/home/buzzbox`.
- Add Goose 1.44.0 as a native ACP runtime and expose its configuration and
  status commands in the desktop menu.
- Update Claude Code to 2.1.220; Codex remains on the current 0.145.0 release.

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
- Add direct pull-and-run instructions for Docker, Podman, nerdctl, and
  compatible OCI container runtimes.
- Add CI, automatic release tagging, GHCR image publishing, SBOM generation,
  provenance attestations, and GitHub Releases.
