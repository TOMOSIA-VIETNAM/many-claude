#!/bin/zsh
# Test suite for mclaude. No dependencies.
#   zsh tests/test.zsh            run all tests
#   zsh tests/test.zsh <glob>     run tests whose name matches, e.g. "*unbind*"
# Every test runs in a subshell with a throwaway HOME and a fake `claude` binary,
# so the real ~/.claude, ~/.mclaude and ~/.zshrc are never touched.

emulate -L zsh
setopt no_unset pipe_fail

ROOT=${0:A:h:h}
TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/mclaude-test.XXXXXX")
trap 'rm -rf $TMP_ROOT' EXIT

typeset -i PASS=0 FAIL=0
typeset -a FAILED

# --- helpers -----------------------------------------------------------------

# Fresh sandbox: fake HOME with a default profile, fake claude on PATH.
setup() {
  T=$(mktemp -d "$TMP_ROOT/case.XXXXXX")
  T=${T:A}
  export HOME=$T/home
  mkdir -p $HOME/.claude/skills $T/bin $T/proj
  print '{}' > $HOME/.claude/settings.json
  print '# shared' > $HOME/.claude/CLAUDE.md
  : > $HOME/.zshrc
  # Fake claude: reports which config dir and args it received.
  # "auth status --json" prints <config dir>/fake-auth.json (see sign_in), else logged out.
  print -r -- '#!/bin/sh
echo "CFG=${CLAUDE_CONFIG_DIR:-<default>} ARGS=$*" >> "$FAKE_LOG"
if [ "$*" = "auth status --json" ]; then
  f="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/fake-auth.json"
  if [ -f "$f" ]; then cat "$f"; exit 0; fi
  echo "{\"loggedIn\": false, \"authMethod\": \"none\"}"; exit 1
fi
echo "CFG=${CLAUDE_CONFIG_DIR:-<default>} ARGS=$*"' > $T/bin/claude
  chmod +x $T/bin/claude
  export FAKE_LOG=$T/claude.log
  export PATH=$T/bin:/usr/bin:/bin:/usr/sbin:/sbin
  unset CLAUDE_CONFIG_DIR MCLAUDE_HOME MCLAUDE_PROFILES MCLAUDE_BASE MCLAUDE_FORCE 2>/dev/null
  source $ROOT/mclaude.zsh
}

# Abort the current test (each test runs in its own subshell).
fail() { print -u2 "    $*"; exit 1 }

assert_eq() {  # expected actual [message]
  [[ $1 == $2 ]] || fail "${3:-assert_eq}: expected [$1], got [$2]"
}

assert_contains() {  # haystack needle [message]
  [[ $1 == *$2* ]] || fail "${3:-assert_contains}: [$2] not in [$1]"
}

assert_not_contains() {
  [[ $1 != *$2* ]] || fail "${3:-assert_not_contains}: [$2] found in [$1]"
}

# Make the fake claude report a profile as signed in: sign_in <config dir> [email].
sign_in() {
  if [[ -n ${2:-} ]]; then
    print -r -- "{\"loggedIn\": true, \"authMethod\": \"claude.ai\", \"email\": \"$2\"}" > $1/fake-auth.json
  else
    print -r -- '{"loggedIn": true, "authMethod": "apiKey"}' > $1/fake-auth.json
  fi
}

profile_at() { ( cd $1 && mclaude which ) | awk '{print $1}' }

run_test() {
  local name=$1
  if ( setup && $name ) 2>$TMP_ROOT/err; then
    PASS+=1; print "  ok   ${name#test_}"
  else
    FAIL+=1; FAILED+=$name; print "  FAIL ${name#test_}"; sed 's/^/  /' $TMP_ROOT/err
  fi
}

# --- resolve / wrapper -------------------------------------------------------

test_unbound_dir_uses_default() {
  assert_eq default "$(profile_at $T/proj)" &&
  assert_eq "CFG=<default> ARGS=" "$(cd $T/proj && claude)"
}

test_bound_dir_sets_config_dir() {
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  assert_eq work "$(profile_at $T/proj)" &&
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=-p hi there" "$(cd $T/proj && claude -p hi there)"
}

test_subdir_inherits_parent() {
  mkdir -p $T/proj/a/b
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  assert_eq work "$(profile_at $T/proj/a/b)"
}

