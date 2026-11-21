# mclaude: per-project Claude Code accounts (zsh). Command: mclaude.
# Source from ~/.zshrc. Picks CLAUDE_CONFIG_DIR from $PWD via a map file kept
# outside every project, so nothing is written into project folders.

MCLAUDE_VERSION=0.1.0

: ${MCLAUDE_HOME:=$HOME/.mclaude}                # tool home: script + map file
: ${MCLAUDE_PROFILES:=$MCLAUDE_HOME/profiles}            # one config dir per account
: ${MCLAUDE_BASE:=$HOME/.claude}                     # "default" profile, shared config source
MCLAUDE_MAP="$MCLAUDE_HOME/projects.conf"

# Items symlinked from $MCLAUDE_BASE into every profile (shared config).
# Credentials, .claude.json, projects/ (memory), history stay per profile.
MCLAUDE_SHARED=(settings.json CLAUDE.md keybindings.json skills plugins hooks agents commands output-styles statusline.sh)

# Read the map into $reply as alternating path, profile (~ expanded, no trailing /).
# Line format: "<path> <profile>"; profile is the last word, so paths may contain spaces.
_mclaude_bindings() {
  emulate -L zsh; setopt extendedglob
  local line prefix
  reply=()
  [[ -r $MCLAUDE_MAP ]] || return 0
  while IFS= read -r line; do
    [[ -z ${line//[[:space:]]/} || $line == \#* ]] && continue
    prefix=${line%[[:space:]]*}; prefix=${prefix%%[[:space:]]#}
    prefix=${prefix/#\~/$HOME}; prefix=${prefix%/}
    reply+=("$prefix" "${line##*[[:space:]]}")
  done < $MCLAUDE_MAP
}

# Print profile bound to a path (longest matching prefix), or "default".
_mclaude_resolve() {
  emulate -L zsh
  local dir=${${1:-$PWD}:A} best="" prefix profile
  local -i best_len=0
  local -a reply
  _mclaude_bindings
  for prefix profile in "${reply[@]}"; do
    if [[ $dir == $prefix || $dir == $prefix/* ]] && (( ${#prefix} > best_len )); then
      best=$profile; best_len=${#prefix}
    fi
  done
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

# Drop every map line bound to profile $1 (profile = last word).
_mclaude_unmap_profile() {
  emulate -L zsh
  [[ -f $MCLAUDE_MAP ]] || return 0
  local tmp=$(mktemp)
  awk -v p="$1" 'NF == 0 || $1 ~ /^#/ || $NF != p' $MCLAUDE_MAP > $tmp && mv $tmp $MCLAUDE_MAP
}

# Print the account a profile is signed in to: its email, "signed in (<method>)"
# when there is no email (e.g. API key), or "not signed in".
_mclaude_account() {
  emulate -L zsh
  local dir=$(_mclaude_dir $1) json
  if [[ -n $dir ]]; then
    json=$(CLAUDE_CONFIG_DIR=$dir command claude auth status --json 2>/dev/null)
  else
    json=$(command claude auth status --json 2>/dev/null)
  fi
  if [[ ! $json =~ '"loggedIn": *true' ]]; then
    print "not signed in"
  elif [[ $json =~ '"email": *"([^"]+)"' ]]; then
    print -r -- $match[1]
  elif [[ $json =~ '"authMethod": *"([^"]+)"' ]]; then
    print -r -- "signed in ($match[1])"
  else
    print "signed in"
  fi
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
  print -r -- "usage: mclaude <command> [args]

  which                  profile and config dir for the current directory (default)
  list                   profiles with their signed-in account, and all bindings
  add <profile>          create a profile
  remove [-y] <profile>  sign out and delete a profile and its bindings
  bind <profile> [path]  bind a folder to a profile (default: current directory)
  unbind [path]          remove a folder's binding (default: current directory)
  login|logout|status [profile]
                         run claude auth for a profile (default: current directory's)
  doctor                 check the setup for problems
  version                print the mclaude version
  help                   show this help"
}

# Check the setup; print one line per finding. Returns 1 if anything is broken.
_mclaude_doctor() {
  emulate -L zsh
  local -i errors=0 warnings=0
  local bin prefix profile p dir item acct rc=${ZDOTDIR:-$HOME}/.zshrc
  local -a profiles reply
  local -A owner   # email -> first profile signed in to it

  bin=$(whence -p claude)
  if [[ -n $bin ]]; then
    print "  ok    claude: $bin ($(command claude --version 2>/dev/null))"
  else
    print "  FAIL  claude: Claude Code is not on PATH"; errors+=1
  fi

  if [[ -r $rc ]] && grep -qF 'mclaude/mclaude.zsh' $rc; then
    print "  ok    $rc loads mclaude"
  else
    print "  warn  $rc does not load mclaude (run ./install.sh, or ignore if you source it elsewhere)"; warnings+=1
  fi

  profiles=(default $MCLAUDE_PROFILES/*(N/:t))
  for p in $profiles; do
    dir=$(_mclaude_dir $p)
    if [[ -n $dir ]]; then
      for item in $dir/*(N@) $dir/.*(N@); do
        [[ -e $item ]] && continue
        print "  warn  $p: broken symlink ${item:t} -> $(readlink $item)"; warnings+=1
      done
    fi
    [[ -n $bin ]] || continue
    acct=$(_mclaude_account $p)
    if [[ $acct == "not signed in" ]]; then
      print "  warn  $p: not signed in (mclaude login $p)"; warnings+=1
    elif [[ $acct == *@* && -n ${owner[$acct]:-} ]]; then
      print "  warn  $p: same account as ${owner[$acct]} ($acct)"; warnings+=1
    else
      print "  ok    $p: $acct"
      [[ $acct == *@* ]] && owner[$acct]=$p
    fi
  done

  _mclaude_bindings
  for prefix profile in "${reply[@]}"; do
    if [[ $profile != default && ! -d $MCLAUDE_PROFILES/$profile ]]; then
      print "  FAIL  binding $prefix -> $profile: profile not found (mclaude add $profile, or mclaude unbind $prefix)"; errors+=1
    elif [[ ! -d $prefix ]]; then
      print "  warn  binding $prefix -> $profile: folder does not exist"; warnings+=1
    fi
  done

  if (( errors + warnings )); then
    print "$errors problem(s), $warnings warning(s)"
  else
    print "no problems found"
  fi
  (( errors == 0 ))
}

mclaude() {
  emulate -L zsh
  local cmd=$1; shift 2>/dev/null
  case $cmd in
    version|--version|-v)
      print "mclaude $MCLAUDE_VERSION" ;;
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
    remove)
      local yes=0 name="" arg
      for arg in "$@"; do
        case $arg in
          -y|--yes) yes=1 ;;
          *) [[ -z $name ]] && name=$arg || name=/ ;;   # a second name makes it invalid
        esac
      done
      [[ -n $name && $name != default && $name != */* ]] || { print -u2 "usage: mclaude remove [-y] <profile>"; return 1 }
      _mclaude_exists $name || return 1
      if (( ! yes )); then
        read -q "?Delete profile '$name' (login, memory, history) and its bindings? This cannot be undone. [y/N] " || { print; print "kept $name"; return 1 }
        print
      fi
      local dir=$MCLAUDE_PROFILES/$name
      CLAUDE_CONFIG_DIR=$dir command claude auth logout >/dev/null 2>&1   # clean up stored credentials
      rm -rf -- $dir
      _mclaude_unmap_profile $name
      print "removed $name" ;;
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
    doctor)
      _mclaude_doctor ;;
    list)
      local p acct
      local -a names=(default $MCLAUDE_PROFILES/*(N/:t))
      local -i w=0
      for p in $names; do (( ${#p} > w )) && w=${#p}; done
      print "profiles:"
      for p in $names; do
        acct=$(_mclaude_account $p)
        [[ $p == default ]] && acct+="  ($MCLAUDE_BASE)"
        printf "  %-*s  %s\n" $w $p $acct
      done
      print "bindings ($MCLAUDE_MAP):"
      if [[ -f $MCLAUDE_MAP ]]; then sed 's/^/  /' $MCLAUDE_MAP; fi ;;
    help|-h|--help)
      _mclaude_usage ;;
    *)
      _mclaude_usage >&2; return 1 ;;
  esac
}

# Tab completion: completions/_mclaude, copied next to this script by install.sh.
# Works whether compinit runs before or after this file is sourced.
if [[ -d $MCLAUDE_HOME/completions ]]; then
  fpath=($MCLAUDE_HOME/completions $fpath)
  if (( $+functions[compdef] )); then
    autoload -Uz _mclaude && compdef _mclaude mclaude
  fi
fi
