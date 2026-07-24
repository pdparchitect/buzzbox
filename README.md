# Buzzbox

<img width="1760" height="894" alt="98b82e2c-1339-4ca7-99ab-4b49f8bb604d" src="https://github.com/user-attachments/assets/c23ef9c5-a26f-4a94-a540-286ad50df0bd" />

## What is Buzzbox?

[Buzz](https://github.com/block/buzz) is a shared workspace where people and AI
agents work together. It brings conversations, channels, projects, workflows,
media, and search into one place. Agents join the same rooms as people, so their
work and decisions remain visible to the whole team.

Buzzbox is a ready-to-run Buzz environment that opens in your web browser. One
command starts the Buzz desktop, its local relay, storage, and supporting
services. Codex and Claude Code are included as optional agents you can add to
the workspace.

<img width="3456" height="2234" alt="tpsmlhvh-6903 euw devtunnels ms_(MacBook Pro 16_) (1)" src="https://github.com/user-attachments/assets/2b110431-d484-4473-959d-2ca6a1dfb153" />

## Quick start

Buzzbox is published as a complete image on GitHub Container Registry.

With Docker:

```bash
docker pull ghcr.io/pdparchitect/buzzbox:latest
docker run --detach \
  --name buzzbox \
  --platform linux/amd64 \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6903:6901 \
  --publish 127.0.0.1:3000:3000 \
  ghcr.io/pdparchitect/buzzbox:latest
```

With Podman:

```bash
podman pull ghcr.io/pdparchitect/buzzbox:latest
podman run --detach \
  --name buzzbox \
  --platform linux/amd64 \
  --restart unless-stopped \
  --shm-size 1g \
  --publish 127.0.0.1:6903:6901 \
  --publish 127.0.0.1:3000:3000 \
  ghcr.io/pdparchitect/buzzbox:latest
```

Open <http://127.0.0.1:6903>.

The same image works with other OCI-compatible runtimes, including containerd
with nerdctl. Use the same port mappings shown above. The image currently
targets `linux/amd64`; ARM hosts need x86-64 container emulation.

## What is inside?

Under the hood, Buzzbox is a browser-accessible Linux desktop with a complete
local [Buzz](https://github.com/block/buzz) workspace. Codex and Claude Code are
already installed and connected through their agent adapters.

One command boots:

- the Buzz desktop as the default full-screen application;
- a local Buzz relay at `ws://127.0.0.1:3000`;
- PostgreSQL, Redis, and MinIO for the relay;
- the bundled `buzz`, `buzz-acp`, `buzz-agent`, and `buzz-dev-mcp` tools;
- Codex, Claude Code, `codex-acp`, and `claude-agent-acp`; and
- the Openbox/KasmVNC desktop adapted from the Pantalk example.

The environment is self-contained. It does not require a host Docker socket or
a separate Compose stack.

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

On first boot, finish Buzz's local identity/community onboarding. Then
right-click the desktop and open **Agent Setup** to authenticate either coding
agent:

- **Log in to Codex** runs `codex login`.
- **Log in to Claude Code** runs `claude auth login`.

Buzz discovers both ACP adapters automatically. Choose Codex or Claude Code as
the runtime when creating or configuring an agent in Buzz.

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

To change the browser port, published relay port, or desktop resolution:

```bash
PORT=8080 RELAY_PORT=3001 RESOLUTION=1600x900 make up
```

The container still uses `ws://127.0.0.1:3000` internally. `RELAY_PORT` only
changes the host-side published port.

## What is pinned

The desktop and relay are pinned together rather than mixing a moving relay
with a released client:

| Component          | Version                   |
| ------------------ | ------------------------- |
| Buzz desktop       | `0.4.24`                  |
| Buzz relay         | upstream commit `710ed9f` |
| Codex              | `0.145.0`                 |
| Claude Code        | `2.1.219`                 |
| Codex ACP adapter  | `1.1.7`                   |
| Claude ACP adapter | `0.62.0`                  |

The Buzz `.deb` is SHA-256 verified during the build. The relay and MinIO
stages use immutable container references.

## Persistence

The Makefile creates named volumes for:

- `/workspace`;
- the relay's PostgreSQL, Redis, MinIO, git, and generated-secret state;
- Buzz desktop config and application data;
- the Buzz agent nest at `~/.buzz`; and
- Codex and Claude authentication/configuration.

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

Keep the default loopback bind. Do not set `BIND_ADDRESS=0.0.0.0` unless the
environment is placed behind suitable authentication and network controls.

Each Buzzbox instance generates stable relay, git-hook, and MinIO secrets on
first boot and persists them in the services volume. No credentials are
committed.

## Releases

CI builds and smoke-tests every change. After successful CI on `main`, the
version-driven release workflows publish versioned and `latest` images to
`ghcr.io/pdparchitect/buzzbox` and create a matching GitHub Release.

See [RELEASES.md](RELEASES.md) for the release process, image tags, supported
architecture, and package visibility requirements.