test_longest_prefix_wins() {
  mkdir -p $T/proj/legacy/web
  mclaude add a >/dev/null; mclaude add b >/dev/null
  # longer path bound first: order in the map must not matter
  mclaude bind b $T/proj/legacy >/dev/null; mclaude bind a $T/proj >/dev/null
  assert_eq a "$(profile_at $T/proj)" &&
  assert_eq b "$(profile_at $T/proj/legacy/web)"
}

test_sibling_prefix_does_not_match() {
  mkdir -p $T/proj2
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  assert_eq default "$(profile_at $T/proj2)" "proj must not match proj2"
}

test_path_with_spaces() {
  mkdir -p "$T/my proj/x"
  mclaude add work >/dev/null && mclaude bind work "$T/my proj" >/dev/null || return 1
  assert_eq work "$(profile_at "$T/my proj/x")"
}

test_symlinked_dir_resolves() {
  ln -s $T/proj $T/link
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  assert_eq work "$(profile_at $T/link)"
}

test_map_comments_tilde_and_trailing_slash() {
  mkdir -p $HOME/code/app
  mclaude add work >/dev/null
  print -l '# comment line' '' '~/code/   work' > $HOME/.mclaude/projects.conf
  assert_eq work "$(profile_at $HOME/code/app)"
}

test_explicit_config_dir_overrides_map() {
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  assert_eq "CFG=/custom ARGS=" "$(cd $T/proj && CLAUDE_CONFIG_DIR=/custom claude)"
}

test_missing_profile_errors_and_skips_claude() {
  mkdir -p $HOME/.mclaude && print "$T/proj ghost" > $HOME/.mclaude/projects.conf
  local err
  err=$(cd $T/proj && claude 2>&1) && fail "claude should fail for missing profile"
  assert_contains "$err" "profile 'ghost' not found" &&
  [[ ! -s $FAKE_LOG ]] || fail "real claude must not run"
}

test_custom_locations_via_env() {
  export MCLAUDE_HOME=$T/alt MCLAUDE_PROFILES=$T/alt-profiles
  source $ROOT/mclaude.zsh
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null || return 1
  [[ -f $T/alt/projects.conf && -d $T/alt-profiles/work ]] || fail "custom paths not used"
  assert_eq "CFG=$T/alt-profiles/work ARGS=" "$(cd $T/proj && claude)"
}

# --- add / shared config -----------------------------------------------------

test_add_creates_private_dir_with_shared_links() {
  mclaude add work >/dev/null || return 1
  local d=$HOME/.mclaude/profiles/work
  assert_eq 700 "$(stat -f %Lp $d)" "profile dir mode" &&
  assert_eq $HOME/.claude/settings.json "$(readlink $d/settings.json)" &&
  assert_eq $HOME/.claude/CLAUDE.md "$(readlink $d/CLAUDE.md)" &&
  assert_eq $HOME/.claude/skills "$(readlink $d/skills)" &&
  [[ ! -e $d/plugins && ! -L $d/plugins ]] || fail "missing source must not be linked"
}

test_add_rejects_bad_names() {
  mclaude add 2>/dev/null && return 1
  mclaude add default 2>/dev/null && return 1
  mclaude add a/b 2>/dev/null && return 1
  [[ ! -e $HOME/.mclaude/profiles/a ]]
}

test_existing_profile_file_not_overwritten() {
  mclaude add work >/dev/null
  local d=$HOME/.mclaude/profiles/work
  rm $d/settings.json && print '{"own":1}' > $d/settings.json
  mclaude bind work $T/proj >/dev/null; (cd $T/proj && claude >/dev/null)
  [[ ! -L $d/settings.json ]] && assert_eq '{"own":1}' "$(<$d/settings.json)"
}

test_wrapper_links_items_added_later() {
  mclaude add work >/dev/null && mclaude bind work $T/proj >/dev/null
  print '{}' > $HOME/.claude/keybindings.json
  (cd $T/proj && claude >/dev/null)
  assert_eq $HOME/.claude/keybindings.json "$(readlink $HOME/.mclaude/profiles/work/keybindings.json)"
}

# --- bind / unbind / list ----------------------------------------------------

test_bind_defaults_to_pwd_and_rebind_replaces() {
  mclaude add a >/dev/null; mclaude add b >/dev/null
  (cd $T/proj && mclaude bind a >/dev/null && mclaude bind b >/dev/null)
  assert_eq "$T/proj b" "$(<$HOME/.mclaude/projects.conf)"
}

