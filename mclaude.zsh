# mclaude: per-project Claude Code accounts (zsh). Command: mclaude.
# Source from ~/.zshrc. Picks CLAUDE_CONFIG_DIR from $PWD via a map file kept
# outside every project, so nothing is written into project folders.

: ${MCLAUDE_HOME:=$HOME/.mclaude}                # tool home: script + map file
: ${MCLAUDE_PROFILES:=$MCLAUDE_HOME/profiles}            # one config dir per account
: ${MCLAUDE_BASE:=$HOME/.claude}                     # "default" profile, shared config source
MCLAUDE_MAP="$MCLAUDE_HOME/projects.conf"

# Items symlinked from $MCLAUDE_BASE into every profile (shared config).
# Credentials, .claude.json, projects/ (memory), history stay per profile.
MCLAUDE_SHARED=(settings.json CLAUDE.md RTK.md keybindings.json skills plugins hooks agents commands output-styles statusline.sh)

# Print profile bound to a path (longest matching prefix), or "default".
_mclaude_resolve() {
  emulate -L zsh; setopt extendedglob
  local dir=${${1:-$PWD}:A} best="" best_len=0 line prefix profile
  [[ -r $MCLAUDE_MAP ]] || { print default; return }
  # Line format: "<path> <profile>"; profile is the last word, so paths may contain spaces.
  while IFS= read -r line; do
    [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
    profile=${line##*[[:space:]]}; prefix=${line%[[:space:]]*}
    prefix=${prefix%%[[:space:]]#}; prefix=${prefix/#\~/$HOME}; prefix=${prefix%/}
    if [[ $dir == $prefix || $dir == $prefix/* ]] && (( ${#prefix} > best_len )); then
      best=$profile; best_len=${#prefix}
    fi
  done < $MCLAUDE_MAP
  print ${best:-default}
}

# Print config dir for a profile ("" means default ~/.claude).
_mclaude_dir() {
  [[ $1 == default ]] && return
  print "$MCLAUDE_PROFILES/$1"
}

_mclaude_link_shared() {
  emulate -L zsh
  local dir=$1 item
  for item in $MCLAUDE_SHARED; do
    [[ -e $MCLAUDE_BASE/$item && ! -e $dir/$item && ! -L $dir/$item ]] || continue
    ln -s "$MCLAUDE_BASE/$item" "$dir/$item"
  done
}

# Drop the map line whose path equals $1 (path = line minus its last word).
_mclaude_unmap() {
  emulate -L zsh
  [[ -f $MCLAUDE_MAP ]] || return 0
  local tmp=$(mktemp)
  awk -v p="$1" '{ l = $0; sub(/[ \t]+[^ \t]+[ \t]*$/, "", l); sub(/\/$/, "", l) } l != p' $MCLAUDE_MAP > $tmp && mv $tmp $MCLAUDE_MAP
}

_mclaude_exists() {
  [[ $1 == default || -d $MCLAUDE_PROFILES/$1 ]] && return
  print -u2 "mclaude: profile '$1' not found (mclaude add $1)"
  return 1
}

# Wrapper: run Claude Code with the profile bound to $PWD.
claude() {
  emulate -L zsh   # ignore user shell options (nounset, sh_word_split, ...)
  local profile dir
  if [[ -n ${CLAUDE_CONFIG_DIR:-} ]]; then
    command claude "$@"; return   # explicit override wins
  fi
  profile=$(_mclaude_resolve)
  _mclaude_exists $profile || return 1
  dir=$(_mclaude_dir $profile)
  if [[ -n $dir ]]; then
    _mclaude_link_shared $dir
    CLAUDE_CONFIG_DIR=$dir command claude "$@"
  else
    command claude "$@"
  fi
}

_mclaude_usage() {
  print "usage: mclaude [which|list|add <p>|login [p]|logout [p]|status [p]|bind <p> [path]|unbind [path]|help]"
}

mclaude() {
  emulate -L zsh
  local cmd=$1; shift 2>/dev/null
  case $cmd in
    add)
      [[ -n $1 && $1 != default && $1 != */* ]] || { print -u2 "usage: mclaude add <profile>"; return 1 }
      mkdir -p "$MCLAUDE_PROFILES/$1" && chmod 700 "$MCLAUDE_PROFILES/$1"
      _mclaude_link_shared "$MCLAUDE_PROFILES/$1"
      print "created $MCLAUDE_PROFILES/$1 - next: mclaude login $1" ;;
    login|logout|status)
      local p=${1:-$(_mclaude_resolve)}
      _mclaude_exists $p || return 1
      if [[ $p == default ]]; then command claude auth $cmd
      else CLAUDE_CONFIG_DIR=$(_mclaude_dir $p) command claude auth $cmd; fi ;;
    bind)
      [[ -n $1 ]] || { print -u2 "usage: mclaude bind <profile> [path]"; return 1 }
      _mclaude_exists $1 || return 1
      local target=${2:-$PWD}; target=${target:A}
      mkdir -p $MCLAUDE_HOME
      _mclaude_unmap $target
      print "$target $1" >> $MCLAUDE_MAP
      print "bound $target -> $1" ;;
    unbind)
      local target=${1:-$PWD}; target=${target:A}
      _mclaude_unmap $target
      print "unbound $target" ;;
    which|"")
      local p=$(_mclaude_resolve)
      print "$p ${$(_mclaude_dir $p):-$MCLAUDE_BASE}" ;;
    list)
      local d p
      print "profiles:"
      print "  default ($MCLAUDE_BASE)"
      for d in $MCLAUDE_PROFILES/*(N/); do print "  ${d:t}"; done
      print "bindings ($MCLAUDE_MAP):"
      if [[ -f $MCLAUDE_MAP ]]; then sed 's/^/  /' $MCLAUDE_MAP; fi ;;
    help|-h|--help)
      _mclaude_usage ;;
    *)
      _mclaude_usage >&2; return 1 ;;
  esac
}
