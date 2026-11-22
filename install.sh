#!/bin/zsh
# Install mclaude: copy mclaude.zsh and its zsh completion into ~/.mclaude and
# source it from ~/.zshrc.
# Safe to re-run (updates the script, keeps profiles and bindings).
set -e
home=$HOME/.mclaude
src=${0:A:h}/mclaude.zsh
completion=${0:A:h}/completions/_mclaude
rc=$HOME/.zshrc
marker='# mclaude'
line='[[ -r ~/.mclaude/mclaude.zsh ]] && source ~/.mclaude/mclaude.zsh'

# Print a finished step with a check mark (green on a terminal, unless NO_COLOR is set).
ok() {
  if [[ -t 1 && -z ${NO_COLOR-} ]]; then print -r -- $'\e[32m✓\e[0m '"$*"
  else print -r -- "✓ $*"; fi
}

[[ -r $src && -r $completion ]] || { print -u2 "mclaude.zsh or completions/_mclaude not found next to install.sh"; exit 1 }

mkdir -p $home/profiles $home/completions
chmod 700 $home $home/profiles
cp $src $home/mclaude.zsh
cp $completion $home/completions/_mclaude
touch $home/projects.conf
ok "Copied mclaude.zsh and completion to $home"

# Clean up earlier layouts: ~/.config/claude-switch and the "ccp" command.
rm -f $home/ccp.zsh
if [[ -f $rc ]]; then
  sed -i '' \
    -e '/^# Per-project Claude Code accounts$/d' -e '/claude-switch\/ccp\.zsh/d' \
    $rc
fi
[[ -L $HOME/.config/claude-switch/ccp.zsh ]] && rm $HOME/.config/claude-switch/ccp.zsh
rmdir $HOME/.config/claude-switch 2>/dev/null || true
ok "Cleaned up earlier layouts"

if ! grep -qF "$line" $rc 2>/dev/null; then
  grep -qxF "$marker" $rc 2>/dev/null || print "\n$marker" >> $rc
  print "$line" >> $rc
  ok "Added mclaude hook to $rc"
else
  ok "mclaude hook already in $rc"
fi

ok "mclaude installed in $home"
print "next: source ~/.zshrc && mclaude list"