test_rebind_path_with_spaces_replaces() {
  mkdir -p "$T/my proj"
  mclaude add a >/dev/null; mclaude add b >/dev/null
  mclaude bind a "$T/my proj" >/dev/null; mclaude bind b "$T/my proj" >/dev/null
  assert_eq "$T/my proj b" "$(<$HOME/.mclaude/projects.conf)"
}

test_bind_unknown_profile_fails() {
  mclaude bind ghost $T/proj 2>/dev/null && return 1
  [[ ! -s $HOME/.mclaude/projects.conf ]]
}

test_unbind_removes_only_target() {
  mkdir -p $T/other
  mclaude add a >/dev/null
  mclaude bind a $T/proj >/dev/null; mclaude bind a $T/other >/dev/null
  mclaude unbind $T/proj >/dev/null
  assert_eq "$T/other a" "$(<$HOME/.mclaude/projects.conf)" &&
  assert_eq default "$(profile_at $T/proj)"
}

test_unbind_path_with_spaces() {
  mkdir -p "$T/my proj"
  mclaude add a >/dev/null; mclaude bind a "$T/my proj" >/dev/null
  mclaude unbind "$T/my proj" >/dev/null
  assert_eq "" "$(<$HOME/.mclaude/projects.conf)"
}

test_list_shows_profiles_and_bindings() {
  mclaude add work >/dev/null; mclaude bind work $T/proj >/dev/null
  local out=$(mclaude list)
  assert_contains "$out" "($HOME/.claude)" &&
  assert_contains "$out" "  work" &&
  assert_contains "$out" "$T/proj work"
}

test_list_shows_account_per_profile() {
  mclaude add work >/dev/null; mclaude add api >/dev/null; mclaude add client-long >/dev/null
  sign_in $HOME/.claude me@home.dev
  sign_in $HOME/.mclaude/profiles/work me@work.dev
  sign_in $HOME/.mclaude/profiles/api
  local out=$(mclaude list)
  assert_contains "$out" "  default      me@home.dev  ($HOME/.claude)" &&
  assert_contains "$out" "  work         me@work.dev" &&
  assert_contains "$out" "  api          signed in (apiKey)" &&
  assert_contains "$out" "  client-long  not signed in"
}

# --- remove ------------------------------------------------------------------

test_remove_yes_logs_out_deletes_and_unbinds() {
  mkdir -p $T/other
  mclaude add work >/dev/null; mclaude add keep >/dev/null
  mclaude bind work $T/proj >/dev/null; mclaude bind keep $T/other >/dev/null
  print "# note" >> $HOME/.mclaude/projects.conf
  mclaude bind work "$T/my proj" >/dev/null
  local out=$(mclaude remove -y work) || fail "remove -y must succeed"
  assert_eq "removed work" "$out" &&
  [[ ! -e $HOME/.mclaude/profiles/work && -d $HOME/.mclaude/profiles/keep ]] || fail "wrong profile deleted"
  assert_contains "$(<$FAKE_LOG)" "CFG=$HOME/.mclaude/profiles/work ARGS=auth logout" &&
  assert_eq "$T/other keep
# note" "$(<$HOME/.mclaude/projects.conf)" &&
  assert_eq default "$(profile_at $T/proj)"
}

test_remove_flag_after_name() {
  mclaude add work >/dev/null
  mclaude remove work --yes >/dev/null || fail "flag after name must work"
  [[ ! -e $HOME/.mclaude/profiles/work ]]
}

test_remove_without_tty_or_yes_keeps_profile() {
  mclaude add work >/dev/null
  print y | mclaude remove work >/dev/null 2>&1 && fail "must not delete without confirmation"
  [[ -d $HOME/.mclaude/profiles/work ]] || fail "profile deleted"
  [[ ! -s $FAKE_LOG ]] || fail "must not log out"
}

test_remove_confirmed_on_tty() {
  mclaude add work >/dev/null
  (sleep 1; print y) | script -q /dev/null zsh -c "source $ROOT/mclaude.zsh; mclaude remove work" >/dev/null || return 1
  [[ ! -e $HOME/.mclaude/profiles/work ]] || fail "profile kept"
}

test_remove_answer_n_on_tty_keeps_profile() {
  mclaude add work >/dev/null
  (sleep 1; print n) | script -q /dev/null zsh -c "source $ROOT/mclaude.zsh; mclaude remove work" >/dev/null
  [[ -d $HOME/.mclaude/profiles/work ]] || fail "profile deleted"
}

