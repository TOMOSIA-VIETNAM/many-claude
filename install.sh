#!/bin/zsh
# Install mclaude: copy mclaude.zsh and its zsh completion into ~/.mclaude and
# source it from ~/.zshrc.
# Safe to re-run (updates the script, keeps profiles and bindings).
set -e
home=$HOME/.mclaude
old_home=$HOME/.many-claude
src=${0:A:h}/mclaude.zsh
completion=${0:A:h}/completions/_mclaude
rc=$HOME/.zshrc
marker='# mclaude'
line='[[ -r ~/.mclaude/mclaude.zsh ]] && source ~/.mclaude/mclaude.zsh'

[[ -r $src && -r $completion ]] || { print -u2 "mclaude.zsh or completions/_mclaude not found next to install.sh"; exit 1 }

# Move data from the previous home (~/.many-claude) so profiles and bindings survive.
if [[ -d $old_home && ! -e $home ]]; then
  mv $old_home $home
  print "moved $old_home -> $home (sign in again per profile if mclaude status says logged out)"
elif [[ -d $old_home ]]; then
  print -u2 "warning: both $old_home and $home exist; leaving $old_home untouched"
fi

mkdir -p $home/profiles $home/completions
chmod 700 $home $home/profiles
cp $src $home/mclaude.zsh
cp $completion $home/completions/_mclaude
touch $home/projects.conf

# Clean up earlier layouts: ~/.config/claude-switch, the "ccp" command, the ~/.many-claude hook.
rm -f $home/ccp.zsh
if [[ -f $rc ]]; then
  sed -i '' \
    -e '/^# Per-project Claude Code accounts$/d' -e '/claude-switch\/ccp\.zsh/d' \
    -e '/^# many-claude$/d' -e '/\.many-claude\/ccp\.zsh/d' -e '/\.many-claude\/mclaude\.zsh/d' \
    $rc
fi
[[ -L $HOME/.config/claude-switch/ccp.zsh ]] && rm $HOME/.config/claude-switch/ccp.zsh
rmdir $HOME/.config/claude-switch 2>/dev/null || true

if ! grep -qF "$line" $rc 2>/dev/null; then
  grep -qxF "$marker" $rc 2>/dev/null || print "\n$marker" >> $rc
  print "$line" >> $rc
fi

print "mclaude installed in $home"
print "next: source ~/.zshrc && mclaude list"
