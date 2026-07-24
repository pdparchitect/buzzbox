# Buzzbox

<img width="3456" height="2234" alt="tpsmlhvh-6903 euw devtunnels ms_(MacBook Pro 16_)" src="https://github.com/user-attachments/assets/725ae16b-fd37-4572-85c1-9226261a6e8e" />

Buzzbox is a browser-accessible Linux desktop with a complete local
[Buzz](https://github.com/block/buzz) workspace and the Codex and Claude Code
agent runtimes already installed.

One command boots:

- the Buzz desktop as the default full-screen application;
- a local Buzz relay at `ws://127.0.0.1:3000`;
- PostgreSQL, Redis, and MinIO for the relay;
- the bundled `buzz`, `buzz-acp`, `buzz-agent`, and `buzz-dev-mcp` tools;
- Codex, Claude Code, `codex-acp`, and `claude-agent-acp`; and
- the Openbox/KasmVNC desktop adapted from the Pantalk example.

The environment is self-contained. It does not require a host Docker socket or
a separate Compose stack.

## Run

From this directory:

```bash
make up
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