test_remove_rejects_bad_args() {
  local err
  err=$(mclaude remove 2>&1) && fail "no name must fail"
  assert_contains "$err" "usage: mclaude remove" || return 1
  mclaude remove -y default 2>/dev/null && fail "default must be refused"
  mclaude remove -y ../x 2>/dev/null && fail "path must be refused"
  mclaude add a >/dev/null; mclaude add b >/dev/null
  mclaude remove -y a b 2>/dev/null && fail "two names must be refused"
  mclaude remove -y ghost 2>/dev/null && fail "unknown profile must fail"
  [[ -d $HOME/.mclaude/profiles/a && -d $HOME/.mclaude/profiles/b && -d $HOME/.claude ]] || fail "something deleted"
  [[ ! -s $FAKE_LOG ]] || fail "must not log out"
}

# --- version / doctor --------------------------------------------------------

test_version() {
  local v=$(sed -n 's/^MCLAUDE_VERSION=//p' $ROOT/mclaude.zsh)
  [[ $v == <->.<->.<-> ]] || fail "bad version [$v]"
  assert_eq "mclaude $v" "$(mclaude version)" &&
  assert_eq "mclaude $v" "$(mclaude --version)" &&
  assert_contains "$(<$ROOT/CHANGELOG.md)" "## [$v]" "CHANGELOG has an entry for the version"
}

test_doctor_clean_setup() {
  $ROOT/install.sh >/dev/null; source $HOME/.mclaude/mclaude.zsh
  mclaude add work >/dev/null; mclaude bind work $T/proj >/dev/null
  sign_in $HOME/.claude me@home.dev; sign_in $HOME/.mclaude/profiles/work me@work.dev
  local out
  out=$(mclaude doctor) || fail "doctor must pass: $out"
  assert_contains "$out" "ok    claude: $T/bin/claude" &&
  assert_contains "$out" "ok    work: me@work.dev" &&
  assert_contains "$out" "no problems found"
}

test_doctor_reports_problems() {
  mclaude add work >/dev/null; mclaude add twin >/dev/null
  sign_in $HOME/.claude me@home.dev
  sign_in $HOME/.mclaude/profiles/twin me@home.dev
  ln -s $T/nowhere $HOME/.mclaude/profiles/work/agents
  print "$T/gone work\n$T/proj ghost" > $HOME/.mclaude/projects.conf
  local out
  out=$(mclaude doctor) && fail "doctor must fail on a broken binding"
  assert_contains "$out" "does not load mclaude" &&
  assert_contains "$out" "work: not signed in" &&
  assert_contains "$out" "work: broken symlink agents" &&
  assert_contains "$out" "twin: same account as default" &&
  assert_contains "$out" "binding $T/gone -> work: folder does not exist" &&
  assert_contains "$out" "FAIL  binding $T/proj -> ghost: profile not found" &&
  assert_contains "$out" "1 problem(s), 5 warning(s)"
}

test_doctor_without_claude_binary() {
  PATH=/usr/bin:/bin
  local out
  out=$(mclaude doctor) && fail "must fail without claude"
  assert_contains "$out" "FAIL  claude: Claude Code is not on PATH"
}

# --- completion --------------------------------------------------------------

# Run the completion function for a command line, with compsys helpers stubbed to
# print what they would offer: complete_line mclaude bind ""
complete_line() {
  (
    _describe() { print -r -- "describe ${(P)${@[-1]}}" }
    compadd() { [[ $1 == -a ]] && { print -r -- "compadd ${(P)2}"; return }; [[ $1 == -- ]] && shift; print -r -- "compadd $*" }
    _arguments() { print -r -- "arguments $*" }
    _message() { print -r -- "message $*" }
    _directories() { print directories }
    _alternative() { print -r -- "alternative $*"; local a; for a; do eval "${a#*:*:}"; done }
    local -a words=("$@"); local -i CURRENT=$#
    setopt extendedglob
    source $ROOT/completions/_mclaude
  )
}

