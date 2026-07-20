# Agent notes

## What this is

One bash script (`mp-env-setup.sh`) that stands up a personal Ubuntu multipass VM:

1. Launch a **new** VM (or reuse with `--reuse`)
2. Sync a few local files
3. Post-process them (e.g. unpack)
4. Push SSH config + `id_*` keys
5. Install packages via apt

No interactive shell at the end.

## Philosophy

**Simple and clear, not perfect.**

- Prefer a readable single script over clever abstractions.
- Prefer editing a step function (explicit `transfer_to_vm` / `vm` / `vm_install` lines) over config arrays and extra CLI flags.
- Don't add `--skip-*`, `--recreate`, cloud-init, package lists, or multi-file frameworks unless asked.
- Bash 3.2 safe (macOS `/bin/bash`). No associative arrays.
- Small diffs. Don't rewrite what isn't broken.

## Layout

```
mp-env-setup.sh   # the whole tool
README.md         # human usage
AGENT.md          # this file (for agents)
```

## VM lifecycle

| Case | Behavior |
|------|----------|
| VM does not exist | `multipass launch` |
| VM exists, no flag | **exit** with a clear error |
| VM exists + `--reuse` | start if Stopped, otherwise keep using it |

`REUSE=1` env is the same as `--reuse`. Do not re-add `--recreate` unless asked.

## Pipeline

`STEPS` at the top of the script. Each name is a function:

```
ensure_vm → wait_ready → sync_files → post_process → setup_ssh → install_packages
```

Comment a name out of `STEPS` to disable a stage. Add a new function + name for a new stage.

### What each step owns

| Step | Edit by… |
|------|----------|
| `sync_files` | Add `transfer_to_vm local remote` lines |
| `post_process` | Add `vm "..."` after files land (unpack, etc.) |
| `setup_ssh` | Already pushes `~/.ssh/config` + every `~/.ssh/id_*` (private 600, `.pub` 644) |
| `install_packages` | Add `vm_install pkg…` or `vm "..."` lines |

### Helpers

| Helper | Role |
|--------|------|
| `vm "cmd"` | `multipass exec` as default user, bash strict mode |
| `vm_install pkg…` | noninteractive `apt-get install -y` via `vm` |
| `transfer_to_vm src dest` | `multipass transfer` with a readability check |
| `push_ssh_file path mode` | transfer via `/tmp`, then `mv` + `chmod` into `~/.ssh` (direct transfer into `~/.ssh` can fail) |
| `log` / `info` / `die` | messages / hard fail |

## How to change things

| Want | Do |
|------|----|
| Copy another file | `transfer_to_vm` in `sync_files` |
| Unpack / fix up after copy | `vm` in `post_process` |
| More SSH keys | Name them `id_*` under `~/.ssh` |
| Install more software | `vm_install …` in `install_packages` |
| New stage | Write a function, add name to `STEPS` |
| Drop a stage | Comment it out of `STEPS` |
| VM size / name | `-n` `-c` `-m` `-d` / env `VM_NAME` etc. |
| Reuse existing VM | `--reuse` or `REUSE=1` |

## Don't

- Reintroduce `FILES_TO_SYNC` / `PACKAGES` arrays, `--skip-*`, `--recreate`, or cloud-init unless asked.
- Auto-scan all of `~/.ssh` — only `config` + `id_*`.
- Split into many modules without a clear need.
- Over-engineer CLI for one-off cases — edit the step functions.
- Break macOS bash 3.2 compatibility.
- Open a shell at the end (`login` was removed on purpose).
- "Improve" style for its own sake.

## Check

```bash
bash -n mp-env-setup.sh
./mp-env-setup.sh --help
```
