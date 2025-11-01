#!/bin/bash
# ...existing code...
# Portainer upgrade helper (Podman-aware, follows https://docs.portainer.io/start/install-ce/server/podman/linux)
set -euo pipefail

NEW_IMAGE="${1:-docker.io/portainer/portainer-ce:2.33.3}"
CONTAINER_NAME="${2:-portainer}"

echo "Portainer upgrade helper (Podman)"
echo "Target container: $CONTAINER_NAME"
echo "Target image:     $NEW_IMAGE"
echo

command -v podman >/dev/null 2>&1 || { echo "podman is required but not found in PATH"; exit 1; }

# Detect podman socket (prefer system socket)
SOCKET_CANDIDATES=(/run/podman/podman.sock /var/run/podman/podman.sock /run/docker.sock /var/run/docker.sock "/run/user/$(id -u)/podman/podman.sock")
SOCKET_HOST=""
for s in "${SOCKET_CANDIDATES[@]}"; do
  if [ -S "$s" ]; then
    SOCKET_HOST="$s"
    break
  fi
done

if [ -z "$SOCKET_HOST" ]; then
  echo "No Podman socket found in common locations."
  echo "Attempting to enable system podman.socket (requires sudo)..."
  if sudo systemctl enable --now podman.socket >/dev/null 2>&1; then
    if [ -S /run/podman/podman.sock ]; then
      SOCKET_HOST=/run/podman/podman.sock
      echo "Enabled system podman.socket, socket at $SOCKET_HOST"
    fi
  fi
fi

if [ -z "$SOCKET_HOST" ]; then
  echo "Still no socket found."
  echo "If you use rootless Podman, run: systemctl --user enable --now podman.socket"
  echo "Then re-run this script as the same user that started the socket, or provide socket path manually."
  echo "You can also pass a socket path as \$3 to this script."
fi

# allow override socket via 3rd arg
if [ -n "${3:-}" ]; then
  SOCKET_HOST="$3"
  echo "Overriding detected socket with: $SOCKET_HOST"
fi

if [ -n "$SOCKET_HOST" ]; then
  echo "Using socket: $SOCKET_HOST"
else
  echo "Proceeding without socket mount. Portainer will not manage containers via API."
fi
echo

if ! podman container exists "$CONTAINER_NAME"; then
  echo "No container named '$CONTAINER_NAME' found."
  read -p "Pull image $NEW_IMAGE now and exit (create container manually later)? [y/N] " -r
  if [[ $REPLY =~ ^[Yy]$ ]]; then
    podman pull "$NEW_IMAGE"
    echo "Image pulled."
  fi
  exit 0
fi

TS=$(date +%Y%m%d-%H%M%S)
INSPECT_JSON="/tmp/${CONTAINER_NAME}-inspect-${TS}.json"
echo "Saving container inspect to $INSPECT_JSON"
podman inspect "$CONTAINER_NAME" > "$INSPECT_JSON"

CUR_IMAGE=$(podman inspect --format '{{.Config.Image}}' "$CONTAINER_NAME" 2>/dev/null || true)
echo "Current image used by container: ${CUR_IMAGE:-<unknown>}"
echo

echo "Detected mounts (host:container):"
podman inspect --format '{{range .Mounts}}{{printf "%s:%s\n" .Source .Destination}}{{end}}' "$CONTAINER_NAME" | sed 's/^/  /'
echo

# Detect host path mounted to /data (Portainer data)
DATA_HOST_PATH=""
while IFS=: read -r src dst; do
  if [[ "$dst" == "/data" ]]; then
    DATA_HOST_PATH="$src"
    break
  fi
done < <(podman inspect --format '{{range .Mounts}}{{printf "%s:%s\n" .Source .Destination}}{{end}}' "$CONTAINER_NAME")

if [ -n "$DATA_HOST_PATH" ]; then
  echo "Portainer data path on host: $DATA_HOST_PATH"
else
  echo "No host mount found for /data. If a named volume is used, inspect $INSPECT_JSON to find the volume path."
fi
echo

echo "Detected published ports (host->container):"
podman port "$CONTAINER_NAME" 2>/dev/null | sed 's/^/  /' || echo "  <none>"
echo

