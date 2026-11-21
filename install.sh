#!/bin/zsh
# Install many-claude: copy mclaude.zsh into ~/.many-claude and source it from ~/.zshrc.
# Safe to re-run (updates the script, keeps profiles and bindings).
set -e
home=$HOME/.many-claude
src=${0:A:h}/mclaude.zsh
rc=$HOME/.zshrc
marker='# many-claude'
line='[[ -r ~/.many-claude/mclaude.zsh ]] && source ~/.many-claude/mclaude.zsh'

[[ -r $src ]] || { print -u2 "mclaude.zsh not found next to install.sh"; exit 1 }

mkdir -p $home/profiles
chmod 700 $home $home/profiles
cp $src $home/mclaude.zsh
touch $home/projects.conf

# Clean up earlier layouts: ~/.config/claude-switch and the old "ccp" command name.
rm -f $home/ccp.zsh
if [[ -f $rc ]]; then
  sed -i '' -e '/^# Per-project Claude Code accounts$/d' -e '/claude-switch\/ccp\.zsh/d' -e '/\.many-claude\/ccp\.zsh/d' $rc
fi
[[ -L $HOME/.config/claude-switch/ccp.zsh ]] && rm $HOME/.config/claude-switch/ccp.zsh
rmdir $HOME/.config/claude-switch 2>/dev/null || true

if ! grep -qF "$line" $rc 2>/dev/null; then
  grep -qxF "$marker" $rc 2>/dev/null || print "\n$marker" >> $rc
  print "$line" >> $rc
fi

print "many-claude installed in $home"
print "next: source ~/.zshrc && mclaude list"
