# SPIKE (#18): regression tests for hooks.bash, mirroring hooks-logic.zsh.
# Run by the hooks-bash-logic check in plain bash, which provides:
#   CANONICAL — store path of the canonical hooks.bash
#   PATH      — includes a mock `direnv` that emits no hook code

fail() { echo "FAIL: $1" >&2; exit 1; }

ws=$TMPDIR/ws proja=$TMPDIR/proja projb=$TMPDIR/projb projc=$TMPDIR/projc
mkdir -p "$ws" "$proja" "$projb" "$projc"
cp "$CANONICAL" "$ws/hooks.bash"
chmod u+w "$ws/hooks.bash"
echo '_extras_count=$(( ${_extras_count:-0} + 1 )); _owner=A' > "$proja/a.bash"
echo '_owner=B' > "$projb/b.bash"
echo '_extras_c=1' > "$projc/c.bash"

source "$ws/hooks.bash"
[ "$NIX_WORKSPACE_ROOT" = "$(cd "$ws" && pwd -P)" ] || fail "self-location: got $NIX_WORKSPACE_ROOT"

# --- prompt marker: prepend, no accumulation, restore ---
PS1='base > '
_nix_base_ps1=""
NIX_SHELL_NAME=proj
_nix_ws_prompt
case "$PS1" in
  *"${_nix_marker_char} proj"*"base > ") ;;
  *) fail "marker prepend: got '$PS1'" ;;
esac
first_ps1="$PS1"
_nix_ws_prompt
[ "$PS1" = "$first_ps1" ] || fail "marker accumulated: got '$PS1'"
NIX_SHELL_NAME=""
_nix_ws_prompt
[ "$PS1" = 'base > ' ] || fail "base PS1 not restored: got '$PS1'"

# --- extras: no-op without WS_ZSH_DIR ---
WS_ZSH_DIR=""
_direnv_ws_extras || fail "no-op call failed without WS_ZSH_DIR"
[ "${_extras_count:-0}" = 0 ] || fail "extras loaded without WS_ZSH_DIR"

# --- extras: sourced on entry, stable, re-sourced on edit ---
export NIX_WS_FRAMEWORK_HOOKS=$CANONICAL
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2> "$TMPDIR/err1"
[ "$_extras_count" = 1 ] || fail "extras not sourced (count=$_extras_count)"
_direnv_ws_extras 2>> "$TMPDIR/err1"
[ "$_extras_count" = 1 ] || fail "extras re-sourced without change (count=$_extras_count)"

touch -d '2000-01-01 00:00:00' "$proja/a.bash" || fail "GNU touch required"
_direnv_ws_extras 2>> "$TMPDIR/err1"
[ "$_extras_count" = 2 ] || fail "extras not re-sourced after file change (count=$_extras_count)"

# --- extras: re-entry after leaving ---
WS_ZSH_DIR=""
_direnv_ws_extras
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2>> "$TMPDIR/err1"
[ "$_extras_count" = 3 ] || fail "extras not re-sourced on re-entry (count=$_extras_count)"

# --- extras: A→B→A ---
[ "$_owner" = A ] || fail "owner after A: got '$_owner'"
export WS_ZSH_DIR=$projb
_direnv_ws_extras 2>> "$TMPDIR/err1"
[ "$_owner" = B ] || fail "owner after A→B: got '$_owner'"
export WS_ZSH_DIR=$proja
_direnv_ws_extras 2>> "$TMPDIR/err1"
[ "$_owner" = A ] || fail "owner after A→B→A: got '$_owner'"
[ "$_extras_count" = 4 ] || fail "A extras not re-sourced on A→B→A (count=$_extras_count)"

# --- banner/drift silent while hooks identical ---
[ ! -s "$TMPDIR/err1" ] || fail "unexpected warning on identical hooks: $(cat "$TMPDIR/err1")"

# --- drift alert: warns once for a fresh workspace after a local edit ---
echo '# local edit' >> "$ws/hooks.bash"
export WS_ZSH_DIR=$projc
_direnv_ws_extras 2> "$TMPDIR/err2"
[ "${_extras_c:-0}" = 1 ] || fail "extras not sourced for third workspace"
grep -q "differs from the pinned framework" "$TMPDIR/err2" \
  || fail "drift warning missing after local edit (stderr: $(cat "$TMPDIR/err2"))"
_direnv_ws_extras 2> "$TMPDIR/err3"
[ ! -s "$TMPDIR/err3" ] || fail "drift warning repeated within a session"

# --- missing direnv: sourcing must warn, not die ---
# NOMOCK_PATH (from the check) has coreutils but no direnv — the
# realistic broken state.
bashbin=$(command -v bash)
out=$(PATH=$NOMOCK_PATH "$bashbin" -c "source $CANONICAL" 2>&1)
rc=$?
[ "$rc" = 0 ] || fail "sourcing without direnv exited $rc: $out"
case "$out" in
  *"direnv not on PATH"*) ;;
  *) fail "missing-direnv warning absent: got '$out'" ;;
esac
case "$out" in
  *"command not found"*) fail "raw command-not-found leaked: $out" ;;
esac

echo "hooks-bash-logic: all tests passed"