test_completion_offers_commands_profiles_and_paths() {
  mclaude add work >/dev/null; mclaude add client-x >/dev/null
  mkdir -p "$T/my proj"
  mclaude bind work $T/proj >/dev/null; mclaude bind client-x "$T/my proj" >/dev/null
  local out
  out=$(complete_line mclaude "")
  assert_contains "$out" "doctor:check the setup" &&
  assert_contains "$out" "remove:sign out and delete" &&
  assert_contains "$out" "version:print" || return 1
  assert_eq "compadd default client-x work" "$(complete_line mclaude bind "")" &&
  assert_eq directories "$(complete_line mclaude bind work "")" &&
  assert_eq "compadd default client-x work" "$(complete_line mclaude status "")" &&
  assert_contains "$(complete_line mclaude remove "")" "1:profile:(client-x work)" &&
  assert_eq "message new profile name" "$(complete_line mclaude add "")" || return 1
  out=$(complete_line mclaude unbind "")
  assert_contains "$out" "compadd $T/proj $T/my proj" &&
  assert_contains "$out" directories
}

test_completion_registers_before_and_after_compinit() {
  $ROOT/install.sh >/dev/null
  local r
  r=$(HOME=$HOME zsh -fc 'autoload -Uz compinit; compinit -u -D; source ~/.mclaude/mclaude.zsh; print $_comps[mclaude]')
  assert_eq _mclaude "$r" "compinit first" || return 1
  r=$(HOME=$HOME zsh -fc 'source ~/.mclaude/mclaude.zsh; autoload -Uz compinit; compinit -u -D; print $_comps[mclaude]')
  assert_eq _mclaude "$r" "compinit after"
}


# --- login / logout / status pass the right config dir -----------------------

test_auth_commands_use_profile_dir() {
  mclaude add work >/dev/null; mclaude bind work $T/proj >/dev/null
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=auth login" "$(mclaude login work)" &&
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=auth status" "$(cd $T/proj && mclaude status)" &&
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=auth logout" "$(mclaude logout work)" &&
  assert_eq "CFG=<default> ARGS=auth status" "$(mclaude status default)"
}

test_auth_unknown_profile_fails() {
  mclaude login ghost 2>/dev/null && return 1
  [[ ! -s $FAKE_LOG ]]
}

test_auth_without_arg_uses_bound_profile() {
  mclaude add work >/dev/null; mclaude bind work $T/proj >/dev/null
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=auth login" "$(cd $T/proj && mclaude login)" &&
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=auth logout" "$(cd $T/proj && mclaude logout)" &&
  assert_eq "CFG=<default> ARGS=auth login" "$(cd $T/proj && mclaude login default)" &&
  assert_eq "CFG=<default> ARGS=auth logout" "$(cd $T && mclaude logout)"
}

# --- which / help / misc -----------------------------------------------------

test_which_prints_profile_and_dir() {
  mclaude add work >/dev/null; mclaude bind work $T/proj >/dev/null
  assert_eq "work $HOME/.mclaude/profiles/work" "$(cd $T/proj && mclaude which)" &&
  assert_eq "work $HOME/.mclaude/profiles/work" "$(cd $T/proj && mclaude)" "bare mclaude = which" &&
  assert_eq "default $HOME/.claude" "$(cd $T && mclaude which)"
}

test_help_and_unknown_command() {
  local out err
  out=$(mclaude help) || fail "help must exit 0"
  assert_contains "$out" "usage: mclaude" || return 1
  out=$(mclaude bogus 2>$T/err) && fail "unknown command must exit non-zero"
  assert_eq "" "$out" "usage goes to stderr" &&
  assert_contains "$(<$T/err)" "usage: mclaude"
}

test_list_without_map_succeeds() {
  local out
  out=$(mclaude list) || fail "list must exit 0 without a map file"
  assert_contains "$out" "default  not signed in  ($HOME/.claude)"
}

test_add_existing_profile_is_safe() {
  mclaude add work >/dev/null
  print 'secret' > $HOME/.mclaude/profiles/work/.claude.json
  mclaude add work >/dev/null || fail "re-add must succeed"
  assert_eq secret "$(<$HOME/.mclaude/profiles/work/.claude.json)"
}

test_dangling_symlink_in_profile_not_replaced() {
  mclaude add work >/dev/null
  local d=$HOME/.mclaude/profiles/work
  rm $d/CLAUDE.md && ln -s $T/nowhere $d/CLAUDE.md
  local err=$(mclaude add work 2>&1 >/dev/null)
  assert_eq "" "$err" "no error output" &&
  assert_eq $T/nowhere "$(readlink $d/CLAUDE.md)"
}

