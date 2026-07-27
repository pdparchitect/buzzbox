#!/bin/bash
# Buzzbox container entrypoint.
# Starts the local data services, Buzz relay, and Openbox/KasmVNC desktop.

set -euo pipefail

export HOME=/home/buzzbox
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export BUZZ_RELAY_URL="${BUZZ_RELAY_URL:-ws://127.0.0.1:3000}"
export BUZZ_WEB_DIR="${BUZZ_WEB_DIR:-/srv/buzz/web}"
export BUZZ_ADMIN_WEB_DIR="${BUZZ_ADMIN_WEB_DIR:-/srv/buzz/admin-web}"

public_relay_url="${BUZZBOX_PUBLIC_RELAY_URL:-$BUZZ_RELAY_URL}"
if ! node -e '
    const url = new URL(process.argv[1]);
    if (url.protocol !== "ws:" && url.protocol !== "wss:") process.exit(1);
' "$public_relay_url"; then
    echo "[buzzbox] invalid BUZZBOX_PUBLIC_RELAY_URL: $public_relay_url" >&2
    exit 1
fi

public_media_base_url="$(node -e '
    const url = new URL(process.argv[1]);
    url.protocol = url.protocol === "wss:" ? "https:" : "http:";
    process.stdout.write(`${url.origin}/media`);
' "$public_relay_url")"
public_relay_domain="$(node -e '
    process.stdout.write(new URL(process.argv[1]).hostname);
' "$public_relay_url")"
printf -v public_relay_url_q '%q' "$public_relay_url"
printf -v public_media_base_url_q '%q' "$public_media_base_url"
printf -v public_relay_domain_q '%q' "$public_relay_domain"

agent_uid="$(id -u agent)"
export XDG_RUNTIME_DIR="/run/user/${agent_uid}"

state_dir="${BUZZBOX_STATE_DIR:-/var/lib/buzzbox}"
postgres_dir="$state_dir/postgres"
redis_dir="$state_dir/redis"
minio_dir="$state_dir/minio"
git_dir="$state_dir/git"
secrets_dir="$state_dir/secrets"
resolution="${BUZZBOX_RESOLUTION:-1920x1080}"

if [[ ! "$resolution" =~ ^[0-9]{3,5}x[0-9]{3,5}$ ]]; then
    echo "[buzzbox] invalid BUZZBOX_RESOLUTION: $resolution" >&2
    exit 1
fi

width="${resolution%x*}"
height="${resolution#*x}"

mkdir -p \
    "$HOME/.vnc" \
    "$HOME/.config" \
    "$HOME/.local/share/applications" \
    "$HOME/.buzz" \
    "$HOME/.codex" \
    "$HOME/.claude" \
    "$XDG_RUNTIME_DIR" \
    "$postgres_dir" \
    "$redis_dir" \
    "$minio_dir" \
    "$git_dir" \
    "$secrets_dir" \
    /workspace \
    /var/log/buzzbox \
    /tmp/.X11-unix

# Keep the durable workspace and the agent's home available as Ranger
# bookmarks without replacing any bookmarks the user has already assigned.
ranger_data_dir="$XDG_DATA_HOME/ranger"
ranger_bookmarks="$ranger_data_dir/bookmarks"
mkdir -p "$ranger_data_dir"
touch "$ranger_bookmarks"
if ! grep -q '^W:' "$ranger_bookmarks"; then
    printf 'W:/workspace\n' >> "$ranger_bookmarks"
fi
if ! grep -q '^H:' "$ranger_bookmarks"; then
    printf 'H:%s\n' "$HOME" >> "$ranger_bookmarks"
fi

# Ownership only needs normalizing once per volume lifetime. Recursing these
# paths on every boot walks the whole workspace, the PostgreSQL cluster, and the
# MinIO object store, which becomes minutes of startup latency once they hold
# real data. Anything created later is created by the agent user already.
persistent_paths=(
    "$HOME/.config"
    "$HOME/.local/share"
    "$HOME/.buzz"
    "$HOME/.codex"
    "$HOME/.claude"
    "$state_dir"
    /workspace
)
ownership_stamp="$state_dir/.ownership-normalized"

chown agent:agent \
    "${persistent_paths[@]}" \
    "$XDG_RUNTIME_DIR" \
    /var/log/buzzbox

