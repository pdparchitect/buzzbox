#!/usr/bin/env bash

set -euo pipefail

container="${1:?usage: smoke-container.sh CONTAINER [ARCH]}"
expected_arch="${2:-}"
docker="${DOCKER:-docker}"

actual_arch="$("$docker" exec "$container" dpkg --print-architecture)"
if [ -n "$expected_arch" ] && [ "$actual_arch" != "$expected_arch" ]; then
    echo "Expected $expected_arch container, got $actual_arch" >&2
    exit 1
fi

"$docker" exec "$container" bash -ec '
    for command in agent-runtime-login buzzbox buzznode-enrollment \
        buzz-desktop buzz buzz-acp buzz-agent buzz-dev-mcp \
        git-credential-nostr buzz-relay buzz-admin buzz-pair-relay \
        codex codex-acp claude claude-agent-acp goose chromium \
        minio mc; do
        command -v "$command" >/dev/null
    done

    case "$(dpkg --print-architecture)" in
        amd64)
            test -x /opt/google/chrome/google-chrome
            test ! -x /usr/bin/chromium
            ;;
        arm64)
            test -x /usr/bin/chromium
            test ! -x /opt/google/chrome/google-chrome
            ;;
        *)
            exit 1
            ;;
    esac

    buzz --help >/dev/null
    buzz-acp --help >/dev/null
    goose --version
    chromium --version
    redis-cli ping | grep -q PONG
    pg_isready -h 127.0.0.1 -p 5432 -U buzz >/dev/null
    curl -fsS http://127.0.0.1:9000/minio/health/live >/dev/null
    curl -fsS http://127.0.0.1:8080/_readiness >/dev/null
    curl -fsS http://127.0.0.1:6901/ >/dev/null
    pgrep -x buzz-relay >/dev/null
    pgrep -f "(^|/)buzz-desktop($| )" >/dev/null
'

desktop_ready=false
for attempt in $(seq 1 30); do
    if "$docker" exec \
        --user agent \
        --env DISPLAY=:1 \
        "$container" \
        wmctrl -lx 2>/dev/null | grep -qi 'buzz-desktop'; then
        desktop_ready=true
        break
    fi
    sleep 1
done

if [ "$desktop_ready" != "true" ]; then
    echo "Buzz Desktop did not create a visible window on linux/$actual_arch." >&2
    "$docker" exec "$container" ps aux >&2 || true
    exit 1
fi

"$docker" exec --detach \
    --user agent \
    --env DISPLAY=:1 \
    --env HOME=/home/agent \
    "$container" \
    chromium --new-window file:///opt/browser/index.html

browser_ready=false
for attempt in $(seq 1 30); do
    if "$docker" exec \
        --user agent \
        --env DISPLAY=:1 \
        "$container" \
        xdotool search --onlyvisible --name 'Buzzbox' \
        >/dev/null 2>&1; then
        browser_ready=true
        break
    fi
    sleep 1
done

if [ "$browser_ready" != "true" ]; then
    echo "The $actual_arch browser did not create a visible desktop window." >&2
    "$docker" exec "$container" ps aux >&2 || true
    exit 1
fi

"$docker" exec \
    --user agent \
    --env DISPLAY=:1 \
    "$container" \
    scrot /tmp/buzzbox-browser-smoke.png
"$docker" exec "$container" test -s /tmp/buzzbox-browser-smoke.png
"$docker" exec "$container" rm -f /tmp/buzzbox-browser-smoke.png

echo "Buzzbox services, desktop, and headed browser passed on linux/$actual_arch."
