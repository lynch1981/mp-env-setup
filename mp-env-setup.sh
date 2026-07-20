#!/usr/bin/env bash
# mp-env-setup.sh — Create an Ubuntu multipass VM (reuse only with --reuse),
# sync local files, post-process, and install packages.
#
# Design: config + ordered pipeline of steps. To extend, edit a step
# function (list of transfer_to_vm / vm calls) or add a name to STEPS.
set -euo pipefail

# =============================================================================
# CONFIG — defaults (override via env vars or CLI flags)
# =============================================================================

VM_NAME="${VM_NAME:-work}"
UBUNTU_RELEASE="${UBUNTU_RELEASE:-24.04}"
CPUS="${CPUS:-2}"
MEMORY="${MEMORY:-4G}"
DISK="${DISK:-20G}"

# If the VM already exists: exit unless REUSE=1 / --reuse.
REUSE="${REUSE:-0}"

REMOTE_USER="ubuntu"
REMOTE_HOME="/home/${REMOTE_USER}"
REMOTE_SSH_DIR="${REMOTE_HOME}/.ssh"

# Pipeline (order matters). Comment out a name to disable a step.
STEPS=(
  ensure_vm
  wait_ready
  sync_files
  post_process
  setup_ssh
  install_packages
)

# =============================================================================
# LOGGING / ERRORS
# =============================================================================

log()  { printf '==> %s\n' "$*"; }
info() { printf '    %s\n' "$*"; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
  cat <<EOF
Usage: $(basename "$0") [options]

Launch a new Ubuntu multipass VM (or reuse with --reuse), sync files,
post-process, and install packages.

By default, if the VM already exists the script exits. Pass --reuse to
keep using it.

Options:
  -n, --name NAME         VM name (default: $VM_NAME)
  -r, --release VER       Ubuntu release (default: $UBUNTU_RELEASE)
  -c, --cpus N            CPUs (default: $CPUS)
  -m, --memory SIZE       Memory (default: $MEMORY)
  -d, --disk SIZE         Disk (default: $DISK)
      --reuse             Reuse existing VM (start if stopped)
  -h, --help              Show this help

Env vars:
  VM_NAME UBUNTU_RELEASE CPUS MEMORY DISK REUSE
EOF
}

# =============================================================================
# ARG PARSE
# =============================================================================

while [[ $# -gt 0 ]]; do
  case "$1" in
    -n|--name)        VM_NAME="$2"; shift 2 ;;
    -r|--release)     UBUNTU_RELEASE="$2"; shift 2 ;;
    -c|--cpus)        CPUS="$2"; shift 2 ;;
    -m|--memory)      MEMORY="$2"; shift 2 ;;
    -d|--disk)        DISK="$2"; shift 2 ;;
    --reuse)          REUSE=1; shift ;;
    -h|--help)        usage; exit 0 ;;
    *)                die "unknown option: $1 (try --help)" ;;
  esac
done

# =============================================================================
# VM HELPERS
# =============================================================================

vm() {
  multipass exec "$VM_NAME" -- bash -lc "set -euo pipefail; $*"
}

# apt-get install on the VM (noninteractive). Usage: vm_install git curl htop
vm_install() {
  vm "sudo DEBIAN_FRONTEND=noninteractive apt-get install -y $*"
}

transfer_to_vm() {
  local src="$1" dest="$2"
  [[ -r "$src" ]] || die "cannot read: $src"
  multipass transfer "$src" "${VM_NAME}:${dest}"
}

# Via /tmp first — multipass can fail writing straight into ~/.ssh.
# Usage: push_ssh_file LOCAL_PATH MODE
push_ssh_file() {
  local src="$1" mode="$2" base
  base="$(basename "$src")"
  [[ -r "$src" ]] || die "cannot read SSH file: $src"
  info "$base (mode $mode)"
  transfer_to_vm "$src" "/tmp/$base"
  vm "mv '/tmp/$base' '$REMOTE_SSH_DIR/$base'
      chmod '$mode' '$REMOTE_SSH_DIR/$base'
      chown $REMOTE_USER:$REMOTE_USER '$REMOTE_SSH_DIR/$base' 2>/dev/null || true"
}