if [ ! -e "$ownership_stamp" ]; then
    chown -R agent:agent "${persistent_paths[@]}" /var/log/buzzbox
    touch "$ownership_stamp"
    chown agent:agent "$ownership_stamp"
    echo "[buzzbox] normalized ownership of the persistent volumes"
fi

chmod 700 "$XDG_RUNTIME_DIR" "$secrets_dir"
chmod 1777 /tmp/.X11-unix

if getent group ssl-cert >/dev/null 2>&1; then
    usermod -a -G ssl-cert agent
fi

stable_secret() {
    local name="$1"
    local path="$secrets_dir/$name"

    if [ ! -s "$path" ]; then
        openssl rand -hex 32 > "$path"
        chown agent:agent "$path"
        chmod 600 "$path"
    fi

    tr -d '[:space:]' < "$path"
}

export BUZZ_RELAY_PRIVATE_KEY="${BUZZ_RELAY_PRIVATE_KEY:-$(stable_secret relay-private-key)}"
export BUZZ_GIT_HOOK_HMAC_SECRET="${BUZZ_GIT_HOOK_HMAC_SECRET:-$(stable_secret git-hook-hmac)}"
export MINIO_ROOT_USER="${BUZZ_S3_ACCESS_KEY:-buzzbox}"
export MINIO_ROOT_PASSWORD="${BUZZ_S3_SECRET_KEY:-$(stable_secret minio-secret)}"
export BUZZ_S3_ACCESS_KEY="$MINIO_ROOT_USER"
export BUZZ_S3_SECRET_KEY="$MINIO_ROOT_PASSWORD"
export BUZZ_S3_BUCKET="${BUZZ_S3_BUCKET:-buzz-media}"

# Every value interpolated into a `su -c` string is quoted the same way the
# relay URLs above are. Most of these can be supplied through the environment,
# so an unquoted space or quote character in one would otherwise break out of
# the command being built rather than fail cleanly.
printf -v postgres_dir_q '%q' "$postgres_dir"
printf -v redis_dir_q '%q' "$redis_dir"
printf -v minio_dir_q '%q' "$minio_dir"
printf -v git_dir_q '%q' "$git_dir"
printf -v s3_access_key_q '%q' "$BUZZ_S3_ACCESS_KEY"
printf -v s3_secret_key_q '%q' "$BUZZ_S3_SECRET_KEY"
printf -v s3_bucket_q '%q' "$BUZZ_S3_BUCKET"
printf -v relay_private_key_q '%q' "$BUZZ_RELAY_PRIVATE_KEY"
printf -v git_hook_secret_q '%q' "$BUZZ_GIT_HOOK_HMAC_SECRET"
printf -v buzz_web_dir_q '%q' "$BUZZ_WEB_DIR"
printf -v buzz_admin_web_dir_q '%q' "$BUZZ_ADMIN_WEB_DIR"

# Codex and Claude Code each prompt once per directory before working in it
# ("Do you trust the contents of this directory?"). Buzzbox ships the same ACP
# adapters as Buzznode, and codex-acp consults trust_level, so a harness
# started against the workspace stops on that prompt. Record the decision at
# boot so the workspace behaves the same way across both images.
#
# Unlike Buzznode there is no scripted unattended launch here - harnesses are
# started from the menu - so this is consistency rather than a hang. Set
# BUZZBOX_TRUST_WORKSPACE=false to leave both prompts in place.
harness_workdir="${BUZZBOX_HARNESS_WORKDIR:-/workspace}"
codex_config="$HOME/.codex/config.toml"

# Codex sandboxes the commands it runs with bubblewrap, and warns when it has to
# fall back to its bundled copy. Neither copy can work here: the container blocks
# unprivileged user namespaces, so bwrap cannot create one, and installing the
# distro package only adds a second binary that fails the same way. Declare the
# mode that matches reality rather than leaving a config that implies an
# isolation boundary which is not there - the boundary is the container itself.
#
# Set BUZZBOX_CODEX_SANDBOX_MODE to read-only or workspace-write to choose a
# different mode, or to an empty value to leave the setting out entirely.
codex_sandbox_mode="${BUZZBOX_CODEX_SANDBOX_MODE-danger-full-access}"
if [ -n "$codex_sandbox_mode" ] &&
    ! grep -Eq '^sandbox_mode *=' "$codex_config" 2>/dev/null; then
    codex_sandbox_tmp="$(mktemp)"
    # Prepended, not appended: sandbox_mode is a top-level key, and TOML assigns
    # any key following a [table] header to that table. The trust block below
    # writes [projects."..."] tables, so appending would quietly turn this into a
    # per-project setting instead of a global one.
    {
        printf 'sandbox_mode = "%s"\n\n' "$codex_sandbox_mode"
        [ -s "$codex_config" ] && cat "$codex_config"
    } > "$codex_sandbox_tmp"
    install -m 0600 -o agent -g agent "$codex_sandbox_tmp" "$codex_config"
    rm -f "$codex_sandbox_tmp"
    echo "[buzzbox] set Codex sandbox_mode=$codex_sandbox_mode" \
        "(no usable bubblewrap in a container)"
