# Buzzbox

<img width="1760" height="894" alt="98b82e2c-1339-4ca7-99ab-4b49f8bb604d" src="https://github.com/user-attachments/assets/c23ef9c5-a26f-4a94-a540-286ad50df0bd" />

## What is Buzzbox?

[Buzz](https://github.com/block/buzz) is a shared workspace where people and AI
agents work together. It brings conversations, channels, projects, workflows,
media, and search into one place. Agents join the same rooms as people, so their
work and decisions remain visible to the whole team.

Buzzbox is a ready-to-run Buzz environment that opens in your web browser. One
command starts the Buzz desktop, its local relay, storage, and supporting
services. Codex, Claude Code, and Goose are included as optional agents you can
add to the workspace.

Agents can also live outside the box.
[Buzznode](https://github.com/pdparchitect/buzznode) is the companion project: a
persistent computer for a single agent, with its own browser, terminal,
and filesystem, joining this or any other Buzz workspace over its relay.
Buzzbox's Agent Setup menu creates agents for it and hands over the enrollment
bundle, but Buzznode does not require Buzzbox to run.

> **Not an official Buzz project.** Buzzbox is an independent, community-built
> environment that packages published Buzz releases. It is not affiliated with,
> endorsed by, or sponsored by the Buzz project, [buzz.xyz](https://buzz.xyz),
> or Block, Inc. "Buzz" is used here only to describe what this image runs and
> what it is compatible with; all trademarks belong to their respective owners.
> Report problems with Buzzbox here, not to the upstream Buzz project.

<img width="3456" height="2234" alt="tpsmlhvh-6903 euw devtunnels ms_(MacBook Pro 16_) (3)" src="https://github.com/user-attachments/assets/5e6391fc-5d43-4986-bedd-f54c47a0dd8e" />

## Quick start

### Launcher (recommended)

The easiest way to run Buzzbox is with
[Launcher](https://github.com/pdparchitect/launcher). Launcher discovers,
installs, starts, stops, and updates Buzzbox while managing its container,
ports, and persistent storage for you.

1. [Download the latest Launcher release](https://github.com/pdparchitect/launcher/releases/latest).
2. Open **Marketplace**, select **Buzzbox**, and install it.
3. Choose **Open agent** when installation finishes.

Launcher uses Apple `container` on macOS and Docker on Linux.

### Run the container manually

Buzzbox is also published as a complete image on GitHub Container Registry.
Release tags contain native AMD64 and ARM64 images.

#### Docker

```bash
docker run --detach \
  --name buzzbox \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6903:6901 \
  --publish 127.0.0.1:3000:3000 \
  --volume buzzbox-workspace:/workspace \
  --volume buzzbox-services:/var/lib/buzzbox \
  --volume buzzbox-config:/home/agent/.config \
  --volume buzzbox-data:/home/agent/.local/share \
  --volume buzzbox-nest:/home/agent/.buzz \
  --volume buzzbox-codex:/home/agent/.codex \
  --volume buzzbox-claude:/home/agent/.claude \
  ghcr.io/pdparchitect/buzzbox:latest
```

#### Podman

```bash
podman run --detach \
  --name buzzbox \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6903:6901 \
  --publish 127.0.0.1:3000:3000 \
  --volume buzzbox-workspace:/workspace \
  --volume buzzbox-services:/var/lib/buzzbox \
  --volume buzzbox-config:/home/agent/.config \
  --volume buzzbox-data:/home/agent/.local/share \
  --volume buzzbox-nest:/home/agent/.buzz \
  --volume buzzbox-codex:/home/agent/.codex \
  --volume buzzbox-claude:/home/agent/.claude \
  ghcr.io/pdparchitect/buzzbox:latest
```

#### Apple container

Apple's [`container`](https://github.com/apple/container) tool requires Apple
silicon and macOS 26 or later. Start its service once, then allocate additional
memory for Buzz Desktop, the relay, PostgreSQL, Redis, MinIO, and the browser:

```bash
container system start

container run --detach \
  --name buzzbox \
  --memory 8g \
  --shm-size 1g \
  --publish 127.0.0.1:6903:6901 \
  --publish 127.0.0.1:3000:3000 \
  --volume buzzbox-workspace:/workspace \
  --volume buzzbox-services:/var/lib/buzzbox \
  --volume buzzbox-config:/home/agent/.config \
  --volume buzzbox-data:/home/agent/.local/share \
  --volume buzzbox-nest:/home/agent/.buzz \
  --volume buzzbox-codex:/home/agent/.codex \
  --volume buzzbox-claude:/home/agent/.claude \
  ghcr.io/pdparchitect/buzzbox:latest
```

Apple `container` preserves the named volumes and stopped container but does
not expose a Docker-style restart policy. Restart it with
`container start buzzbox`.

Open <http://127.0.0.1:6903>. Buzz launches automatically once the local relay
is ready.

Keep the named volumes. The image declares those seven paths as volumes, so a
run without them creates anonymous volumes instead: the Buzz identity, relay
database, media store, and agent logins are discarded whenever the container is
replaced, and the orphaned volumes stay on disk. See
[Persistence](#persistence).

The image also works with other OCI-compatible runtimes, including containerd
with nerdctl, using the port mappings above. Docker and Podman select the host's
native image automatically; Apple `container` selects ARM64 on Apple silicon.

## What is inside?

Under the hood, Buzzbox is a browser-accessible Linux desktop with a complete
local [Buzz](https://github.com/block/buzz) workspace. Codex, Claude Code, and
Goose are already installed with their required ACP support.

One command boots:

- the Buzz desktop as the default full-screen application;
- a local Buzz relay at `ws://127.0.0.1:3000`;
- PostgreSQL, Redis, and MinIO for the relay;
- the bundled `buzz`, `buzz-acp`, `buzz-agent`, and `buzz-dev-mcp` tools;
- Codex, Claude Code, Goose, `codex-acp`, and `claude-agent-acp`; and
- the Openbox/KasmVNC desktop, supplied by the Launcher desktop base.

The environment is self-contained. It does not require a host Docker socket or
a separate Compose stack.

The graphical stack is about a third of the AMD64 image, dominated by Chrome,
Buzz Desktop's WebKit runtime, software GL, and fonts rather than by the
desktop shell itself. ARM64 uses Chromium because Google does not publish
Chrome for Linux ARM64. See [IMAGE-SIZE.md](IMAGE-SIZE.md) for the measured
breakdown and reasoning, and run `make size-report` to reproduce it.

Serving a web application instead of a desktop was considered and set aside,
and here the case against it is stronger than in Buzznode. The relay's own web
clients are already present at `/srv/buzz`, so the browser-only path partly
exists — but Buzzbox is meant to run Buzz Desktop, which is a native Tauri
application. Replacing it with a web UI would mean reimplementing the very
client this environment exists to provide, and building a second product to
design, secure, and maintain alongside it. It would also save less than it
appears: WebKitGTK is Buzz Desktop's runtime, Chrome handles login flows, and
software GL rasterises for both, so the large items stay regardless. Openbox,
tint2, and the rest of the desktop shell add roughly 22 MiB on top of that.
Buzzbox therefore lives off the land, surfacing the real desktop client through
KasmVNC rather than substituting a thinner one — which also keeps it aligned
with Buzznode, so agent behaviour developed against one desktop transfers to
the other.

## Relationship to the Launcher desktop base

Buzzbox is a product image on top of
`ghcr.io/pdparchitect/launcher-image-base-desktop`, the same substrate the
other Launcher desktops use. The base supplies Ubuntu, Node, KasmVNC, Openbox,
Cortile, tint2, kitty, the browser, the GTK theme, the `agent` account, and the
entrypoint. This repository supplies only Buzz.

That split is what the source layout reflects:

| Path                             | What it is                                         |
| -------------------------------- | -------------------------------------------------- |
| `Dockerfile`                     | The Buzz Desktop build, the relay stack, the agent runtimes |
| `overlay/`                       | Files copied over the base's defaults               |
| `overlay/etc/desktop/startup.d/` | Programs the entrypoint runs before the session     |
| `overlay/etc/desktop/session.d/` | Programs the session runs once it has a display     |

Two consequences are worth knowing:

- The desktop user is `agent`, homed at `/home/agent`, and desktop logs live in
  `/var/log/launcher-desktop`. Buzz's own service state stays in
  `/var/lib/buzzbox`.
- Desktop-level settings use the base's names — `DESKTOP_VNC_STATS` and
  `DESKTOP_TITLE`. Buzz-level settings keep their `BUZZBOX_*` and `BUZZ_*`
  names.

To build against a different base, override `DESKTOP_IMAGE`:

```bash
make up DESKTOP_IMAGE=ghcr.io/pdparchitect/launcher-image-base-desktop:0.2.0
```

## Build locally

From this directory:

```bash
make up
```

The Makefile uses Docker by default. To build and run with Podman:

```bash
make up DOCKER=podman
```

Open <http://127.0.0.1:6903>. Buzz launches automatically after the local relay
is ready.

### Test with a local Buzznode

Buzzbox and [Buzznode](https://github.com/pdparchitect/buzznode) are independent
projects. They coordinate only through a named Docker network and the relay URL;
neither Makefile depends on the other directory.

Clone Buzznode next to this repository, then start Buzzbox from this directory:

```bash
make up \
  BUZZ_NETWORK=buzz-local \
  PUBLIC_RELAY_URL=ws://buzzbox:3000
```

Then, from the separate `buzznode` directory:

```bash
make up \
  BUZZ_NETWORK=buzz-local \
  RELAY_URL=ws://buzzbox:3000
```

Both Makefiles create `buzz-local` if it does not exist. Docker DNS resolves
the Buzzbox container name `buzzbox` from Buzznode, so the relay does not need
to be published on a non-loopback host interface.

Open Buzzbox at <http://127.0.0.1:6903> and Buzznode at
<http://127.0.0.1:6904>. The local Buzzbox relay does not require an API token,
so leave Buzznode's token field empty.

In Buzzbox, right-click the desktop and choose **Agent Setup → Create New Agent
for Buzznode**. Choose the real channel, agent name, and instructions in the
terminal. Buzzbox submits those values with `buzz agents draft-create`; review
the prefilled owner-approval form in Buzz and choose Save. The enrollment
window detects the newly minted identity and displays a `buzznode-v1:` bundle.
The terminal remains open and copies the bundle to the Buzzbox desktop
clipboard. Paste it into Buzznode's setup window, then return and press Enter.
In an enrollment terminal, `Ctrl+C` always copies instead of interrupting the
workflow. Other terminals copy selected text and retain the usual interrupt
behavior when nothing is selected. After confirming the bundle has been
pasted, the enrollment window becomes a normal Buzzbox terminal and remains
open until you close it or type `exit`.

The `nsec1...` value shown during Buzz's confirmation screen is only the agent
private key. The enrollment bundle is the longer line beginning
`buzznode-v1:`; it also carries the relay, authorization, and response policy.
It preserves an external workspace relay. When the agent uses Buzzbox's bundled
relay, the internal address is translated to `PUBLIC_RELAY_URL`, which must be
reachable from the destination Buzznode.

To relocate an agent you already created, stop its local harness and choose
**Agent Setup → Move Existing Agent to Buzznode** instead. The bundle carries
the selected agent's relay URL, private key, authorization tag, and response
policy, so the node joins as that agent rather than creating another identity.

The enrollment bundle is base64-encoded, not encrypted, and contains the agent
private key. Treat it like a password. Do not restart the same agent in Buzzbox
after its harness is running on Buzznode.

Run the connection check from the Buzznode directory:

```bash
make connection-test \
  BUZZ_NETWORK=buzz-local \
  RELAY_URL=ws://buzzbox:3000
```

`PUBLIC_RELAY_URL` is the address Buzzbox advertises to external clients and
uses to construct media URLs. The default remains `ws://127.0.0.1:3000` for a
standalone Buzzbox.

On first boot, finish Buzz's local identity/community onboarding. Then
right-click the desktop and open **Agent Setup** to configure a coding agent:

- **Create New Agent for Buzznode** submits a prefilled, owner-reviewed draft
  through Buzz CLI and exports only the newly created identity.
- **Move Existing Agent to Buzznode** exports a stopped managed agent.
- **Sign in to Codex...** lets you choose desktop browser, device code, or API
  key authentication.
- **Sign in to Claude Code...** lets you choose Claude subscription, Anthropic
  Console, long-lived setup-token, or organization SSO authentication.
- **Configure Goose** runs `goose configure`.

Buzz discovers the Codex and Claude Code ACP adapters plus Goose's native ACP
runtime automatically. Choose Codex, Claude Code, or Goose when creating or
configuring an agent in Buzz.

Do not use `buzz-admin generate-key` for a Buzznode agent. That command only
creates a raw Nostr keypair; it does not create the Buzz agent profile,
ownership attestation, or channel memberships that a managed agent receives.

Useful commands:

```bash
make check
make build
make run
make recreate
make test
make smoke
make logs
make relay-log
make status
make stop
```

To change the browser port or published relay port:

```bash
PORT=8080 RELAY_PORT=3001 make up
```

Two container-level variables are also read at boot. `BUZZBOX_STATE_DIR`
relocates the backing-service state away from `/var/lib/buzzbox`, and
`BUZZ_RELAY_AUTOSTART=false` starts the desktop without the bundled relay, for
pointing Buzz Desktop at an external one. The health check skips its relay
probe when the relay is not expected.

The container still uses `ws://127.0.0.1:3000` internally. `RELAY_PORT` only
changes the host-side published port.

## What is pinned

The desktop and relay are pinned together rather than mixing a moving relay
with a released client:

| Component          | Version                   |
| ------------------ | ------------------------- |
| Buzz desktop       | `0.5.3`                   |
| Buzz relay         | upstream commit `3a96ace` |
| Codex              | `0.145.0`                 |
| Claude Code        | `2.1.220`                 |
| Goose              | `1.44.0`                  |
| Codex ACP adapter  | `1.1.7`                   |
| Claude ACP adapter | `0.62.0`                  |

The Buzz `.deb` and Goose CLI archive are SHA-256 verified during the build.
The relay and MinIO stages use immutable container references.

## Persistence

The Makefile creates named volumes for:

- `/workspace`;
- the relay's PostgreSQL, Redis, MinIO, git, and generated-secret state;
- Buzz desktop config and application data;
- the Buzz agent nest at `~/.buzz`; and
- Codex, Claude, and Goose authentication/configuration.

`make stop` removes the container but keeps these volumes. `make recreate`
therefore preserves identities, messages, service data, and agent logins.

## Services

All backing services bind only inside the container:

| Service      | Address          |
| ------------ | ---------------- |
| Buzz relay   | `0.0.0.0:3000`   |
| Relay health | `127.0.0.1:8080` |
| PostgreSQL   | `127.0.0.1:5432` |
| Redis        | `127.0.0.1:6379` |
| MinIO        | `127.0.0.1:9000` |
| KasmVNC      | `0.0.0.0:6901`   |

Only KasmVNC and the Buzz relay are published by the Makefile, both on
`127.0.0.1` by default.

## Security posture

This is a trusted, single-user development workstation:

- KasmVNC browser authentication and TLS are disabled.
- The local relay does not require an API token or relay membership.
- The `agent` user has passwordless sudo.
- Authenticated coding agents can operate in `/workspace`.
- Codex runs with `sandbox_mode = "danger-full-access"`. Its bubblewrap sandbox
  cannot create a user namespace inside a container, so no sandbox mode is
  enforceable here whatever is configured; the setting states what is true
  rather than implying a boundary that does not exist. The boundary is the
  container. Override with `BUZZBOX_CODEX_SANDBOX_MODE`.

Keep the default loopback bind. Do not set `BIND_ADDRESS=0.0.0.0` unless the
environment is placed behind suitable authentication and network controls.

Each Buzzbox instance generates stable relay, git-hook, and MinIO secrets on
first boot and persists them in the services volume. No credentials are
committed.

### Authentication is delegated by design

Access to the desktop web application is not authenticated. KasmVNC is started
with `-disableBasicAuth` and TLS disabled, and the KasmVNC password written on
first boot exists only because KasmVNC checks that the file is there. It is not
an access control and should not be treated as one. The same applies to the
local relay on port `3000`, which requires no API token or relay membership.

This is a deliberate decision, and built-in authentication is not planned.
A Buzzbox reachable beyond loopback is expected to be fronted by whichever
access layer already suits its environment: a conventional reverse proxy, or
preferably a zero-trust access proxy such as Cloudflare Access or an equivalent
identity-aware proxy. Those systems already own identity, session lifetime,
device posture, revocation, and audit, and in an enterprise deployment they are
the layer that has to be satisfied regardless of what the box does.

Adding a second mechanism inside the box would not strengthen that arrangement,
it would compete with it: two session models to keep aligned, two places to
revoke an operator, and an open question about which one wins when they
disagree. Leaving the box unauthenticated keeps a single enforcement point and
a single path forward — the proxy is the front door, and there is no second
door to reason about or accidentally leave open.

This applies to both published ports. If `PUBLIC_RELAY_URL` is used so remote
Buzznodes can reach the relay, terminate that `wss://` endpoint at the same
access layer rather than exposing port `3000` on its own. Until an access layer
is in place, the loopback bind is the only boundary, and exposing Buzzbox
without one publishes an unauthenticated root shell alongside an open relay.

## Releases

CI builds and smoke-tests every change. After successful CI on `main`, the
version-driven release workflows publish versioned and `latest` images to
`ghcr.io/pdparchitect/buzzbox` and create a matching GitHub Release.

See [RELEASES.md](RELEASES.md) for the release process, image tags, supported
architecture, and package visibility requirements.
