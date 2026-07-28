# Changelog

All notable changes to Buzzbox are documented here, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.5.0] - 2026-07-28

### Changed

- Update Buzz Desktop to 0.5.0 and the matching relay to upstream commit
  `4a977c5`.

## [0.4.0] - 2026-07-27

### Added

- Publish native `linux/amd64` and `linux/arm64` images under the same release
  tags. ARM64 builds the Buzz Tauri desktop and its sidecars from the exact
  pinned upstream source tag and commit because upstream publishes a Linux
  desktop package only for AMD64.
- Build and smoke-test each architecture on a native GitHub runner, including
  the visible Buzz Desktop window, headed browser, relay, PostgreSQL, Redis,
  MinIO, and agent runtimes, then assemble the release from per-architecture
  digests.

### Changed

- Select architecture-matched Goose, yq, Cortile, KasmVNC, Buzz relay, and
  MinIO artifacts. Keep Google Chrome on AMD64 and use signed Debian Chromium
  on ARM64 behind the same launcher, GTK theme, preferences, and policies.
- Make local builds default to the host architecture while retaining
  `PLATFORM=linux/amd64` and `PLATFORM=linux/arm64` overrides.
- Pin GTK and Chrome's Linux UI typography to Noto Sans 9, matching every
  Openbox title, menu, and on-screen-display font declaration instead of
  inheriting GTK's larger Sans 10 default.
- Give Chrome a self-contained, Buzz-branded near-black GTK system theme that
  darkens native menus and popups as well as the tab strip, active tab,
  toolbar, controls, and address field; render Chrome's window controls from
  the same XBM masks and state colors as Openbox, square the GTK-controlled
  outer frame corners, and replace the bundled welcome card with the
  terminal's ASCII banner on pure black.
- Remove the window handle, which drew a second line under the client area
  with a resize grip boxed off at each end. Resizing stays available through
  the window edges and corners and through Alt+right-drag anywhere on the
  frame.
- Declare Codex's sandbox mode as `danger-full-access` at boot. Codex sandboxes
  commands with bubblewrap, which cannot create a user namespace inside the
  container, so no sandbox mode is enforceable and Codex warned on every start
  about falling back to its bundled copy. Override with `BUZZBOX_CODEX_SANDBOX_MODE`.
- Start terminals in `/workspace` instead of the home directory, so the desktop
  and the agent harness work in the same tree. Openbox chdirs to `$HOME` at
  startup whatever directory it was started from and hands that to everything
  it launches, so this is set in the shell - the one place every terminal
  passes through - and only when the shell landed in `$HOME`, which leaves
  non-interactive shells and deliberate directories alone.
- Widen the window grab margin with client padding. With the handle gone the
  frame offered 1px to grab at the bottom against a 28px titlebar, so the
  bottom corners were nearly unhittable. Client padding adds frame around the
  client and paints it in the frame background, taking the grabbable ring from
  1px to 7px without drawing anything new.
- Record the workspace as trusted for Codex and Claude Code at boot, matching
  Buzznode, so a harness started against `/workspace` does not stop on a
  per-directory trust prompt. Set `BUZZBOX_TRUST_WORKSPACE=false` to keep the
  prompts.

## [0.3.0] - 2026-07-26

### Added

- Add optional `BUZZ_NETWORK` support for connecting independent Buzznode
  containers over a private Docker network.
- Add `PUBLIC_RELAY_URL` so remote nodes receive usable relay and media URLs.
- Add **Create New Agent for Buzznode**, which uses `buzz agents draft-create`
  to submit a prefilled owner-reviewed agent, detects the newly saved identity,
  and produces its enrollment bundle.
- Add **Move Existing Agent to Buzznode**, which exports a stopped managed
  agent's identity, relay, authorization, and response policy.
- Keep the enrollment terminal open, distinguish the bundle from Buzz's
  displayed `nsec`, and copy the completed `buzznode-v1:` bundle to the desktop
  clipboard.
- Map Kitty's `Ctrl+C` to copy selected text or interrupt when nothing is
  selected, make it copy-only in enrollment windows, add `Ctrl+V` paste, and
  turn a completed menu-launched enrollment flow into a normal terminal.
- Add ANSI headings, steps, success states, warnings, errors, and styled prompts
  to the enrollment flow, with `NO_COLOR` support.
- Keep local channel discovery on each agent's workspace relay, carry that relay
  through newly created agent bundles, and translate only Buzzbox's own internal
  relay address to `PUBLIC_RELAY_URL`.
- Add an interactive runtime authentication chooser. Codex offers desktop
  browser, device code, API key, and status flows; Claude Code offers
  subscription, Console, long-lived setup token, SSO, and status flows.
- Add `make size-report` and `tools/size-report.sh`, which measure the
  graphical stack's share of the image as an apt dependency closure.
- Document the graphical stack's measured cost and the rationale for keeping it
  in `IMAGE-SIZE.md`.

### Fixed

- Add the named volumes to the quick-start `docker run` and `podman run`
  commands. The image declares those seven paths as volumes, so the documented
  command was creating anonymous volumes: the Buzz identity, relay database,
  media store, and agent logins were discarded whenever the container was
  replaced, and the orphaned volumes stayed on disk.
- Enable KasmVNC `hw3d` and Chrome's GPU flags only when the desktop user can
  actually open the render node. A passed-through node is normally
  `root:render 0660` and the host's render group does not exist in this image,
  so testing for presence alone announced GPU acceleration that could not work
  and left Xvnc and Chrome pointed at a device they could not open. The startup
  log now distinguishes an absent node from an inaccessible one.
- Pass only `/dev/dri/renderD*` rather than the whole `/dev/dri` directory,
  which also handed over the `card*` DRM master/modesetting node.
- Normalize ownership of the persistent volumes once per volume lifetime
  instead of recursing `/workspace`, the PostgreSQL cluster, and the MinIO
  object store on every boot, which grew into minutes of startup latency once
  they held real data.
- Quote every value interpolated into a `su -c` string with `printf %q`. The S3
  credentials, bucket, relay private key, git-hook secret, web directories, and
  `BUZZBOX_STATE_DIR` can all be supplied through the environment, and a space
  or quote character in one broke the command being built instead of failing
  cleanly.
- Install the shutdown trap before the first backing service starts, so a stop
  during startup still shuts PostgreSQL down cleanly.
- Probe the relay in `HEALTHCHECK` only when `BUZZ_RELAY_AUTOSTART` is enabled.
  Probing port 8080 unconditionally held a relay-less container unhealthy
  forever.

### Removed

- Remove the `xorg` metapackage and `x11-xserver-utils` from the desktop layer.
  KasmVNC supplies its own X server, and the replaced `xstartup` never reaches
  KasmVNC's `xrdb` call, so both were unreachable. This drops about 86 MiB,
  including `udev`, `man-db`, and the apport chain. `xauth`, `xkb-data`,
  `x11-xkb-utils`, and `xfonts-base` are now explicit so an autoremove cannot
  take them out.

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