fi

if [ "${BUZZBOX_TRUST_WORKSPACE:-true}" = "true" ]; then
    if ! grep -Fq "[projects.\"$harness_workdir\"]" "$codex_config" 2>/dev/null; then
        printf '\n[projects."%s"]\ntrust_level = "trusted"\n' \
            "$harness_workdir" >> "$codex_config"
        chown agent:agent "$codex_config"
        echo "[buzzbox] recorded $harness_workdir as trusted for Codex"
    fi

    claude_config="$HOME/.claude.json"
    if ! jq -e --arg dir "$harness_workdir" \
        '.projects[$dir].hasTrustDialogAccepted == true' \
        "$claude_config" >/dev/null 2>&1; then
        [ -s "$claude_config" ] || echo '{}' > "$claude_config"
        claude_trust_tmp="$(mktemp)"
        # Leave the file untouched if it is not valid JSON rather than
        # replacing a config the operator may have hand-written.
        if jq --arg dir "$harness_workdir" \
            '.projects[$dir].hasTrustDialogAccepted = true' \
            "$claude_config" > "$claude_trust_tmp" 2>/dev/null; then
            install -m 0600 -o agent -g agent \
                "$claude_trust_tmp" "$claude_config"
            echo "[buzzbox] recorded $harness_workdir as trusted for Claude Code"
        fi
        rm -f "$claude_trust_tmp"
    fi
fi

# Use a GPU only when the host exposes a render node *and* the desktop user can
# open it; otherwise keep software rendering. A passed-through node is normally
# root:render 0660 and the host's render group does not exist in this image, so
# presence alone does not mean usable. Announcing hw3d in that case leaves Xvnc
# and Chrome retrying against a device they cannot open.
gpu_node=""
gpu_node_blocked=""
for node in /dev/dri/renderD*; do
    [ -e "$node" ] || continue
    printf -v node_q '%q' "$node"
    if su -s /bin/bash -c "test -r $node_q && test -w $node_q" agent; then
        gpu_node="$node"
        break
    fi
    gpu_node_blocked="$node"
done

if [ -n "$gpu_node" ]; then
    gpu_config="  gpu:
    hw3d: true
    drinode: $gpu_node"
    echo "[buzzbox] GPU acceleration enabled via $gpu_node"
else
    gpu_config="  gpu:
    hw3d: false"
    if [ -n "$gpu_node_blocked" ]; then
        echo "[buzzbox] $gpu_node_blocked is not readable by the agent user;" \
            "using software rendering"
    else
        echo "[buzzbox] no GPU render node found; using software rendering"
    fi
fi

cat > "$HOME/.vnc/kasmvnc.yaml" <<YAML
network:
  protocol: http
  ssl:
    require_ssl: false
  interface: 0.0.0.0
  websocket_port: 6901

desktop:
  resolution:
    width: $width
    height: $height
  pixel_depth: 24
$gpu_config

encoding:
  max_frame_rate: 30

security:
  brute_force_protection:
    blacklist_threshold: 0
YAML

if [ "${BUZZBOX_VNC_STATS:-false}" = "true" ]; then
    cat >> "$HOME/.vnc/kasmvnc.yaml" <<'YAML'

logging:
  log_writer_name: EncodeManager
  log_dest: logfile
  level: 100
YAML
    echo "[buzzbox] KasmVNC encoder statistics enabled"
fi

cat > "$HOME/.vnc/xstartup" <<'XSTARTUP'
#!/bin/bash
exec openbox-session
XSTARTUP
chmod +x "$HOME/.vnc/xstartup"
touch "$HOME/.vnc/.de-was-selected"
chown -R agent:agent "$HOME/.vnc"

