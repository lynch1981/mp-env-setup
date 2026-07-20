# mp-env-setup

Create (or reuse) an Ubuntu multipass work VM, sync local files, post-process them, and install packages.

## Requirements

- [Multipass](https://multipass.run)
- Bash (works with macOS system Bash 3.2+)
- `~/vim.tgz`, `~/.ssh/config`, and any `~/.ssh/id_*` keys

## Quick start

```bash
./mp-env-setup.sh
```

Defaults: VM name `work`, Ubuntu `24.04`, 2 CPUs, 4G RAM, 20G disk.

## Options

```bash
./mp-env-setup.sh                  # launch new; exit if VM already exists
./mp-env-setup.sh --reuse          # start/reuse existing VM
./mp-env-setup.sh -n dev -c 4 -m 8G -d 40G
```

| Flag | Purpose |
|------|---------|
| `-n / --name` | VM name |
| `-r / --release` | Ubuntu release |
| `-c / -m / -d` | CPUs / memory / disk |
| `--reuse` | Reuse existing VM (start if stopped) |

Default: if the VM already exists, print a message and exit.  
Env vars: `VM_NAME`, `UBUNTU_RELEASE`, `CPUS`, `MEMORY`, `DISK`, `REUSE`.

## Pipeline

```
ensure_vm → wait_ready → sync_files → post_process → setup_ssh → install_packages
```

Comment out a name in `STEPS` to disable a stage.

### Customize by editing step functions

```bash
sync_files() {
  log "Syncing files..."
  transfer_to_vm "$HOME/vim.tgz" "${REMOTE_HOME}/vim.tgz"
}

post_process() {
  log "Post-processing on VM..."
  vm "cd '$REMOTE_HOME' && tar -xzf vim.tgz"
}

setup_ssh() {
  push_ssh_file "$HOME/.ssh/config" 600
  # then every ~/.ssh/id_* (private → 600, .pub → 644)
}

install_packages() {
  log "Installing packages..."
  vm "sudo apt-get update -qq"
  vm_install git curl
}
```

### New step

1. Write a function, e.g. `setup_docker() { ... }`.
2. Add its name to `STEPS`.
