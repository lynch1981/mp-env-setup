#!/usr/bin/env bash
# setup-env.sh — Launch an Ubuntu work VM with multipass, install vim.tgz, then login.
set -euo pipefail

# ---------------------------------------------------------------------------
# Config (override via env or flags)
# ---------------------------------------------------------------------------
VM_NAME="${VM_NAME:-work}"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-24.04}"
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-4G}"
DISK="${DISK:-20G}"
VIM_TGZ="${VIM_TGZ:-$HOME/vim.tgz}"
SSH_DIR="${SSH_DIR:-$HOME/.ssh}"
SSH_CONFIG="${SSH_CONFIG:-$SSH_DIR/config}"

REMOTE_HOME="/home/ubuntu"
REMOTE_SSH_DIR="$REMOTE_HOME/.ssh"

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Launch an Ubuntu multipass VM, copy vim.tgz + SSH config/keys onto it,
unpack vim.tgz, then open a shell.

Options:
  -n, --name NAME       VM name (default: $VM_NAME)
  -r, --release VER     Ubuntu release (default: $UBUNTU_RELEASE)
  -c, --cpus N          CPUs (default: $CPUS)
  -m, --memory SIZE     Memory (default: $MEMORY)
  -d, --disk SIZE       Disk (default: $DISK)
  -f, --file PATH       Path to vim.tgz (default: $VIM_TGZ)
  -s, --ssh-config PATH Path to SSH config (default: $SSH_CONFIG)
      --ssh-dir PATH    Path to local SSH directory (default: $SSH_DIR)
  -h, --help            Show this help

Env vars: VM_NAME UBUNTU_RELEASE CPUS MEMORY DISK VIM_TGZ SSH_CONFIG SSH_DIR
EOF
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)       VM_NAME="$2"; shift 2 ;;
    -r|--release)    UBUNTU_RELEASE="$2"; shift 2 ;;
    -c|--cpus)       CPUS="$2"; shift 2 ;;
    -m|--memory)     MEMORY="$2"; shift 2 ;;
    -d|--disk)       DISK="$2"; shift 2 ;;
    -f|--file)       VIM_TGZ="$2"; shift 2 ;;
    -s|--ssh-config) SSH_CONFIG="$2"; shift 2 ;;
    --ssh-dir)       SSH_DIR="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *)               die "unknown option: $1 (try --help)" ;;
  esac
done

# ---------------------------------------------------------------------------
# Preflight
# ---------------------------------------------------------------------------
command -v multipass >/dev/null || die "multipass not found; install from https://multipass.run"
[[ -f "$VIM_TGZ" ]]    || die "vim archive not found: $VIM_TGZ"
[[ -d "$SSH_DIR" ]]    || die "SSH directory not found: $SSH_DIR"
[[ -f "$SSH_CONFIG" ]] || die "SSH config not found: $SSH_CONFIG"

# Run a command inside the VM as ubuntu, with strict mode.
vm() { multipass exec "$VM_NAME" -- bash -lc "set -euo pipefail; $*"; }

# Install software on the VM. Edit this function when you need new packages.
install_packages() {
  log "Installing packages..."
  vm "sudo apt-get update -qq"
  vm "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y git curl"
  # vm "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y htop"
}

# ---------------------------------------------------------------------------
# Launch or reuse VM
# ---------------------------------------------------------------------------
STATE="$(multipass info "$VM_NAME" 2>/dev/null | awk -F': *' '/^State:/{print $2; exit}' || true)"

case "$STATE" in
  "")
    log "Launching Ubuntu $UBUNTU_RELEASE VM '$VM_NAME' (cpus=$CPUS mem=$MEMORY disk=$DISK)..."
    multipass launch "$UBUNTU_RELEASE" --name "$VM_NAME" \
      --cpus "$CPUS" --memory "$MEMORY" --disk "$DISK"
    ;;
  Stopped)
    log "Starting existing VM '$VM_NAME'..."
    multipass start "$VM_NAME"
    ;;
  *)
    log "VM '$VM_NAME' already $STATE — reusing it."
    ;;
