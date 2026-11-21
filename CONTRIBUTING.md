# Contributing to mclaude

Thanks for helping. `mclaude` is deliberately small: a few zsh scripts, no build step and no dependencies. Please keep it that way.

## Reporting a bug

Open an issue and include:

- what you ran and what happened (exact output or error),
- `mclaude version`, `mclaude doctor` and `mclaude which` from the folder involved,
- `zsh --version`, `claude --version` and your macOS version.

Remove emails and paths you do not want to share. Security problems go through [SECURITY.md](SECURITY.md), not public issues.

## Development setup

```zsh
git clone https://github.com/TOMOSIA-VIETNAM/mclaude.git
cd mclaude
zsh tests/test.zsh               # run all tests
zsh tests/test.zsh '*remove*'    # run tests whose name matches a glob
```

`install.sh` copies the scripts into `~/.mclaude`, so your shell keeps using the installed copy until you run `./install.sh && source ~/.zshrc` again.

The tests run in a temporary `HOME` with a fake `claude`, so they never touch your real `~/.claude`, `~/.mclaude` or `~/.zshrc`.

## Rules for changes

- **Never write into project folders, and never modify `~/.claude`.** It is the default profile and the source of shared config.
- **Start every function that does real work with `emulate -L zsh`**, so user shell options (`nounset`, `sh_word_split`, `ksh_arrays`, …) cannot break it. A test enforces this.
- **Target macOS/BSD tools** (`sed -i ''`, `stat -f`). No GNU-only flags, no new dependencies (no `jq`, no Python).
- **Keep destructive actions opt-in.** Deleting profiles asks first, defaults to no, and signs out before deleting.
- **The map format is `<path> <profile>`, profile = last word.** `_mclaude_bindings`, `_mclaude_unmap` and `_mclaude_unmap_profile` all rely on it; change them together.
- **Add or update tests** for every behavior change. `zsh tests/test.zsh` must pass; CI runs it on macOS along with `zsh -n` on every script.
- **Update both READMEs** (`README.md` and `README.vi.md`) when behavior changes, and add a line to `CHANGELOG.md`. If you cannot write Vietnamese, say so in the pull request and a maintainer will translate.

## Pull requests

- One topic per pull request; keep the diff focused.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for commit messages and the PR title: `feat:`, `fix:`, `docs:`, `test:`, `ci:`, `chore:`.
- Describe what changed, why, and how you tested it. If you checked something by hand with real accounts (sign-in, Keychain), say so.

By contributing you agree that your contribution is licensed under the [MIT License](LICENSE).
