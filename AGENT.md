# Agent notes

## What this is

One host script (`mp-env-setup.sh`) that stands up a personal Ubuntu multipass VM:

1. Launch a **new** VM (or reuse with `--reuse`)
2. Sync files from `data/`
3. Post-process them (e.g. unpack)
4. Push SSH config + `id_*` keys
5. Run `data/init-env.sh` **on the guest** for packages / env setup

No interactive shell at the end.

## Philosophy

**Simple and clear, not perfect.**

- Prefer a readable single host script + a guest init script over clever abstractions.
- Prefer editing step functions / `data/init-env.sh` over config arrays and extra CLI flags.
- Don't add `--skip-*`, `--recreate`, cloud-init, package lists, or multi-file frameworks unless asked.
- Bash 3.2 safe on the **host** (macOS `/bin/bash`). No associative arrays in `mp-env-setup.sh`.
- Small diffs. Don't rewrite what isn't broken.

## Layout

```
mp-env-setup.sh     # host: multipass lifecycle + sync + steps
data/
  vim.tgz           # synced then unpacked on the guest
  init-env.sh       # synced then run on the guest (packages, env)
  bash_aliases      # synced to ~/.bash_aliases (Ubuntu bashrc sources it)
README.md
AGENT.md            # this file
```

## VM lifecycle

| Case | Behavior |
|------|----------|
| VM does not exist | `multipass launch` |
| VM exists, no flag | **exit** with a clear error |
| VM exists + `--reuse` | start if Stopped, otherwise keep using it |

`REUSE=1` env is the same as `--reuse`. Do not re-add `--recreate` unless asked.

## Pipeline

`STEPS` in `mp-env-setup.sh`:

```
ensure_vm → wait_ready → sync_files → post_process → setup_ssh → init_env
```

### What each step owns

| Step | Edit by… |
|------|----------|
| `sync_files` | `transfer_to_vm` lines; assets under `$ROOT/data/` |
| `post_process` | `vm "..."` after files land (unpack, chmod) |
| `setup_ssh` | `~/.ssh/config` + every `~/.ssh/id_*` via `push_ssh_file` |
| `init_env` | **do not put packages here** — edit `data/init-env.sh` |

### Host helpers

| Helper | Role |
|--------|------|
| `vm "cmd"` | `multipass exec` as default user, bash strict mode |
| `transfer_to_vm src dest` | `multipass transfer` with a readability check |
| `push_ssh_file path mode` | transfer via `/tmp`, then `mv` + `chmod` into `~/.ssh` |
| `log` / `info` / `die` | messages / hard fail |

There is no host-side `vm_install` — apt install belongs in `data/init-env.sh`.

## How to change things

| Want | Do |
|------|----|
| Copy another file | Put it in `data/`, add `transfer_to_vm` in `sync_files` |
| Unpack / fix up after copy | `vm` in `post_process` |
| More SSH keys | Name them `id_*` under `~/.ssh` |
| Install more software / guest setup | Edit `data/init-env.sh` |
| Grok Build on guest | Already installed in `data/init-env.sh` via `https://x.ai/cli/install.sh` |
| New host stage | Write a function, add name to `STEPS` |
| Drop a stage | Comment it out of `STEPS` |
| VM size / name | `-n` `-c` `-m` `-d` / env `VM_NAME` etc. |
| Reuse existing VM | `--reuse` or `REUSE=1` |

## Don't

- Put guest package lists back into `mp-env-setup.sh` (use `data/init-env.sh`).
- Reintroduce `FILES_TO_SYNC` / `PACKAGES` arrays, `--skip-*`, `--recreate`, or cloud-init unless asked.
- Auto-scan all of `~/.ssh` — only `config` + `id_*`.
- Split into many modules without a clear need.
- Over-engineer CLI for one-off cases — edit the scripts.
- Break host macOS bash 3.2 compatibility.
- Open a shell at the end (`login` was removed on purpose).
- "Improve" style for its own sake.

## Check

```bash
bash -n mp-env-setup.sh
bash -n data/init-env.sh
./mp-env-setup.sh --help
```