esac

log "Waiting for VM to be ready..."
for _ in $(seq 30); do
  multipass exec "$VM_NAME" -- true 2>/dev/null && break
  sleep 1
done
multipass exec "$VM_NAME" -- true || die "VM '$VM_NAME' is not ready"

# ---------------------------------------------------------------------------
# Copy + unpack vim.tgz
# ---------------------------------------------------------------------------
log "Copying vim.tgz and unpacking on the VM..."
multipass transfer "$VIM_TGZ" "${VM_NAME}:${REMOTE_HOME}/vim.tgz"
vm "cd '$REMOTE_HOME' && tar -xzf vim.tgz"

# ---------------------------------------------------------------------------
# Sync SSH config + keys
# ---------------------------------------------------------------------------
# Copy a local file into the remote ~/.ssh with a given mode.
# Transfer via /tmp first — multipass can fail writing straight into ~/.ssh.
push_ssh_file() {
  local src="$1" mode="$2" base
  base="$(basename "$src")"
  [[ -r "$src" ]] || die "cannot read SSH file: $src"
  log "  $base (mode $mode)"
  multipass transfer "$src" "${VM_NAME}:/tmp/$base"
  vm "mv '/tmp/$base' '$REMOTE_SSH_DIR/$base'
      chmod '$mode' '$REMOTE_SSH_DIR/$base'
      chown ubuntu:ubuntu '$REMOTE_SSH_DIR/$base' 2>/dev/null || true"
}

is_private_key() {
  [[ -r "$1" ]] && head -n1 "$1" 2>/dev/null | grep -q 'PRIVATE KEY'
}

# Dedup helper (bash 3.2 compatible — no associative arrays on macOS /bin/bash).
SEEN=" "
already_seen() {
  case "$SEEN" in *" $1 "*) return 0 ;; *) return 1 ;; esac
}
mark_seen() { SEEN="${SEEN}${1} "; }

log "Setting up ${VM_NAME}:${REMOTE_SSH_DIR}..."
vm "mkdir -p '$REMOTE_SSH_DIR' && chmod 700 '$REMOTE_SSH_DIR'"
push_ssh_file "$SSH_CONFIG" 600

log "Syncing SSH keys from $SSH_DIR..."
keys=0 pubs=0

shopt -s nullglob
for path in "$SSH_DIR"/id_* "$SSH_DIR"/*; do
  [[ -f "$path" ]] || continue
  base="$(basename "$path")"
  already_seen "$base" && continue

  case "$base" in
    config|config~|known_hosts|known_hosts.old|authorized_keys|authorized_keys2)
      continue ;;
    *.pub)
      # Sync standalone .pub only for id_* keys; other pubs handled with their key.
      [[ "$base" == id_*.pub ]] || continue
      mark_seen "$base"
      push_ssh_file "$path" 644
      pubs=$((pubs + 1))
      continue ;;
  esac

  # Private keys: always id_*, or anything else that looks like a private key.
  if [[ "$base" == id_* ]] || is_private_key "$path"; then
    mark_seen "$base"
    push_ssh_file "$path" 600
    keys=$((keys + 1))
    if [[ -f "$path.pub" ]] && ! already_seen "$base.pub"; then
      mark_seen "$base.pub"
      push_ssh_file "$path.pub" 644
      pubs=$((pubs + 1))
    fi
  fi
done
shopt -u nullglob

if [[ "$keys" -eq 0 && "$pubs" -eq 0 ]]; then
  log "warning: no SSH keys found in $SSH_DIR (expected e.g. id_ed25519 / id_ed25519.pub)"
else
  log "Synced $keys private key(s) and $pubs public key(s)."
fi

# ---------------------------------------------------------------------------
# Install packages (edit install_packages above)
# ---------------------------------------------------------------------------
install_packages

# ---------------------------------------------------------------------------
# Login
# ---------------------------------------------------------------------------
log "Done. Logging into '$VM_NAME'..."
exec multipass shell "$VM_NAME"