test_bind_requires_profile_arg() {
  local err
  err=$(mclaude bind 2>&1) && fail "bind without args must fail"
  assert_contains "$err" "usage: mclaude bind"
}

test_unbind_defaults_to_pwd_and_tolerates_missing_map() {
  (cd $T/proj && mclaude unbind >/dev/null) || fail "unbind without map must succeed"
  mclaude add a >/dev/null; mclaude bind a $T/proj >/dev/null
  (cd $T/proj && mclaude unbind >/dev/null)
  assert_eq "" "$(<$HOME/.mclaude/projects.conf)"
}

test_user_shell_options_do_not_break_functions() {
  setopt no_unset sh_word_split ksh_arrays
  mkdir -p "$T/a b"
  mclaude add work >/dev/null && mclaude bind work "$T/a b" >/dev/null || return 1
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=x" "$(cd "$T/a b" && claude x)" &&
  assert_contains "$(mclaude list)" "  work"
}

# --- install / uninstall -----------------------------------------------------

test_install_without_zshrc_creates_it() {
  rm $HOME/.zshrc
  $ROOT/install.sh >/dev/null || return 1
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)"
}

test_install_marker_without_hook_adds_hook_once() {
  print '# mclaude' > $HOME/.zshrc
  $ROOT/install.sh >/dev/null || return 1
  assert_eq 1 "$(grep -cx '# mclaude' $HOME/.zshrc)" "marker count" &&
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)" "hook count"
}

test_install_fails_without_script() {
  mkdir -p $T/repo && cp $ROOT/install.sh $T/repo/
  local err
  err=$($T/repo/install.sh 2>&1) && fail "install must fail without mclaude.zsh"
  assert_contains "$err" "not found next to install.sh" &&
  [[ ! -e $HOME/.mclaude ]] || fail "nothing should be created"
}

test_uninstall_without_zshrc() {
  $ROOT/install.sh >/dev/null; rm $HOME/.zshrc
  $ROOT/uninstall.sh >/dev/null || return 1
  [[ ! -e $HOME/.mclaude && ! -e $HOME/.zshrc ]] || fail "unexpected files"
}

test_uninstall_confirmed_deletes_profiles() {
  $ROOT/install.sh >/dev/null; mkdir -p $HOME/.mclaude/profiles/work
  # read -q needs a terminal: run under a pseudo-tty and answer "y".
  (sleep 1; print y) | script -q /dev/null $ROOT/uninstall.sh >/dev/null || return 1
  [[ ! -e $HOME/.mclaude ]] || fail "home dir left"
  assert_contains "$(<$FAKE_LOG)" "CFG=$HOME/.mclaude/profiles/work ARGS=auth logout"
}

test_uninstall_answer_n_on_tty_keeps_profiles() {
  $ROOT/install.sh >/dev/null; mkdir -p $HOME/.mclaude/profiles/work
  (sleep 1; print n) | script -q /dev/null $ROOT/uninstall.sh >/dev/null || return 1
  [[ -d $HOME/.mclaude/profiles/work ]] || fail "profile deleted"
  [[ ! -s $FAKE_LOG ]] || fail "must not log out"
}

zshrc_hook='[[ -r ~/.mclaude/mclaude.zsh ]] && source ~/.mclaude/mclaude.zsh'

test_install_copies_completion() {
  $ROOT/install.sh >/dev/null || return 1
  cmp -s $ROOT/completions/_mclaude $HOME/.mclaude/completions/_mclaude || fail "completion not copied"
  mkdir -p $HOME/.mclaude/profiles/work
  print n | $ROOT/uninstall.sh >/dev/null 2>&1
  [[ ! -e $HOME/.mclaude/completions ]] || fail "completion left after uninstall"
}

test_install_and_uninstall_mark_steps_done() {
  local out
  out=$($ROOT/install.sh) || return 1
  assert_contains "$out" "✓ Added mclaude hook to $HOME/.zshrc" &&
  assert_contains "$out" "✓ mclaude installed in $HOME/.mclaude" || return 1
  [[ $out != *$'\e['* ]] || fail "no color codes when stdout is not a terminal"
  out=$($ROOT/uninstall.sh --purge) || return 1
  assert_contains "$out" "✓ Removed mclaude hook from $HOME/.zshrc" &&
  assert_contains "$out" "✓ mclaude uninstalled"
}