# KasmVNC checks these even with browser authentication and TLS disabled.
su -s /bin/bash -c '
    openssl req -x509 -nodes -days 3650 -newkey rsa:2048 \
        -keyout "$HOME/.vnc/self.pem" \
        -out "$HOME/.vnc/self.pem" \
        -subj "/CN=buzzbox" >/dev/null 2>&1
    printf "buzzbox\nbuzzbox\n" | kasmvncpasswd -u agent -wo >/dev/null 2>&1 || true
' agent

pg_bindir="$(pg_config --bindir)"
printf -v pg_bindir_q '%q' "$pg_bindir"
printf -v pg_options_q '%q' "-h 127.0.0.1 -p 5432 -k $postgres_dir"

# shellcheck disable=SC2329
cleanup() {
    echo "[buzzbox] stopping"
    su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
    pkill -TERM -u agent -f '(^|/)buzz-desktop($| )' 2>/dev/null || true
    pkill -TERM -u agent buzz-relay 2>/dev/null || true
    pkill -TERM -u agent minio 2>/dev/null || true
    pkill -TERM -u agent redis-server 2>/dev/null || true
    su -s /bin/bash -c \
        "$pg_bindir_q/pg_ctl -D $postgres_dir_q stop -m fast >/dev/null 2>&1 || true" \
        agent
}

# Installed before the first service starts so a stop during startup still
# shuts PostgreSQL down cleanly. Every step is already idempotent.
trap cleanup EXIT INT TERM

if [ ! -s "$postgres_dir/PG_VERSION" ]; then
    su -s /bin/bash -c \
        "$pg_bindir_q/initdb -D $postgres_dir_q -U buzz --auth-local=trust --auth-host=trust" \
        agent >/var/log/buzzbox/postgres-init.log 2>&1
    echo "[buzzbox] initialized PostgreSQL"
fi

su -s /bin/bash -c \
    "$pg_bindir_q/pg_ctl -D $postgres_dir_q -l /var/log/buzzbox/postgres.log \
        -o $pg_options_q start" \
    agent >/dev/null

for attempt in $(seq 1 40); do
    if pg_isready -h 127.0.0.1 -p 5432 -U buzz >/dev/null 2>&1; then
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[buzzbox] PostgreSQL did not become ready" >&2
        tail -n 100 /var/log/buzzbox/postgres.log >&2 || true
        exit 1
    fi
    sleep 1
done

if ! psql -h 127.0.0.1 -U buzz -d postgres -tAc \
    "SELECT 1 FROM pg_database WHERE datname = 'buzz'" | grep -q 1; then
    createdb -h 127.0.0.1 -U buzz buzz
fi
echo "[buzzbox] PostgreSQL ready"

su -s /bin/bash -c "
    exec redis-server \
        --bind 127.0.0.1 \
        --port 6379 \
        --protected-mode yes \
        --dir $redis_dir_q \
        --appendonly yes \
        --logfile /var/log/buzzbox/redis.log
" agent &

for attempt in $(seq 1 30); do
    if redis-cli -h 127.0.0.1 ping 2>/dev/null | grep -q PONG; then
        break
    fi
    if [ "$attempt" -eq 30 ]; then
        echo "[buzzbox] Redis did not become ready" >&2
        tail -n 100 /var/log/buzzbox/redis.log >&2 || true
        exit 1
    fi
    sleep 1
done
echo "[buzzbox] Redis ready"

su -s /bin/bash -c "
    export MINIO_ROOT_USER=$s3_access_key_q
    export MINIO_ROOT_PASSWORD=$s3_secret_key_q
    exec minio server $minio_dir_q \
        --address 127.0.0.1:9000 \
        --console-address 127.0.0.1:9001
" agent >>/var/log/buzzbox/minio.log 2>&1 &

for attempt in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:9000/minio/health/live >/dev/null 2>&1; then
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[buzzbox] MinIO did not become ready" >&2
        tail -n 100 /var/log/buzzbox/minio.log >&2 || true
        exit 1
    fi
    sleep 1
done

mc alias set buzzbox http://127.0.0.1:9000 \
    "$BUZZ_S3_ACCESS_KEY" "$BUZZ_S3_SECRET_KEY" >/dev/null
