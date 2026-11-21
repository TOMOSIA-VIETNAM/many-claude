# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-21

First release.

### Added

- `claude` wrapper that picks the Claude Code account for the current folder from `~/.mclaude/projects.conf` (longest path prefix wins; subfolders inherit, symlinks resolved, paths may contain spaces) and sets `CLAUDE_CONFIG_DIR`. Falls back to the plain `~/.claude` (`default` profile); an already-set `CLAUDE_CONFIG_DIR` is respected.
- `mclaude` command: `add`, `remove`, `bind`, `unbind`, `which`, `list`, `login`, `logout`, `status`, `doctor`, `version`, `help`.
- `mclaude list` shows the account (email) each profile is signed in to.
- `mclaude remove [-y] <profile>` signs out, deletes the profile and drops its bindings, after confirmation.
- `mclaude doctor` checks `claude` on PATH, the `~/.zshrc` hook, sign-in of every profile, profiles sharing one account, broken shared symlinks and bindings to missing profiles or folders.
- zsh tab completion for `mclaude`, installed by `install.sh`.
- Shared config: `settings.json`, `CLAUDE.md`, `keybindings.json`, `skills`, `plugins`, `hooks`, `agents`, `commands`, `output-styles` and `statusline.sh` are symlinked from `~/.claude` into every profile; login, `.claude.json` and `projects/` stay per profile.
- `install.sh` / `uninstall.sh`, with migration from earlier layouts (`~/.many-claude`, `ccp`, `~/.config/claude-switch`). Deleting profiles on uninstall is opt-in.
- Test suite (`zsh tests/test.zsh`) and CI on GitHub Actions (macOS).
- English and Vietnamese README, logo, MIT license.

[0.1.0]: https://github.com/TOMOSIA-VIETNAM/mclaude/releases/tag/v0.1.0