test_install_fresh() {
  $ROOT/install.sh >/dev/null || return 1
  [[ -f $HOME/.mclaude/mclaude.zsh && ! -L $HOME/.mclaude/mclaude.zsh ]] || fail "script not copied"
  [[ -d $HOME/.mclaude/profiles && -f $HOME/.mclaude/projects.conf ]] || fail "layout missing"
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)" "hook line count"
}

test_install_is_idempotent_and_keeps_data() {
  $ROOT/install.sh >/dev/null
  zsh -c "source ~/.mclaude/mclaude.zsh; mclaude add work; mclaude bind work $T/proj" >/dev/null
  $ROOT/install.sh >/dev/null || return 1
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)" "hook line count" &&
  assert_eq 1 "$(grep -cx '# mclaude' $HOME/.zshrc)" "marker count" &&
  assert_eq "$T/proj work" "$(<$HOME/.mclaude/projects.conf)" &&
  [[ -d $HOME/.mclaude/profiles/work ]]
}

test_install_migrates_old_layouts() {
  mkdir -p $HOME/.config/claude-switch $HOME/.mclaude
  ln -s /nowhere $HOME/.config/claude-switch/ccp.zsh
  print old > $HOME/.mclaude/ccp.zsh
  print -l 'export KEEP=1' '# Per-project Claude Code accounts' \
    '[[ -r ~/.config/claude-switch/ccp.zsh ]] && source ~/.config/claude-switch/ccp.zsh' > $HOME/.zshrc
  $ROOT/install.sh >/dev/null || return 1
  local rc=$(<$HOME/.zshrc)
  assert_not_contains "$rc" "ccp.zsh" &&
  assert_contains "$rc" "export KEEP=1" &&
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)" &&
  [[ ! -e $HOME/.config/claude-switch && ! -e $HOME/.mclaude/ccp.zsh ]] || fail "old files left"
}

test_installed_hook_works_in_new_shell() {
  $ROOT/install.sh >/dev/null
  mkdir -p $HOME/.mclaude/profiles/work
  print "$T/proj work" > $HOME/.mclaude/projects.conf
  assert_eq "CFG=$HOME/.mclaude/profiles/work ARGS=" "$(cd $T/proj && HOME=$HOME zsh -c 'source ~/.zshrc; claude')"
}

test_uninstall_without_profiles_removes_all() {
  print 'export KEEP=1' > $HOME/.zshrc
  $ROOT/install.sh >/dev/null && $ROOT/uninstall.sh >/dev/null || return 1
  [[ ! -e $HOME/.mclaude ]] || fail "home dir left"
  assert_not_contains "$(<$HOME/.zshrc)" "mclaude" &&
  assert_contains "$(<$HOME/.zshrc)" "export KEEP=1" &&
  [[ -f $HOME/.claude/settings.json ]] || fail "default profile touched"
}

test_uninstall_declined_keeps_profiles() {
  $ROOT/install.sh >/dev/null; mkdir -p $HOME/.mclaude/profiles/work
  print n | $ROOT/uninstall.sh >/dev/null 2>&1 || return 1
  [[ -d $HOME/.mclaude/profiles/work ]] || fail "profile deleted"
  [[ ! -e $HOME/.mclaude/mclaude.zsh && ! -e $HOME/.mclaude/projects.conf ]] || fail "script left"
  assert_not_contains "$(<$HOME/.zshrc)" "mclaude.zsh"
}

test_uninstall_purge_logs_out_and_deletes() {
  $ROOT/install.sh >/dev/null; mkdir -p $HOME/.mclaude/profiles/{a,b}
  $ROOT/uninstall.sh --purge >/dev/null || return 1
  [[ ! -e $HOME/.mclaude ]] || fail "home dir left"
  assert_contains "$(<$FAKE_LOG)" "CFG=$HOME/.mclaude/profiles/a ARGS=auth logout" &&
  assert_contains "$(<$FAKE_LOG)" "CFG=$HOME/.mclaude/profiles/b ARGS=auth logout" &&
  [[ -f $HOME/.claude/settings.json ]] || fail "default profile touched"
}

# --- run ---------------------------------------------------------------------

print "mclaude tests"
for t in ${(ok)functions[(I)test_*]}; do
  [[ -n ${1:-} && ${t#test_} != $~1 ]] && continue
  run_test $t
done
print "\n$PASS passed, $FAIL failed"
(( FAIL == 0 ))
