#!/bin/zsh
# Uninstall mclaude: remove the ~/.zshrc hook and ~/.mclaude.
# Profiles hold logins, memory and history; they are deleted only after confirmation
# (or with --purge). ~/.claude (default profile) is never touched.
set -e
home=$HOME/.mclaude
rc=$HOME/.zshrc
purge=0
[[ $1 == --purge ]] && purge=1

if [[ -f $rc ]]; then
  sed -i '' \
    -e '/^# mclaude$/d' -e '/\.mclaude\/mclaude\.zsh/d' \
    -e '/^# many-claude$/d' -e '/\.many-claude\/ccp\.zsh/d' -e '/\.many-claude\/mclaude\.zsh/d' \
    $rc
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
    print "Removed mclaude. Profiles kept in $home/profiles"
    exit 0
  fi
  for p in $profiles; do   # sign out first so stored credentials are cleaned up
    CLAUDE_CONFIG_DIR=$p command claude auth logout >/dev/null 2>&1 || true
  done
fi

rm -rf $home
print "mclaude uninstalled. Open a new terminal (or exec zsh) to drop mclaude from this shell."
