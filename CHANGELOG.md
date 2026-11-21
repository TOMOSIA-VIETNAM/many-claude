# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [0.1.0] - 2026-11-21

First release.

### Added

- `claude` wrapper that picks the Claude Code account for the current folder from `~/.mclaude/projects.conf` (longest path prefix wins; subfolders inherit, symlinks resolved, paths may contain spaces) and sets `CLAUDE_CONFIG_DIR`. Falls back to the plain `~/.claude` (`default` profile); an already-set `CLAUDE_CONFIG_DIR` is respected.
- `mclaude` command: `add`, `bind`, `unbind`, `which`, `list`, `login`, `logout`, `status`, `help`.
- Shared config: `settings.json`, `CLAUDE.md`, `keybindings.json`, `skills`, `plugins`, `hooks`, `agents`, `commands`, `output-styles` and `statusline.sh` are symlinked from `~/.claude` into every profile; login, `.claude.json` and `projects/` stay per profile.
- `install.sh` / `uninstall.sh`, with migration from earlier layouts (`~/.many-claude`, `ccp`, `~/.config/claude-switch`). Deleting profiles on uninstall is opt-in.
- Test suite (`zsh tests/test.zsh`) and CI on GitHub Actions (macOS).
- English and Vietnamese README, logo, MIT license.

[0.1.0]: https://github.com/TOMOSIA-VIETNAM/mclaude/releases/tag/v0.1.0
