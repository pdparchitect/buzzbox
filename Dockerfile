# syntax=docker/dockerfile:1.7
#
# Buzzbox - a browser-accessible Buzz desktop, local relay, and coding
# agent workstation.
#
# The Openbox/KasmVNC desktop, its browser, and the Ubuntu/Node foundation
# under it all come from the Launcher desktop base. Nothing about the desktop
# is configured here: branding and product programs are installed through
# overlay/, which is copied over the base's defaults, and the Buzz stack is
# started from the base entrypoint's /etc/desktop/startup.d hook.
#
# The desktop release and relay image are pinned to the same upstream commit.
# Upstream publishes the Linux desktop package only for AMD64; ARM64 builds the
# same immutable source tag and exact commit natively.

ARG DESKTOP_IMAGE=ghcr.io/pdparchitect/launcher-image-base-desktop:0.1.6

ARG BUZZ_RELAY_IMAGE=ghcr.io/block/buzz:sha-3e48f1b
FROM ${BUZZ_RELAY_IMAGE} AS buzz-relay

FROM minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e AS minio
FROM minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727 AS minio-client

# Build a package with the same layout on both architectures. AMD64 retains
# upstream's verified release .deb; ARM64 builds the pinned Tauri desktop and
# its sidecars from source because upstream does not publish a Linux ARM64 .deb.
FROM rust:1.95-bookworm AS buzz-desktop

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ARG BUZZ_VERSION=0.5.2
ARG BUZZ_DEB_SHA256=3f022bc31ed579e045946e6acab8483639bcb94e62c1e70f67b97b22f8f879c5
ARG BUZZ_SOURCE_SHA=3e48f1b2365d326ee1c9582448d86a99b44ecd5d

RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    apt-get update; \
    if [ "$arch" = "arm64" ]; then \
        apt-get install -y --no-install-recommends \
            ca-certificates curl git gnupg \
            build-essential file cmake \
            libasound2-dev libayatana-appindicator3-dev libgtk-3-dev \
            librsvg2-dev libssl-dev libwebkit2gtk-4.1-dev libxdo-dev \
            patchelf pkg-config xdg-utils; \
        curl -fsSL https://deb.nodesource.com/setup_24.x | bash -; \
        apt-get install -y --no-install-recommends nodejs; \
        corepack enable; \
        corepack prepare pnpm@10.13.1 --activate; \
    else \
        apt-get install -y --no-install-recommends ca-certificates curl; \
    fi; \
    rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    mkdir -p /out; \
    if [ "$arch" = "amd64" ]; then \
        buzz_deb="/out/Buzz.deb"; \
        curl -fsSL \
            "https://github.com/block/buzz/releases/download/v${BUZZ_VERSION}/Buzz_${BUZZ_VERSION}_amd64.deb" \
            -o "$buzz_deb"; \
        echo "${BUZZ_DEB_SHA256}  ${buzz_deb}" | sha256sum -c -; \
    elif [ "$arch" = "arm64" ]; then \
        git clone --branch "v${BUZZ_VERSION}" --depth 1 \
            https://github.com/block/buzz.git /tmp/buzz; \
        cd /tmp/buzz; \
        test "$(git rev-parse HEAD)" = "$BUZZ_SOURCE_SHA"; \
        pnpm install --frozen-lockfile; \
        CARGO_BUILD_JOBS=2 cargo build --locked --release \
            -p buzz-cli \
            -p buzz-acp \
            -p buzz-agent \
            -p buzz-dev-mcp \
            -p git-credential-nostr; \
        ./scripts/bundle-sidecars.sh; \
        cd /tmp/buzz/desktop; \
        CARGO_BUILD_JOBS=2 CMAKE_POLICY_VERSION_MINIMUM=3.5 \
            pnpm tauri build --ci --bundles deb; \
        mapfile -t packages < <(find src-tauri/target/release/bundle/deb \
            -maxdepth 1 -type f -name '*.deb'); \
        test "${#packages[@]}" -eq 1; \
        install -m 0644 "${packages[0]}" /out/Buzz.deb; \
        dpkg-deb --info /out/Buzz.deb >/dev/null; \
    else \
        echo "Buzzbox does not support linux/$arch" >&2; \
        exit 1; \
    fi

FROM ${DESKTOP_IMAGE}

USER root

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH

