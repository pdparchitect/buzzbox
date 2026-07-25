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

chown -R agent:agent \
    "$HOME/.vnc" \
    "$HOME/.config" \
    "$HOME/.local/share" \
    "$HOME/.buzz" \
    "$HOME/.codex" \
    "$HOME/.claude" \
    "$XDG_RUNTIME_DIR" \
    "$state_dir" \
    /workspace \
    /var/log/buzzbox
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

# Use a GPU when the host exposes one; otherwise keep software rendering.
gpu_node=""
for node in /dev/dri/renderD*; do
    if [ -e "$node" ]; then
        gpu_node="$node"
        break
    fi
done

if [ -n "$gpu_node" ]; then
    gpu_config="  gpu:
    hw3d: true
    drinode: $gpu_node"
    echo "[buzzbox] GPU acceleration enabled via $gpu_node"
else
    gpu_config="  gpu:
    hw3d: false"
    echo "[buzzbox] no GPU render node found; using software rendering"
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

if [ ! -s "$postgres_dir/PG_VERSION" ]; then
    su -s /bin/bash -c \
        "'$pg_bindir/initdb' -D '$postgres_dir' -U buzz --auth-local=trust --auth-host=trust" \
        agent >/var/log/buzzbox/postgres-init.log 2>&1
    echo "[buzzbox] initialized PostgreSQL"
fi

su -s /bin/bash -c \
    "'$pg_bindir/pg_ctl' -D '$postgres_dir' -l /var/log/buzzbox/postgres.log \
        -o '-h 127.0.0.1 -p 5432 -k $postgres_dir' start" \
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
        --dir '$redis_dir' \
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
    export MINIO_ROOT_USER='$MINIO_ROOT_USER'
    export MINIO_ROOT_PASSWORD='$MINIO_ROOT_PASSWORD'
    exec minio server '$minio_dir' \
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

# shellcheck disable=SC2329
cleanup() {
    echo "[buzzbox] stopping"
    su -s /bin/bash -c 'kasmvncserver -kill :1 >/dev/null 2>&1 || true' agent
    pkill -TERM -u agent -f '(^|/)buzz-desktop($| )' 2>/dev/null || true
    pkill -TERM -u agent buzz-relay 2>/dev/null || true
    pkill -TERM -u agent minio 2>/dev/null || true
    pkill -TERM -u agent redis-server 2>/dev/null || true
    su -s /bin/bash -c \
        "'$pg_bindir/pg_ctl' -D '$postgres_dir' stop -m fast >/dev/null 2>&1 || true" \
        agent
}
trap cleanup EXIT INT TERM

if [ "${BUZZ_RELAY_AUTOSTART:-true}" = "true" ]; then
    su -s /bin/bash -c "
        export HOME='$HOME'
        export DATABASE_URL='postgres://buzz@127.0.0.1:5432/buzz'
        export REDIS_URL='redis://127.0.0.1:6379'
        export RELAY_URL='$BUZZ_RELAY_URL'
        export BUZZ_BIND_ADDR='0.0.0.0:3000'
        export BUZZ_HEALTH_PORT='8080'
        export BUZZ_METRICS_PORT='9102'
        export BUZZ_RELAY_PRIVATE_KEY='$BUZZ_RELAY_PRIVATE_KEY'
        export BUZZ_GIT_HOOK_HMAC_SECRET='$BUZZ_GIT_HOOK_HMAC_SECRET'
        export BUZZ_S3_ENDPOINT='http://127.0.0.1:9000'
        export BUZZ_S3_ACCESS_KEY='$BUZZ_S3_ACCESS_KEY'
        export BUZZ_S3_SECRET_KEY='$BUZZ_S3_SECRET_KEY'
        export BUZZ_S3_BUCKET='$BUZZ_S3_BUCKET'
        export BUZZ_MEDIA_BASE_URL='http://127.0.0.1:3000/media'
        export BUZZ_MEDIA_SERVER_DOMAIN='127.0.0.1'
        export BUZZ_GIT_REPO_PATH='$git_dir'
        export BUZZ_AUTO_MIGRATE='true'
        export BUZZ_GIT_CONFORMANCE_PROBE='false'
        export BUZZ_REQUIRE_AUTH_TOKEN='false'
        export BUZZ_REQUIRE_RELAY_MEMBERSHIP='false'
        export BUZZ_ALLOW_NIP_OA_AUTH='true'
        export BUZZ_WEB_DIR='$BUZZ_WEB_DIR'
        export BUZZ_ADMIN_WEB_DIR='$BUZZ_ADMIN_WEB_DIR'
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