read -p "Continue with backup, pull $NEW_IMAGE, stop & recreate $CONTAINER_NAME? [y/N] " -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  echo "Aborted by user."
  exit 0
fi

echo "Pulling new image: $NEW_IMAGE"
podman pull "$NEW_IMAGE"

# Backup data directory if found
BACKUP_DIR=""
if [ -n "$DATA_HOST_PATH" ] && [ -d "$DATA_HOST_PATH" ]; then
  BACKUP_DIR="${DATA_HOST_PATH}-backup-${TS}"
  echo "Backing up Portainer data from $DATA_HOST_PATH -> $BACKUP_DIR"
  sudo rsync -aHAX --delete "$DATA_HOST_PATH/" "$BACKUP_DIR/" || { echo "Backup failed"; exit 1; }
  echo "Backup complete."
else
  echo "No data directory to back up or path not found: $DATA_HOST_PATH"
fi
echo

echo "Stopping container $CONTAINER_NAME..."
podman stop "$CONTAINER_NAME" || true
echo "Removing container $CONTAINER_NAME..."
podman rm "$CONTAINER_NAME" || true
echo

# Build run options from detected ports and mounts
RUN_OPTS=()
# ports
while read -r line; do
  if [[ -z "$line" ]]; then
    continue
  fi
  # e.g. "9000/tcp -> 0.0.0.0:9000"
  if [[ "$line" =~ ->[[:space:]]([^:]+):([0-9]+)$ ]]; then
    host_port="${BASH_REMATCH[2]}"
    container_port=$(awk -F'/' '{print $1}' <<<"$line")
    RUN_OPTS+=("-p" "${host_port}:${container_port}")
  fi
done < <(podman port "$CONTAINER_NAME" 2>/dev/null || true)

# mounts: preserve host->container mounts (especially /data)
while read -r mount; do
  [ -z "$mount" ] && continue
  src="${mount%%:*}"
  dst="${mount#*:}"
  SELINUX_FLAG=""
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null || echo Permissive)" = "Enforcing" ]; then
    SELINUX_FLAG=":Z"
  fi
  RUN_OPTS+=("-v" "${src}:${dst}${SELINUX_FLAG}")
done < <(podman inspect --format '{{range .Mounts}}{{printf "%s:%s\n" .Source .Destination}}{{end}}' "$CONTAINER_NAME")

# socket mount (mount host podman socket as /var/run/docker.sock inside container per Portainer docs)
if [ -n "$SOCKET_HOST" ] && [ -S "$SOCKET_HOST" ]; then
  SELINUX_FLAG=""
  if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null || echo Permissive)" = "Enforcing" ]; then
    SELINUX_FLAG=":Z"
  fi
  RUN_OPTS+=("-v" "${SOCKET_HOST}:/var/run/docker.sock${SELINUX_FLAG}")
  echo "Will mount socket $SOCKET_HOST -> /var/run/docker.sock inside container"
fi

# recommended ports for Portainer (ensure defaults exist if none detected)
if ! printf '%s\n' "${RUN_OPTS[@]}" | grep -q '\-p'; then
  RUN_OPTS+=("-p" "9000:9000" "-p" "9443:9443")
fi

echo "Recreating container with options:"
printf '  %s\n' "${RUN_OPTS[@]}"
echo

echo "Running: podman run -d --name $CONTAINER_NAME --restart=always ${RUN_OPTS[*]} $NEW_IMAGE"
podman run -d --name "$CONTAINER_NAME" --restart=always "${RUN_OPTS[@]}" "$NEW_IMAGE"

echo
echo "Upgrade attempted. Verify container and logs:"
podman ps --filter "name=^/${CONTAINER_NAME}$"
echo
echo "Recent logs (tail 200):"
podman logs --tail 200 "$CONTAINER_NAME" || true
echo
echo "Notes:"
echo "- If you run rootless Podman, ensure the container is created by the same user that owns the rootless socket,"
echo "  or use the system socket via 'sudo systemctl enable --now podman.socket' and run this script as root."
echo "- Inspect $INSPECT_JSON for any additional flags (env, network) to reapply."
echo "- Backup located at: ${BACKUP_DIR:-<none>}"
# ...existing code...