mc mb --ignore-existing "buzzbox/$BUZZ_S3_BUCKET" >/dev/null
mc anonymous set none "buzzbox/$BUZZ_S3_BUCKET" >/dev/null
echo "[buzzbox] MinIO ready"

if [ "${BUZZ_RELAY_AUTOSTART:-true}" = "true" ]; then
    su -s /bin/bash -c "
        export HOME='$HOME'
        export DATABASE_URL='postgres://buzz@127.0.0.1:5432/buzz'
        export REDIS_URL='redis://127.0.0.1:6379'
        export RELAY_URL=$public_relay_url_q
        export BUZZ_BIND_ADDR='0.0.0.0:3000'
        export BUZZ_HEALTH_PORT='8080'
        export BUZZ_METRICS_PORT='9102'
        export BUZZ_RELAY_PRIVATE_KEY=$relay_private_key_q
        export BUZZ_GIT_HOOK_HMAC_SECRET=$git_hook_secret_q
        export BUZZ_S3_ENDPOINT='http://127.0.0.1:9000'
        export BUZZ_S3_ACCESS_KEY=$s3_access_key_q
        export BUZZ_S3_SECRET_KEY=$s3_secret_key_q
        export BUZZ_S3_BUCKET=$s3_bucket_q
        export BUZZ_MEDIA_BASE_URL=$public_media_base_url_q
        export BUZZ_MEDIA_SERVER_DOMAIN=$public_relay_domain_q
        export BUZZ_GIT_REPO_PATH=$git_dir_q
        export BUZZ_AUTO_MIGRATE='true'
        export BUZZ_GIT_CONFORMANCE_PROBE='false'
        export BUZZ_REQUIRE_AUTH_TOKEN='false'
        export BUZZ_REQUIRE_RELAY_MEMBERSHIP='false'
        export BUZZ_ALLOW_NIP_OA_AUTH='true'
        export BUZZ_WEB_DIR=$buzz_web_dir_q
        export BUZZ_ADMIN_WEB_DIR=$buzz_admin_web_dir_q
        export RUST_LOG='buzz_relay=info,buzz_db=info,buzz_auth=info'
        exec buzz-relay
    " agent >>/var/log/buzzbox/buzz-relay.log 2>&1 &

    for attempt in $(seq 1 60); do
        if curl -fsS http://127.0.0.1:8080/_readiness >/dev/null 2>&1; then
            break
        fi
        if [ "$attempt" -eq 60 ]; then
            echo "[buzzbox] Buzz relay did not become ready" >&2
            tail -n 150 /var/log/buzzbox/buzz-relay.log >&2 || true
            exit 1
        fi
        sleep 1
    done
    echo "[buzzbox] Buzz relay ready at $BUZZ_RELAY_URL"
    echo "[buzzbox] external relay URL: $public_relay_url"
fi

su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
rm -f /tmp/.X1-lock /tmp/.X11-unix/X1

su -s /bin/bash -c "
    export HOME='$HOME'
    export DISPLAY=:1
    export XDG_CONFIG_HOME='$XDG_CONFIG_HOME'
    export XDG_DATA_HOME='$XDG_DATA_HOME'
    export XDG_RUNTIME_DIR='$XDG_RUNTIME_DIR'
    export BUZZ_RELAY_URL='$BUZZ_RELAY_URL'
    exec kasmvncserver :1 \
        -disableBasicAuth \
        -interface 0.0.0.0 \
        -websocketPort 6901 \
        -publicIP 127.0.0.1 \
        -geometry '$resolution' \
        -depth 24 \
        -httpd /usr/share/kasmvnc/www \
        -BlacklistThreshold 0 \
        -FreeKeyMappings
" agent >>/var/log/buzzbox/kasmvnc.log 2>&1 &

for attempt in $(seq 1 40); do
    if curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; then
        echo "[buzzbox] desktop ready at http://localhost:6901"
        break
    fi
    if [ "$attempt" -eq 40 ]; then
        echo "[buzzbox] KasmVNC did not become ready" >&2
        tail -n 100 /var/log/buzzbox/kasmvnc.log >&2 || true
        exit 1
    fi
    sleep 1
done

while curl -fsS http://127.0.0.1:6901/ >/dev/null 2>&1; do
    sleep 5
done

echo "[buzzbox] browser environment stopped unexpectedly" >&2
exit 1