# =============================================================================
# PREFLIGHT
# =============================================================================

preflight() {
  command -v multipass >/dev/null \
    || die "multipass not found; install from https://multipass.run"
}

# =============================================================================
# STEPS — edit these functions to change what the VM gets
# =============================================================================

launch_vm() {
  log "Launching Ubuntu $UBUNTU_RELEASE VM '$VM_NAME' (cpus=$CPUS mem=$MEMORY disk=$DISK)..."
  multipass launch "$UBUNTU_RELEASE" \
    --name "$VM_NAME" \
    --cpus "$CPUS" \
    --memory "$MEMORY" \
    --disk "$DISK"
}

ensure_vm() {
  local state
  state="$(multipass info "$VM_NAME" 2>/dev/null \
    | awk -F': *' '/^State:/{print $2; exit}' || true)"

  # No VM yet — always launch.
  if [[ -z "$state" ]]; then
    launch_vm
    return
  fi

  if [[ "$REUSE" -ne 1 ]]; then
    die "VM '$VM_NAME' already exists (state: $state). Use --reuse to keep it."
  fi

  case "$state" in
    Stopped)
      log "Starting existing VM '$VM_NAME'..."
      multipass start "$VM_NAME"
      ;;
    *)
      log "VM '$VM_NAME' already $state — reusing it."
      ;;
  esac
}

wait_ready() {
  log "Waiting for VM to be ready..."
  local i
  for i in $(seq 30); do
    multipass exec "$VM_NAME" -- true 2>/dev/null && return 0
    sleep 1
  done
  multipass exec "$VM_NAME" -- true || die "VM '$VM_NAME' is not ready"
}

# Edit this function to copy more local files into the VM.
# Transfer only — unpacking belongs in post_process.
sync_files() {
  log "Syncing files..."
  transfer_to_vm "$HOME/vim.tgz" "${REMOTE_HOME}/vim.tgz"
  # transfer_to_vm "$HOME/dotfiles.tgz" "${REMOTE_HOME}/dotfiles.tgz"
  # transfer_to_vm "$HOME/.gitconfig" "${REMOTE_HOME}/.gitconfig"
}

# Edit this function for unpack / chmod / wiring after files land.
post_process() {
  log "Post-processing on VM..."
  vm "cd '$REMOTE_HOME' && tar -xzf vim.tgz"
  # vm "cd '$REMOTE_HOME' && tar -xzf dotfiles.tgz"
}

# Pushes ~/.ssh/config and every id_* key/pub file.
setup_ssh() {
  log "Setting up SSH..."
  vm "mkdir -p '$REMOTE_SSH_DIR' && chmod 700 '$REMOTE_SSH_DIR'"
  push_ssh_file "$HOME/.ssh/config" 600

  local path
  shopt -s nullglob
  for path in "$HOME/.ssh"/id_*; do
    [[ -f "$path" ]] || continue
    case "$path" in
      *.pub) push_ssh_file "$path" 644 ;;
      *)     push_ssh_file "$path" 600 ;;
    esac
  done
  shopt -u nullglob
}

# Edit this function to install software / run setup on the VM.
install_packages() {
  log "Installing packages..."
  vm "sudo apt-get update -qq"
  vm_install git curl
  # vm_install htop tmux
  # vm "curl -fsSL https://example.com/install.sh | bash"
}

# =============================================================================
# MAIN
# =============================================================================

main() {
  preflight

  local step
  for step in "${STEPS[@]}"; do
    if ! declare -f "$step" >/dev/null; then
      die "unknown step in STEPS: $step"
    fi
    "$step"
  done

  log "Done. VM '$VM_NAME' is ready."
}

main "$@"
