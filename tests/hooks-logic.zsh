# Regression tests for hooks.zsh logic. Run by the hooks-zsh-logic check
# (tests/checks.nix) in headless zsh (`zsh -f`), which provides:
#   CANONICAL — store path of the canonical hooks.zsh
#   PATH      — includes a mock `direnv` that emits no hook code

fail() { print -ru2 -- "FAIL: $1"; exit 1 }

ws=$TMPDIR/ws proja=$TMPDIR/proja projb=$TMPDIR/projb projc=$TMPDIR/projc
mkdir -p $ws $proja $projb $projc
cp $CANONICAL $ws/hooks.zsh
chmod u+w $ws/hooks.zsh
print -r -- '_extras_count=$(( ${_extras_count:-0} + 1 )); _owner=A' > $proja/a.zsh
print -r -- '_owner=B' > $projb/b.zsh
print -r -- '_extras_c=1' > $projc/c.zsh

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

# --- extras: no-op without WS_ZSH_DIR ---
WS_ZSH_DIR=""
_direnv_ws_extras || fail "no-op call failed without WS_ZSH_DIR"
(( ${_extras_count:-0} == 0 )) || fail "extras loaded without WS_ZSH_DIR"

# --- extras: sourced on entry, stable across prompts, re-sourced on edit ---
export NIX_WS_FRAMEWORK_HOOKS=$CANONICAL
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2> $TMPDIR/err1
(( _extras_count == 1 )) || fail "extras not sourced (count=$_extras_count)"
_direnv_ws_extras 2>> $TMPDIR/err1
_direnv_ws_extras 2>> $TMPDIR/err1
(( _extras_count == 1 )) || fail "extras re-sourced without change (count=$_extras_count)"

touch -d '2000-01-01 00:00:00' $proja/a.zsh   # simulate an edit (mtime change)
_direnv_ws_extras 2>> $TMPDIR/err1
(( _extras_count == 2 )) || fail "extras not re-sourced after file change (count=$_extras_count)"

# --- extras: re-sourced on re-entry after leaving ---
WS_ZSH_DIR=""
_direnv_ws_extras
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2>> $TMPDIR/err1
(( _extras_count == 3 )) || fail "extras not re-sourced on re-entry (count=$_extras_count)"

# --- extras: A→B→A — the project you're in is authoritative ---
[[ $_owner == A ]] || fail "owner after A: got '$_owner'"
export WS_ZSH_DIR=$projb
_direnv_ws_extras 2>> $TMPDIR/err1
[[ $_owner == B ]] || fail "owner after A→B: got '$_owner'"
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2>> $TMPDIR/err1
[[ $_owner == A ]] || fail "owner after A→B→A: got '$_owner'"
(( _extras_count == 4 )) || fail "A extras not re-sourced on A→B→A (count=$_extras_count)"

# --- banner: once per session per workspace even though extras repeat ---
# err1 doubles as the banner/drift channel: all calls above used identical
# hooks, so it must be empty (drift silent) — and versions isn't a command
# here, so the banner path is exercised via the guard only.
[[ ! -s $TMPDIR/err1 ]] || fail "unexpected warning on identical hooks: $(<$TMPDIR/err1)"

# --- drift alert: warns once for a fresh workspace after a local edit ---
print -r -- '# local edit' >> $ws/hooks.zsh
export WS_ZSH_DIR=$projc
_direnv_ws_extras 2> $TMPDIR/err2
[[ ${_extras_c:-0} == 1 ]] || fail "extras not sourced for third workspace"
grep -q "differs from the pinned framework" $TMPDIR/err2 \
  || fail "drift warning missing after local edit (stderr: $(<$TMPDIR/err2))"
_direnv_ws_extras 2> $TMPDIR/err3
[[ ! -s $TMPDIR/err3 ]] || fail "drift warning repeated within a session"

# --- missing direnv: sourcing must warn, not die with command-not-found ---
zshbin=${commands[zsh]}
out=$(PATH=/nonexistent $zshbin -f -c "source $CANONICAL" 2>&1)
rc=$?
(( rc == 0 )) || fail "sourcing without direnv exited $rc: $out"
[[ $out == *"direnv not on PATH"* ]] || fail "missing-direnv warning absent: got '$out'"
[[ $out != *"command not found"* ]] || fail "raw command-not-found leaked: $out"

print "hooks-logic: all tests passed"
