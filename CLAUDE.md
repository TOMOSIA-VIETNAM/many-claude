# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

mclaude: a zsh tool (macOS) that binds each project folder to its own Claude Code subscription account. No build step, no dependencies — three zsh scripts plus a test suite. User-facing docs: `README.md` (English) and `README.vi.md` (Vietnamese); keep both in sync when behavior changes.

## Commands

```zsh
zsh tests/test.zsh               # run all tests
zsh tests/test.zsh '*unbind*'    # run tests whose name (without test_ prefix) matches a glob
./install.sh && source ~/.zshrc  # install/update the live copy in ~/.mclaude
```

`install.sh` **copies** `mclaude.zsh` into `~/.mclaude/`, so edits in the repo do not affect the user's shell until `install.sh` is re-run.

## Architecture

- `mclaude.zsh` is sourced from `~/.zshrc` and defines two public functions:
  - `claude` — wrapper that shadows the real binary. Resolves `$PWD` against `~/.mclaude/projects.conf` (longest path prefix wins, symlinks resolved with `:A`), sets `CLAUDE_CONFIG_DIR=~/.mclaude/profiles/<profile>`, then runs `command claude`. No match → profile `default` = plain `~/.claude` (no env var set). A pre-set `CLAUDE_CONFIG_DIR` bypasses the map.
  - `mclaude` — management CLI (`add`, `bind`, `unbind`, `which`, `list`, `login|logout|status` → `claude auth <cmd>`, `help`).
- Map format: one `<path> <profile>` per line; the profile is the **last word**, so paths may contain spaces. Both the resolver and `_mclaude_unmap` (used by bind/unbind) rely on this rule — change them together.
- Shared config: `_mclaude_link_shared` symlinks the items in `MCLAUDE_SHARED` from `~/.claude` into each profile (on `add` and on every wrapper run), never overwriting existing files or symlinks. Login, `.claude.json` and `projects/` stay per profile.
- `install.sh` / `uninstall.sh` own the `~/.zshrc` hook (`# mclaude` marker + source line) and also clean up earlier layouts (`~/.config/claude-switch`, the old `ccp` command/`ccp.zsh`, the `~/.many-claude` home and `# many-claude` hook from before the rename — `install.sh` moves that home to `~/.mclaude`). Keep that migration code when touching them.

## Invariants

- Never write anything into project folders, and never modify `~/.claude` (it is the default profile and the shared-config source).
- Every function in `mclaude.zsh` that does real work starts with `emulate -L zsh` so the user's shell options (`nounset`, `sh_word_split`, `ksh_arrays`, …) cannot break it; a test enforces this.
- Scripts target macOS/BSD tools: `sed -i ''`, `stat -f`, `script -q /dev/null` (tests).
- Profile deletion in `uninstall.sh` is destructive and must stay opt-in (prompt defaulting to no, or `--purge`), and it signs out each profile before deleting.

## Tests

`tests/test.zsh` is a self-contained runner: every `test_*` function runs in its own subshell with a temporary `HOME` and a fake `claude` on `PATH` that echoes and logs (`$FAKE_LOG`) the `CLAUDE_CONFIG_DIR` and arguments it received. `fail` exits the subshell, so a failed assertion stops the test. The interactive `read -q` prompt in `uninstall.sh` is exercised through a pseudo-tty via `script`. Real sign-in and macOS Keychain separation between profiles are not testable here; they have been verified by hand with real accounts.
