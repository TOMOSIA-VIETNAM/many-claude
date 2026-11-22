#!/bin/zsh
# Uninstall mclaude: remove the ~/.zshrc hook and ~/.mclaude.
# Profiles hold logins, memory and history; they are deleted only after confirmation
# (or with --purge). ~/.claude (default profile) is never touched.
set -e
home=$HOME/.mclaude
rc=$HOME/.zshrc
purge=0

# Print a finished step with a check mark (green on a terminal, unless NO_COLOR is set).
ok() {
  if [[ -t 1 && -z ${NO_COLOR-} ]]; then print -r -- $'\e[32m✓\e[0m '"$*"
  else print -r -- "✓ $*"; fi
}
[[ $1 == --purge ]] && purge=1

if [[ -f $rc ]]; then
  sed -i '' \
    -e '/^# mclaude$/d' -e '/\.mclaude\/mclaude\.zsh/d' \
    $rc
  ok "Removed mclaude hook from $rc"
fi

profiles=($home/profiles/*(N/))
if (( ${#profiles} )); then
  print "Profiles found: ${profiles:t}"
  if (( ! purge )); then
    read -q "?Delete all profiles (logins, memory, history)? This cannot be undone. [y/N] " && purge=1
    print
  fi
  if (( ! purge )); then
    rm -f $home/mclaude.zsh $home/ccp.zsh $home/projects.conf
    rm -rf $home/completions
    ok "Removed mclaude. Profiles kept in $home/profiles"
    exit 0
  fi
  for p in $profiles; do   # sign out first so stored credentials are cleaned up
    if CLAUDE_CONFIG_DIR=$p command claude auth logout >/dev/null 2>&1; then
      ok "Signed out profile ${p:t}"
    fi
  done
fi

rm -rf $home
ok "Deleted $home"
ok "mclaude uninstalled. Open a new terminal (or exec zsh) to drop mclaude from this shell."
