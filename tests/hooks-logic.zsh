# Regression tests for hooks.zsh logic. Run by the hooks-zsh-logic check
# (tests/checks.nix) in headless zsh (`zsh -f`), which provides:
#   CANONICAL — store path of the canonical hooks.zsh
#   PATH      — includes a mock `direnv` that emits no hook code

fail() { print -ru2 -- "FAIL: $1"; exit 1 }

ws=$TMPDIR/ws proja=$TMPDIR/proja projb=$TMPDIR/projb
mkdir -p $ws $proja $projb
cp $CANONICAL $ws/hooks.zsh
chmod u+w $ws/hooks.zsh
print -r -- '_extras_count=$(( ${_extras_count:-0} + 1 ))' > $proja/a.zsh
print -r -- '_extras_b=1' > $projb/b.zsh

source $ws/hooks.zsh
[[ $NIX_WORKSPACE_ROOT == ${ws:A} ]] || fail "self-location: got $NIX_WORKSPACE_ROOT"

# --- prompt marker: theme with %c (robbyrussell style) ---
base='%{f%}%c > '
PROMPT=$base
_nix_base_prompt=""
NIX_SHELL_NAME=proj
_nix_direnv_prompt
expected="%{f%}nix-shell ${_nix_marker_char} %c > "
[[ $PROMPT == "$expected" ]] || fail "%c insertion: got '$PROMPT'"
_nix_direnv_prompt
[[ $PROMPT == "$expected" ]] || fail "%c marker accumulated on re-render: got '$PROMPT'"
NIX_SHELL_NAME=""
_nix_direnv_prompt
[[ $PROMPT == "$base" ]] || fail "base prompt not restored: got '$PROMPT'"

# --- prompt marker: theme without %c (agnoster style) ---
base='user@host > '
PROMPT=$base
_nix_base_prompt=""
NIX_SHELL_NAME=proj
_nix_direnv_prompt
prefix="%B%F{cyan}${_nix_marker_char} proj%f%b "
[[ $PROMPT == "$prefix"* ]] || fail "%c-less prepend: got '$PROMPT'"
[[ $PROMPT == "$prefix$base" ]] || fail "%c-less base kept: got '$PROMPT'"
_nix_direnv_prompt
[[ $PROMPT == "$prefix$base" ]] || fail "%c-less marker accumulated: got '$PROMPT'"
NIX_SHELL_NAME=""
_nix_direnv_prompt
[[ $PROMPT == "$base" ]] || fail "%c-less base not restored: got '$PROMPT'"

# --- extras: no-op without WS_ZSH_DIR, once per session per workspace ---
WS_ZSH_DIR=""
_direnv_ws_extras || fail "no-op call failed without WS_ZSH_DIR"
(( ${_extras_count:-0} == 0 )) || fail "extras loaded without WS_ZSH_DIR"

export NIX_WS_FRAMEWORK_HOOKS=$CANONICAL
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2> $TMPDIR/err1
(( _extras_count == 1 )) || fail "extras not sourced (count=$_extras_count)"
_direnv_ws_extras 2>> $TMPDIR/err1
(( _extras_count == 1 )) || fail "extras re-sourced within a session (count=$_extras_count)"

# --- drift alert: silent while identical, warns after a local edit ---
[[ ! -s $TMPDIR/err1 ]] || fail "unexpected warning on identical hooks: $(<$TMPDIR/err1)"
print -r -- '# local edit' >> $ws/hooks.zsh
export WS_ZSH_DIR=$projb
_direnv_ws_extras 2> $TMPDIR/err2
[[ ${_extras_b:-0} == 1 ]] || fail "extras not sourced for second workspace"
grep -q "differs from the pinned framework" $TMPDIR/err2 \
  || fail "drift warning missing after local edit (stderr: $(<$TMPDIR/err2))"

print "hooks-logic: all tests passed"
