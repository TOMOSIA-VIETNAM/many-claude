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
  print -r -- '#!/bin/sh
echo "CFG=${CLAUDE_CONFIG_DIR:-<default>} ARGS=$*" >> "$FAKE_LOG"
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
  assert_contains "$out" "default ($HOME/.claude)" &&
  assert_contains "$out" "  work" &&
  assert_contains "$out" "$T/proj work"
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
  assert_contains "$out" "default ($HOME/.claude)"
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
  assert_contains "$err" "mclaude.zsh not found" &&
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
  mkdir -p $HOME/.config/claude-switch $HOME/.many-claude
  ln -s /nowhere $HOME/.config/claude-switch/ccp.zsh
  print old > $HOME/.many-claude/ccp.zsh
  print -l 'export KEEP=1' '# Per-project Claude Code accounts' \
    '[[ -r ~/.config/claude-switch/ccp.zsh ]] && source ~/.config/claude-switch/ccp.zsh' \
    '# many-claude' '[[ -r ~/.many-claude/ccp.zsh ]] && source ~/.many-claude/ccp.zsh' \
    '[[ -r ~/.many-claude/mclaude.zsh ]] && source ~/.many-claude/mclaude.zsh' > $HOME/.zshrc
  $ROOT/install.sh >/dev/null || return 1
  local rc=$(<$HOME/.zshrc)
  assert_not_contains "$rc" "ccp.zsh" &&
  assert_not_contains "$rc" "many-claude" &&
  assert_contains "$rc" "export KEEP=1" &&
  assert_eq 1 "$(grep -cF $zshrc_hook $HOME/.zshrc)" &&
  [[ ! -e $HOME/.config/claude-switch && ! -e $HOME/.mclaude/ccp.zsh ]] || fail "old files left"
}

test_install_moves_many_claude_home() {
  mkdir -p $HOME/.many-claude/profiles/work
  print 'secret' > $HOME/.many-claude/profiles/work/.claude.json
  print "$T/proj work" > $HOME/.many-claude/projects.conf
  $ROOT/install.sh >/dev/null || return 1
  [[ ! -e $HOME/.many-claude ]] || fail "old home left"
  assert_eq secret "$(<$HOME/.mclaude/profiles/work/.claude.json)" &&
  assert_eq "$T/proj work" "$(<$HOME/.mclaude/projects.conf)"
}

test_install_keeps_old_home_when_both_exist() {
  mkdir -p $HOME/.many-claude/profiles/old $HOME/.mclaude/profiles/new
  local err=$($ROOT/install.sh 2>&1 >/dev/null) || fail "install must succeed"
  assert_contains "$err" "both" &&
  [[ -d $HOME/.many-claude/profiles/old && -d $HOME/.mclaude/profiles/new ]] || fail "data touched"
}

test_uninstall_removes_old_many_claude_hook() {
  print -l 'export KEEP=1' '# many-claude' '[[ -r ~/.many-claude/mclaude.zsh ]] && source ~/.many-claude/mclaude.zsh' > $HOME/.zshrc
  $ROOT/uninstall.sh >/dev/null || return 1
  assert_eq "export KEEP=1" "$(<$HOME/.zshrc)"
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
