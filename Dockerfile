# syntax=docker/dockerfile:1.7
#
# Buzzbox - a browser-accessible Buzz desktop, local relay, and coding
# agent workstation.
#
# The desktop release and relay image are pinned to the same upstream commit.
# Buzz's current Linux desktop release is amd64-only, so this image is too.

ARG BUZZ_RELAY_IMAGE=ghcr.io/block/buzz:sha-0096d71
FROM ${BUZZ_RELAY_IMAGE} AS buzz-relay

FROM minio/minio@sha256:14cea493d9a34af32f524e538b8346cf79f3321eff8e708c1e2960462bd8936e AS minio
FROM minio/mc@sha256:a7fe349ef4bd8521fb8497f55c6042871b2ae640607cf99d9bede5e9bdf11727 AS minio-client

# ═══════════════════════════════════════════════════════════════════
# Stage: core - shared runtime/tooling baseline for agent workloads.
# ═══════════════════════════════════════════════════════════════════
FROM ubuntu:24.04 AS core

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

ARG TARGETARCH
ENV DEBIAN_FRONTEND=noninteractive

RUN test "${TARGETARCH:-amd64}" = "amd64" || \
    { echo "Buzzbox currently supports linux/amd64 only" >&2; exit 1; }

# Core tools, local Buzz service dependencies, and desktop runtime libraries.
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash coreutils curl git openssh-client jq socat wget ca-certificates sudo \
    tar zip unzip file procps openssl gnupg \
    dnsutils iproute2 haveged \
    sqlite3 \
    python3 python3-pip python-is-python3 \
    python3-numpy python3-pandas python3-scipy python3-requests \
    ipython3 \
    vim ripgrep git-lfs \
    postgresql postgresql-client redis-server \
    libwebkit2gtk-4.1-0 libgtk-3-0 \
    libayatana-appindicator3-1 librsvg2-2 \
    && rm -rf /var/lib/apt/lists/*

# Node.js 24, matching the current Buzz development toolchain.
RUN curl -fsSL https://deb.nodesource.com/setup_24.x | bash - && \
    apt-get install -y --no-install-recommends nodejs && \
    rm -rf /var/lib/apt/lists/* && \
    node --version && npm --version

RUN corepack enable && corepack prepare pnpm@10.13.1 --activate && \
    pnpm --version

# Coding CLIs and the ACP adapters that make them discoverable by Buzz.
ARG CODEX_VERSION=0.145.0
ARG CLAUDE_CODE_VERSION=2.1.220
ARG CODEX_ACP_VERSION=1.1.7
ARG CLAUDE_ACP_VERSION=0.62.0
RUN npm install -g \
    "@openai/codex@${CODEX_VERSION}" \
    "@anthropic-ai/claude-code@${CLAUDE_CODE_VERSION}" \
    "@agentclientprotocol/codex-acp@${CODEX_ACP_VERSION}" \
    "@agentclientprotocol/claude-agent-acp@${CLAUDE_ACP_VERSION}" && \
    codex --version && \
    claude --version && \
    codex-acp --version && \
    claude-agent-acp --version

# Goose exposes ACP natively, so it does not need a separate adapter.
ARG GOOSE_VERSION=1.44.0
ARG GOOSE_ARCHIVE_SHA256=07febc8b4f73bdfdc3ece3d34d0e21b005f3a4f43008f95b85d6538da8f6bac1
RUN goose_archive="/tmp/goose-${GOOSE_VERSION}.tar.gz" && \
    curl -fsSL --retry 5 --retry-all-errors --connect-timeout 20 \
        "https://github.com/aaif-goose/goose/releases/download/v${GOOSE_VERSION}/goose-x86_64-unknown-linux-gnu.tar.gz" \
        -o "$goose_archive" && \
    echo "${GOOSE_ARCHIVE_SHA256}  ${goose_archive}" | sha256sum -c - && \
    goose_dir="$(mktemp -d)" && \
    tar -xzf "$goose_archive" -C "$goose_dir" && \
    install -m 0755 "$goose_dir/goose" /usr/local/bin/goose && \
    rm -rf "$goose_dir" "$goose_archive" && \
    goose --version && \
    goose acp --help >/dev/null

# Mike Farah yq.
ARG YQ_VERSION=4.44.6
RUN curl -fsSL "https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64" \
        -o /usr/local/bin/yq && \
    chmod +x /usr/local/bin/yq && \
    yq --version

# Buzz relay, administration utilities, and its bundled web clients. The source
# stage is immutable through BUZZ_RELAY_IMAGE in the Makefile.
COPY --from=buzz-relay /usr/local/bin/buzz-relay /usr/local/bin/buzz-relay
COPY --from=buzz-relay /usr/local/bin/buzz-admin /usr/local/bin/buzz-admin
COPY --from=buzz-relay /usr/local/bin/buzz-pair-relay /usr/local/bin/buzz-pair-relay
COPY --from=buzz-relay /srv/buzz /srv/buzz
COPY --from=minio /usr/bin/minio /usr/local/bin/minio
COPY --from=minio-client /usr/bin/mc /usr/local/bin/mc

# The released Buzz desktop package includes buzz-desktop, buzz, buzz-acp,
# buzz-agent, buzz-dev-mcp, and git-credential-nostr.
ARG BUZZ_VERSION=0.4.26
ARG BUZZ_DEB_SHA256=1b520756ecfc28ad81981a2cd5cc6688f785f447b3f5d8d553544906f59bf521
RUN buzz_deb="/tmp/Buzz_${BUZZ_VERSION}_amd64.deb"; \
    curl -fsSL \
        "https://github.com/block/buzz/releases/download/v${BUZZ_VERSION}/Buzz_${BUZZ_VERSION}_amd64.deb" \
        -o "$buzz_deb"; \
    echo "${BUZZ_DEB_SHA256}  ${buzz_deb}" | sha256sum -c -; \
    apt-get update; \
    apt-get install -y --no-install-recommends "$buzz_deb"; \
    rm -f "$buzz_deb"; \
    rm -rf /var/lib/apt/lists/*; \
    command -v buzz-desktop; \
    command -v buzz; \
    command -v buzz-acp; \
    command -v buzz-agent

# Required directories.
RUN mkdir -p /data /outputs /workspace /var/lib/buzzbox /var/log/buzzbox

# Alias ipython to ipython3 and pip to pip3 for consistency.
RUN ln -sf /usr/bin/ipython3 /usr/bin/ipython && \
    ln -sf /usr/bin/pip3 /usr/bin/pip

# ═══════════════════════════════════════════════════════════════════
# Stage: base - desktop UI substrate layered on top of core.
# ═══════════════════════════════════════════════════════════════════
FROM core AS base

# KasmVNC supplies its own X server (Xvnc), so the `xorg` metapackage is not
# installed: it would add xserver-xorg-core, input/video drivers, keyboard-
# configuration, and udev/systemd for hardware this container never has.
# `x11-xserver-utils` is skipped for the same reason - its only consumer would
# be the xrdb call in KasmVNC's generated xstartup, and xstartup is replaced
# below with `exec openbox-session`. Together they cost ~90 MiB.
# xauth, xkb-data, and x11-xkb-utils are listed explicitly even though
# kasmvncserver depends on them, so an autoremove can never take them out.
# xfonts-base supplies the core font path Xvnc is started with.
RUN apt-get update && apt-get install -y --no-install-recommends \
    xdg-utils ssl-cert \
    xauth xkb-data x11-xkb-utils xfonts-base \
    xterm dbus-x11 x11-utils \
    scrot \
    openbox obconf tint2 kitty ranger feh picom htop xdotool wmctrl xclip \
    fonts-noto fonts-noto-color-emoji \
    libnss3 libatk1.0-0t64 libatk-bridge2.0-0t64 libcups2t64 libdrm2 \
    libxkbcommon0 libxcomposite1 libxdamage1 libxrandr2 libgbm1 \
    libpango-1.0-0 libasound2t64 libxshmfence1 \
    && rm -rf /var/lib/apt/lists/*

# Cortile provides optional dynamic tiling on top of Openbox.
ARG CORTILE_VERSION=2.5.2
RUN tmp_dir="$(mktemp -d)"; \
    curl -fsSL \
        "https://github.com/leukipp/cortile/releases/download/v${CORTILE_VERSION}/cortile_${CORTILE_VERSION}_linux_amd64.tar.gz" \
        | tar -xz -C "$tmp_dir"; \
    install -m 0755 "$tmp_dir/cortile" /usr/local/bin/cortile; \
    rm -rf "$tmp_dir"

# KasmVNC exposes the desktop in a browser.
ARG KASMVNC_VERSION=1.4.0
RUN curl -fsSL \
        "https://github.com/kasmtech/KasmVNC/releases/download/v${KASMVNC_VERSION}/kasmvncserver_noble_${KASMVNC_VERSION}_amd64.deb" \
        -o /tmp/kasmvnc.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/kasmvnc.deb && \
    rm -f /tmp/kasmvnc.deb && \
    rm -rf /var/lib/apt/lists/*

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

# Chrome is a secondary browser for documentation and login flows.
RUN curl -fsSL https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb \
        -o /tmp/chrome.deb && \
    apt-get update && \
    apt-get install -y --no-install-recommends /tmp/chrome.deb && \
    rm -f /tmp/chrome.deb && \
    rm -rf /var/lib/apt/lists/* && \
    rm -f /usr/local/bin/chromium

# ═══════════════════════════════════════════════════════════════════
# Stage: buzzbox - complete independently runnable environment.
# ═══════════════════════════════════════════════════════════════════
FROM base AS buzzbox

RUN if id -u agent >/dev/null 2>&1; then \
        usermod -d /home/buzzbox -m agent; \
    elif id -u ubuntu >/dev/null 2>&1; then \
        usermod -l agent -d /home/buzzbox -m ubuntu && groupmod -n agent ubuntu; \
    else \
        groupadd --system agent && \
        useradd --system --create-home --home-dir /home/buzzbox \
            --gid agent --shell /bin/bash agent; \
    fi && \
    mkdir -p \
        /home/buzzbox/.vnc \
        /home/buzzbox/.config \
        /home/buzzbox/.local/share/applications \
        /home/buzzbox/.buzz \
        /home/buzzbox/.codex \
        /home/buzzbox/.claude \
        /workspace \
        /var/lib/buzzbox \
        /var/log/buzzbox && \
    chown -R agent:agent \
        /home/buzzbox \
        /workspace \
        /var/lib/buzzbox \
        /var/log/buzzbox

ENV HOME=/home/buzzbox \
    BROWSER=chromium \
    BUZZ_RELAY_URL=ws://127.0.0.1:3000 \
    BUZZ_WEB_DIR=/srv/buzz/web \
    BUZZ_ADMIN_WEB_DIR=/srv/buzz/admin-web

RUN echo "agent ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/agent && \
    chmod 0440 /etc/sudoers.d/agent && \
    touch /home/buzzbox/.sudo_as_admin_successful /home/buzzbox/.hushlogin && \
    chown agent:agent \
        /home/buzzbox/.sudo_as_admin_successful \
        /home/buzzbox/.hushlogin

# KasmVNC UI customisation.
COPY kasm/custom.css /usr/share/kasmvnc/www/assets/custom.css
COPY kasm/favicon.svg /usr/share/kasmvnc/www/assets/favicon.svg
COPY kasm/patch.sh /tmp/kasm-patch.sh
RUN chmod +x /tmp/kasm-patch.sh && /tmp/kasm-patch.sh && rm /tmp/kasm-patch.sh

# Match the Buzz website's chartreuse background and subtle dot grid.
COPY wallpaper/buzz-grid.svg /usr/share/backgrounds/buzz-grid.svg

RUN mkdir -p /etc/opt/chrome/policies/managed && \
    printf '{\n  "DefaultBrowserSettingEnabled": false,\n  "BrowserSignin": 0,\n  "HomepageLocation": "file:///opt/browser/index.html",\n  "HomepageIsNewTabPage": false,\n  "ShowHomeButton": true\n}\n' \
        > /etc/opt/chrome/policies/managed/chrome-policy.json

COPY openbox/rc.xml /etc/xdg/openbox/rc.xml
COPY openbox/menu.xml /etc/xdg/openbox/menu.xml
COPY openbox/autostart /etc/xdg/openbox/autostart
COPY openbox/theme /usr/share/themes/Triste-Crimson/openbox-3
COPY cortile/cortilectl /usr/local/bin/cortilectl
COPY shell/welcome /usr/local/bin/welcome
COPY shell/chromium /usr/local/bin/chromium
COPY shell/buzzbox /usr/local/bin/buzzbox
COPY shell/buzznode-enrollment /usr/local/bin/buzznode-enrollment
COPY shell/agent-runtime-login /usr/local/bin/agent-runtime-login
RUN mkdir -p /etc/bash.bashrc.d
COPY shell/bashrc /etc/bash.bashrc.d/buzzbox-prompt.sh
COPY browser /opt/browser
COPY tint2/tint2rc /etc/xdg/tint2/tint2rc
RUN chmod +x \
        /etc/xdg/openbox/autostart \
        /usr/local/bin/cortilectl \
        /usr/local/bin/welcome \
        /usr/local/bin/chromium \
        /usr/local/bin/buzzbox \
        /usr/local/bin/buzznode-enrollment \
        /usr/local/bin/agent-runtime-login && \
    echo '[ -d /etc/bash.bashrc.d ] && for f in /etc/bash.bashrc.d/*.sh; do . "$f"; done' \
        >> /etc/bash.bashrc

RUN mkdir -p /usr/share/xsessions && \
    printf '[Desktop Entry]\nName=Openbox\nExec=openbox-session\nType=Application\n' \
        > /usr/share/xsessions/openbox.desktop

USER agent

RUN mkdir -p "$HOME/.config/cortile"
COPY --chown=agent:agent cortile/cortile-config.toml /home/buzzbox/.config/cortile/config.toml

RUN printf '#!/bin/bash\nexec openbox-session\n' > "$HOME/.vnc/xstartup" && \
    chmod +x "$HOME/.vnc/xstartup" && \
    touch "$HOME/.vnc/.de-was-selected" && \
    printf 'network:\n  ssl:\n    require_ssl: false\n  websocket_port: 6901\n' \
        > "$HOME/.vnc/kasmvnc.yaml"

USER root

COPY init.sh /init
RUN chmod +x /init

EXPOSE 6901 3000
WORKDIR /workspace
VOLUME ["/workspace", "/var/lib/buzzbox", "/home/buzzbox/.config", "/home/buzzbox/.local/share", "/home/buzzbox/.buzz", "/home/buzzbox/.codex", "/home/buzzbox/.claude"]

# The relay probe only applies when the relay is expected. Disabling the relay
# with BUZZ_RELAY_AUTOSTART is a supported configuration, and probing 8080
# unconditionally would hold such a container unhealthy forever.
HEALTHCHECK --interval=10s --timeout=5s --start-period=60s --retries=6 \
    CMD curl -fsS http://127.0.0.1:6901/ >/dev/null && \
        { [ "${BUZZ_RELAY_AUTOSTART:-true}" != "true" ] || \
          curl -fsS http://127.0.0.1:8080/_readiness >/dev/null; } || exit 1

ENTRYPOINT ["/init"]
