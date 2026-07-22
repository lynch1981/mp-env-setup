# mp-env-setup

Create an Ubuntu multipass work VM, sync local files from `data/`, post-process them, setup SSH, and run a guest init script.

## Requirements

- [Multipass](https://multipass.run)
- Bash (works with macOS system Bash 3.2+)
- `data/vim.tgz`, `data/init-env.sh`, `data/bash_aliases`
- `~/.ssh/config` and any `~/.ssh/id_*` keys

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
ensure_vm → wait_ready → sync_files → post_process → setup_ssh → init_env
```

- **Host** (`mp-env-setup.sh`): multipass, file sync, SSH
- **Guest** (`data/init-env.sh`): apt packages and other env setup

### Sync + post-process

```bash
sync_files() {
  transfer_to_vm "$ROOT/data/vim.tgz" "${REMOTE_HOME}/vim.tgz"
  transfer_to_vm "$ROOT/data/init-env.sh" "${REMOTE_HOME}/init-env.sh"
  transfer_to_vm "$ROOT/data/bash_aliases" "${REMOTE_HOME}/.bash_aliases"
}

post_process() {
  vm "cd '$REMOTE_HOME' && tar -xzf vim.tgz"
  vm "chmod +x '$REMOTE_HOME/init-env.sh'"
}
```

### Guest packages / env

Edit `data/init-env.sh`:

```bash
sudo apt-get update -qq
sudo apt-get install -y git curl tree net-tools
curl -fsSL https://x.ai/cli/install.sh | bash   # Grok Build
```

The host only runs it:

```bash
init_env() {
  vm "bash '$REMOTE_HOME/init-env.sh'"
}
```
