# Security policy

`mclaude` decides which Claude Code config directory — and therefore which signed-in account — is used in each folder. A bug here can send work to the wrong account or expose another profile's data, so security reports are taken seriously.

## Supported versions

Only the latest release receives fixes.

## Reporting a vulnerability

**Do not open a public issue.** Report privately through GitHub: open the repository's **Security** tab and click **Report a vulnerability** ([direct link](https://github.com/TOMOSIA-VIETNAM/mclaude/security/advisories/new)).

Please include the affected version (`mclaude version`), steps to reproduce, and what an attacker could achieve. Never include real tokens, credentials or Keychain contents.

You can expect an acknowledgement within 7 days. Once a fix is released, the advisory is published with credit to the reporter unless you prefer to stay anonymous.

## In scope

- A folder resolving to the wrong profile, or the map file being bypassed or altered unexpectedly.
- Profile data (login, `.claude.json`, history, memory) readable by other users or leaking between profiles.
- `mclaude` writing into project folders or modifying `~/.claude`.
- `install.sh` / `uninstall.sh` deleting or exposing data they should not.

## Out of scope

- Vulnerabilities in Claude Code itself or in Anthropic's services — report those to Anthropic ([anthropic.com/responsible-disclosure-policy](https://www.anthropic.com/responsible-disclosure-policy)).
- Problems that need an attacker who can already run code as your user or edit your `~/.zshrc`.
