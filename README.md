# many-claude — One Claude Code account per project

[![test](https://github.com/TOMOSIA-VIETNAM/many-claude/actions/workflows/test.yml/badge.svg?branch=master)](https://github.com/TOMOSIA-VIETNAM/many-claude/actions/workflows/test.yml)

English | [Tiếng Việt](README.vi.md)

`many-claude` lets you use several Claude Code (subscription) accounts on one machine. Each project is bound to an account; when you `cd` into the project and run `claude`, the matching account is used automatically.

- Writes nothing into project folders — nothing to accidentally commit.
- Settings, skills, plugins, hooks and `CLAUDE.md` are shared across accounts.
- Claude Code CLI on zsh (macOS) only.

The control command is `mclaude` (many-claude). It is a shell function defined by this tool (not a system or Claude Code command), loaded into zsh at install time.

## How it works

Claude Code reads the `CLAUDE_CONFIG_DIR` environment variable to locate its config directory (login session, history, memory). The tool gives each account its own config directory and wraps the `claude` command in a shell function:

1. Take the current directory (`$PWD`).
2. Look it up in the map file `~/.many-claude/projects.conf` and pick the line with the **longest** matching path (subdirectories inherit their parent's profile).
3. Set `CLAUDE_CONFIG_DIR=~/.many-claude/profiles/<profile>` and run the real Claude Code.
4. If nothing matches, use `~/.claude` as usual (the `default` profile).

```
~/.claude/                         # "default" profile + shared config source (never modified by the tool)
~/.many-claude/                    # everything the tool owns lives here
├── mclaude.zsh                    # the script, sourced from ~/.zshrc
├── projects.conf                  # map: path → profile
└── profiles/
    ├── client-x/                  # account B
    │   ├── settings.json -> ~/.claude/settings.json
    │   ├── skills        -> ~/.claude/skills
    │   ├── ...                    # other shared symlinks
    │   ├── .claude.json           # private: account info, onboarding
    │   └── projects/              # private: memory, history
    └── client-y/                  # account C
```

## Install

One command:

```zsh
./install.sh && source ~/.zshrc
```

`install.sh` will:
- Create `~/.many-claude/` (with `profiles/` and `projects.conf`) and **copy** `mclaude.zsh` into it — you can delete the repo afterwards.
- Append one `source ~/.many-claude/mclaude.zsh` line to `~/.zshrc` (only once).
- Clean up the old `~/.config/claude-switch` layout if present.

Re-run `install.sh` any time to update the script; profiles and bindings are kept.

`source ~/.zshrc` loads `mclaude` into the current terminal; new terminals get it automatically.

Check:

```zsh
mclaude list
mclaude which
```

## Quick start

Example: use company B's account for every project under `~/Project/ClientX`.

```zsh
mclaude add client-x                      # 1. create the profile
mclaude login client-x                    # 2. sign in to account B (opens a browser)
mclaude bind client-x ~/Project/ClientX   # 3. bind the folder to the profile

cd ~/Project/ClientX/api
claude                                    # → runs with account B
```

Check which account is in use:

```zsh
cd ~/Project/ClientX && mclaude status    # account B
mclaude status default                    # original account, unaffected
```

## Commands

| Command | Description |
|---|---|
| `mclaude` / `mclaude which` | Print the profile and config dir for the current directory |
| `mclaude list` | List profiles and all bindings |
| `mclaude add <profile>` | Create a profile in `~/.many-claude/profiles/<profile>` with shared-config symlinks |
| `mclaude login [profile]` | Sign in for a profile (default: the current directory's profile) |
| `mclaude logout [profile]` | Sign out of a profile |
| `mclaude status [profile]` | Show a profile's sign-in status |
| `mclaude bind <profile> [path]` | Bind a folder to a profile (default: current directory). Re-binding the same folder replaces the old line |
| `mclaude unbind [path]` | Remove a folder's binding (default: current directory) |
| `mclaude help` | Show usage |
| `claude ...` | Run Claude Code with the current directory's profile; all arguments are passed through unchanged |

The name `default` is reserved for `~/.claude`.

## The `projects.conf` map

Each line: `<path> <profile>`. The profile is the last word, so paths may contain spaces. Lines starting with `#` are comments. `~` is allowed.

```
# ~/.many-claude/projects.conf
/Users/admin/Project/ClientX            client-x
/Users/admin/Project/ClientX/legacy     client-y
~/Project/My Side Project               personal
```

With the map above:

| Current directory | Profile |
|---|---|
| `~/Project/ClientX/api` | `client-x` |
| `~/Project/ClientX/legacy/web` | `client-y` (longer match) |
| `~/Project/My Side Project` | `personal` |
| `~/Downloads` | `default` |

Edit the file by hand or use `mclaude bind` / `mclaude unbind`. Paths reached through symlinks are resolved to their real path before matching.

## Shared config

When a profile is created (and each time `claude` runs with it), these items from `~/.claude` are symlinked into the profile if they exist:

```
settings.json  CLAUDE.md  RTK.md  keybindings.json  skills  plugins
hooks  agents  commands  output-styles  statusline.sh
```

Change something in `~/.claude` and every profile sees it. To share more items, add them to the `MCLAUDE_SHARED` array in `mclaude.zsh`. To give one profile its own copy of an item, delete the symlink in the profile folder and put a real file there — `mclaude` never overwrites existing files.

**Not shared** (per profile): login session, `.claude.json` (account info, user-scope MCP servers), `projects/` (per-project memory and history).

## Environment variables

Set these before the `source` line in `~/.zshrc` to change the default locations:

| Variable | Default | Meaning |
|---|---|---|
| `MCLAUDE_HOME` | `~/.many-claude` | Where `projects.conf` lives |
| `MCLAUDE_PROFILES` | `$MCLAUDE_HOME/profiles` | Where profile folders live |
| `MCLAUDE_BASE` | `~/.claude` | The `default` profile and shared-config source |

## Notes

- **No account switch mid-session.** The profile is chosen when `claude` starts. If you move to another project during a session, exit and start again.
- **Manual override:** if `CLAUDE_CONFIG_DIR` is already set in the environment, the wrapper respects it and skips the map. Example of a one-off run with another account: `CLAUDE_CONFIG_DIR=~/.many-claude/profiles/client-y claude`.
- **User-scope MCP servers** live in each profile's `.claude.json`, so add them again per profile (`claude mcp add --scope user ...`).
- **zsh CLI only.** VS Code/JetBrains extensions, `sh`/`bash` scripts, or calling the binary directly (`command claude`, `~/.local/bin/claude`) bypass the wrapper.
- **macOS Keychain:** subscription logins are stored in the Keychain. After the first login for a new profile, run `mclaude status default` to make sure the original account was not replaced. If it was, profiles are sharing one Keychain entry — please report it so we can switch to per-profile tokens (`claude setup-token`).
- If `mclaude login` does not work with your Claude Code version, go to the project folder, run `claude`, then type `/login`.

## Running tests

```zsh
zsh tests/test.zsh
```

No dependencies. Each test runs in a temporary HOME with a fake `claude`, so the real `~/.claude`, `~/.many-claude` and `~/.zshrc` are never touched. Covered: profile resolution (subdirectories, longest match, sibling paths, spaces, symlinks, `~`, comments), the `CLAUDE_CONFIG_DIR` override, profile creation and shared symlinks, `bind`/`unbind`/`list`/`which`/`help`, `login`/`logout`/`status`, robustness against user shell options, `install.sh` (fresh, re-run, old-layout migration) and `uninstall.sh` (keep or delete profiles, including the interactive prompt).

The tests do not cover real sign-in or the Keychain — check those by hand with real accounts.

## Uninstall

One command:

```zsh
./uninstall.sh
```

- Removes the `source` line from `~/.zshrc`.
- If profiles exist, asks whether to delete them (default **no**):
  - `N`: removes only `mclaude.zsh` and `projects.conf`, keeping `~/.many-claude/profiles/` — reinstall later to keep using them.
  - `y`: signs out of each profile, then deletes all of `~/.many-claude`. **This permanently deletes the login sessions, memory and history of those accounts.**
- Remove everything without asking (for scripts): `./uninstall.sh --purge`.

`~/.claude` (the `default` profile) is never touched. After uninstalling, open a new terminal (or run `exec zsh`) so the current shell drops `mclaude`.

## License

[MIT](LICENSE)
