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
        command -v "$command" >/dev/null || {
            echo "[smoke] FAILED: $command is not on PATH" >&2
            exit 1
        }
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

    # Every check below is named, because this block runs under `bash -ec` and
    # a bare failing command exits 1 with nothing on stderr - which is all a CI
    # log shows for an arch this cannot be reproduced on locally.
    check() {
        local label="$1"
        shift
        if ! "$@" >/dev/null 2>&1; then
            echo "[smoke] FAILED: $label" >&2
            return 1
        fi
    }

    # Services the entrypoint brought up before the desktop.
    check "redis responds to ping" \
        bash -c "redis-cli ping | grep -q PONG"
    check "postgres accepts connections" \
        pg_isready -h 127.0.0.1 -p 5432 -U buzz
    check "minio is live" \
        curl -fsS http://127.0.0.1:9000/minio/health/live
    check "buzz relay reports ready" \
        curl -fsS "http://127.0.0.1:${BUZZ_HEALTH_PORT:-8080}/_readiness"
    check "kasmvnc serves the desktop" \
        curl -fsS http://127.0.0.1:6901/

    # Liveness of the two long-running processes. These are polled rather than
    # sampled once: the relay is started before the session and buzz-desktop
    # from inside it, so a single check here races session startup - and does so
    # differently per architecture, because the native ARM64 build of the Tauri
    # desktop starts on its own schedule.
    await() {
        local label="$1"
        shift
        local attempt
        for attempt in $(seq 1 30); do
            if "$@" >/dev/null 2>&1; then
                return 0
            fi
            sleep 1
        done
        echo "[smoke] FAILED: $label did not appear within 30s" >&2
        ps -eo user,pid,comm >&2 || true
        return 1
    }

    await "the buzz-relay process" pgrep -x buzz-relay
    await "the buzz-desktop process" pgrep -f "(^|/)buzz-desktop($| )"
'

# The desktop base owns this contract. Product processes must be able to use
# the inherited display environment without locating or copying X11 cookies.
x_access=false
for attempt in $(seq 1 20); do
    if "$docker" exec --user agent "$container" xprop -root >/dev/null 2>&1; then
        x_access=true
        break
    fi
    sleep 1
done
if [ "$x_access" != "true" ]; then
    echo "The agent account could not authenticate to the X display." >&2
    exit 1
fi

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