# Backing services for the local Buzz stack, plus the GTK/WebKit runtime the
# Tauri desktop links against. The desktop base already carries the browser's
# own libraries; these are the ones only buzz-desktop needs. xclip backs the
# enrollment bundle's clipboard hand-off.
RUN apt-get update && apt-get install -y --no-install-recommends \
    postgresql postgresql-client redis-server \
    libwebkit2gtk-4.1-0 libgtk-3-0 libayatana-appindicator3-1 librsvg2-2 \
    xclip \
    python3-numpy python3-pandas python3-scipy python3-requests ipython3 \
    && rm -rf /var/lib/apt/lists/* && \
    ln -sf /usr/bin/ipython3 /usr/bin/ipython

# Docker and GitHub CLIs remain available for coding-agent workflows. The local
# Buzz stack does not require a host Docker socket.
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor \
        -o /usr/share/keyrings/docker-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu noble stable" \
        > /etc/apt/sources.list.d/docker.list && \
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        -o /usr/share/keyrings/githubcli-archive-keyring.gpg && \
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        > /etc/apt/sources.list.d/github-cli.list && \
    apt-get update && \
    apt-get install -y --no-install-recommends docker-ce-cli gh && \
    rm -rf /var/lib/apt/lists/*

# Coding CLIs and the ACP adapters that make them discoverable by Buzz. Node
# and npm come from the runtime layer in the base chain.
#
# npm's cache follows HOME, which the desktop base points at the session user's
# home. Without an explicit cache directory this root-run install leaves
# /home/agent/.npm owned by root, and then kitty cannot start and the session
# opens with no terminal at all.
ARG CODEX_VERSION=0.145.0
ARG CLAUDE_CODE_VERSION=2.1.220
ARG CODEX_ACP_VERSION=1.1.7
ARG CLAUDE_ACP_VERSION=0.62.0
ENV npm_config_cache=/tmp/npm-cache
RUN npm install -g \
        "@openai/codex@${CODEX_VERSION}" \
        "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
        "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
        "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" && \
    rm -rf /tmp/npm-cache && \
    codex --version && \
    claude --version && \
    codex-acp --version && \
    claude-agent-acp --version

# Goose exposes ACP natively, so it does not need a separate adapter.
ARG GOOSE_VERSION=1.44.0
ARG GOOSE_AMD64_SHA256=07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
ARG GOOSE_ARM64_SHA256=da6cb005d421b0bdcb83fe8386ba5ae8060ef17adf64641a684d4fc4b9e1c15f
RUN arch="${TARGETARCH:-$(dpkg --print-architecture)}"; \
    case "$arch" in \
        amd64) goose_arch=x86_64; goose_sha="$GOOSE_AMD64_SHA256" ;; \
        arm64) goose_arch=aarch64; goose_sha="$GOOSE_ARM64_SHA256" ;; \
        *) echo "Unsupported Goose architecture: $arch" >&2; exit 1 ;; \
    esac; \
    goose_archive="/tmp/goose-${GOOSE_VERSION}.tar.gz" && \
    curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 \
        "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-${goose_arch}-unknown-linux-gnu.tar.gz" \
        -o "$goose_archive" && \
    echo "${goose_sha}  ${goose_archive}" | sha256sum -c - && \
    goose_dir="$(mktemp -d)" && \
    tar -xzf "$goose_archive" -C "$goose_dir" && \
    install -m 0755 "$goose_dir/goose" /usr/local/bin/goose && \
    rm -rf "$goose_dir" "$goose_archive" && \
    goose --version && \
    goose acp --help >/dev/null

# Buzz relay, administration utilities, and its bundled web clients. The source
# stage is immutable through BUZZ_RELAY_IMAGE in the Makefile.
COPY --from=buzz-relay /usr/local/bin/buzz-relay /usr/local/bin/buzz-relay
COPY --from=buzz-relay /usr/local/bin/buzz-admin /usr/local/bin/buzz-admin
COPY --from=buzz-relay /usr/local/bin/buzz-pair-relay /usr/local/bin/buzz-pair-relay
COPY --from=buzz-relay /srv/buzz /srv/buzz
COPY --from=minio /usr/bin/minio /usr/local/bin/minio
COPY --from=minio-client /usr/bin/mc /usr/local/bin/mc

# Install the architecture's package produced above. Both variants include
# buzz-desktop and the five sidecars at the same paths.
ARG BUZZ_VERSION=0.5.2
ARG BUZZ_SOURCE_SHA=3e48f1b2365d326ee1c9582448d86a99b44ecd5d
ARG BUZZ_SOURCE_URL=https://github.com/block/buzz
COPY --from=buzz-desktop /out/Buzz.deb /tmp/Buzz.deb
RUN set -eux; \
    apt-get update; \
    apt-get install -y --no-install-recommends /tmp/Buzz.deb; \
    rm -f /tmp/Buzz.deb; \
    rm -rf /var/lib/apt/lists/*; \
    command -v buzz-desktop; \
    command -v buzz; \
    command -v buzz-acp; \
    command -v buzz-agent; \
    command -v buzz-dev-mcp; \
    command -v git-credential-nostr

# The state directory is a volume, so a rebuilt image resumes with its relay
# identity, database, and object store intact. Creating the agent-runtime homes
# now means the entrypoint's ownership pass has something to normalise on a
# brand-new volume.
RUN mkdir -p \
        /var/lib/buzzbox \
        /home/agent/.buzz \
        /home/agent/.codex \
        /home/agent/.claude && \
    rm -rf /home/agent/.cache /home/agent/.npm && \
    chown -R agent:agent /home/agent /var/lib/buzzbox

# Product branding and the programs that drive the Buzz stack. Everything under
# overlay/ is installed over the base's defaults, so a file here wins without
# the base knowing this product exists.
COPY overlay /
RUN chmod 0755 \
        /etc/desktop/session.d/10-buzz-desktop \
        /etc/desktop/startup.d/05-agent-runtime-trust \
        /etc/desktop/startup.d/10-buzz-stack \
        /usr/local/bin/agent-runtime-login \
        /usr/local/bin/buzzbox \
        /usr/local/bin/buzzbox-greeting \
        /usr/local/bin/buzznode-enrollment \
        /usr/local/bin/desktop-harness \
        /usr/local/bin/desktop-panel-status \
        /usr/local/bin/desktop-welcome

# Rebrand the KasmVNC client. The base already patched it, so this replaces the
# brand rather than injecting the asset links a second time.
RUN kasm-patch "Buzzbox"

# DESKTOP_PERSISTENT_PATHS is the base entrypoint's contract: these are created
# and ownership-normalised before the session starts, and they are the paths
# declared as volumes below.
#
# BUZZ_RELAY_PORT and BUZZ_HEALTH_PORT are declared once here and read by
# everything that needs them - the startup hook that launches the relay, the
# session program that waits for it, the panel status, and the health check
# below - so the port lives in one place rather than in six.
ENV DESKTOP_TITLE="Buzzbox" \
    DESKTOP_PERSISTENT_PATHS="/var/lib/buzzbox /home/agent/.buzz /home/agent/.codex /home/agent/.claude" \
    BUZZ_RELAY_PORT=3000 \
    BUZZ_HEALTH_PORT=8080 \
    BUZZ_RELAY_URL=ws://127.0.0.1:3000 \
    BUZZ_WEB_DIR=/srv/buzz/web \
    BUZZ_ADMIN_WEB_DIR=/srv/buzz/admin-web

LABEL org.opencontainers.image.title="Buzzbox" \
    org.opencontainers.image.description="Buzz desktop, local relay, and coding agent workstation in a Launcher-managed browser desktop" \
    org.opencontainers.image.source="https://github.com/pdparchitect/buzzbox" \
    dev.pdparchitect.launcher.upstream.source="${BUZZ_SOURCE_URL}" \
    dev.pdparchitect.launcher.upstream.version="${BUZZ_VERSION}" \
    dev.pdparchitect.launcher.upstream.revision="${BUZZ_SOURCE_SHA}"

# The desktop's own 6901 comes from the base, like every other Launcher
# product. Only the relay is this image's to declare.
EXPOSE 3000
WORKDIR /workspace
VOLUME ["/workspace", "/var/lib/buzzbox", "/home/agent/.buzz", "/home/agent/.codex", "/home/agent/.claude"]

# A HEALTHCHECK replaces the inherited one rather than adding to it, so repeat
# both base probes before checking the relay. The relay probe only applies when
# the relay is expected: disabling it with BUZZ_RELAY_AUTOSTART is a supported
# configuration, and probing the health port unconditionally would hold such a
# container unhealthy forever.
#
# Interval, timeout, and retries match the base. Only start-period differs: the
# entrypoint brings PostgreSQL, Redis, MinIO, and the relay up before it starts
# the desktop, so this image has further to go before its first healthy probe.
HEALTHCHECK --interval=10s --timeout=3s --start-period=90s --retries=5 \
    CMD curl -fsS http://127.0.0.1:6901/ >/dev/null && \
        curl -fsS http://127.0.0.1:6902/healthz >/dev/null && \
        { [ "${BUZZ_RELAY_AUTOSTART:-true}" != "true" ] || \
          curl -fsS "http://127.0.0.1:${BUZZ_HEALTH_PORT:-8080}/_readiness" \
            >/dev/null; } || exit 1
