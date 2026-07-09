# SPIKE (#18): regression tests for hooks.fish, mirroring hooks-logic.zsh.
# Run by the hooks-fish-logic check in fish, which provides:
#   CANONICAL — store path of the canonical hooks.fish
#   PATH      — includes a mock `direnv` that emits no hook code

function fail
    echo "FAIL: $argv[1]" >&2
    exit 1
end

set ws $TMPDIR/ws
set proja $TMPDIR/proja
set projb $TMPDIR/projb
set projc $TMPDIR/projc
mkdir -p $ws $proja $projb $projc
cp $CANONICAL $ws/hooks.fish
chmod u+w $ws/hooks.fish
printf 'if set -q _extras_count\n  set -g _extras_count (math $_extras_count + 1)\nelse\n  set -g _extras_count 1\nend\nset -g _owner A\n' > $proja/a.fish
printf 'set -g _owner B\n' > $projb/b.fish
printf 'set -g _extras_c 1\n' > $projc/c.fish

source $ws/hooks.fish
test "$NIX_WORKSPACE_ROOT" = (path resolve $ws); or fail "self-location: got $NIX_WORKSPACE_ROOT"

# --- prompt marker: prefix when NIX_SHELL_NAME set, absent otherwise ---
set -gx NIX_SHELL_NAME proj
set out (fish_prompt | string join '')
string match -q "*$_nix_marker_char proj*" -- $out; or fail "marker missing: got '$out'"
set -gx NIX_SHELL_NAME ''
set out (fish_prompt | string join '')
string match -q "*$_nix_marker_char*" -- $out; and fail "marker present without NIX_SHELL_NAME: got '$out'"

# --- extras: no-op without WS_ZSH_DIR ---
set -gx WS_ZSH_DIR ''
_direnv_ws_extras; or fail "no-op call failed without WS_ZSH_DIR"
set -q _extras_count; and fail "extras loaded without WS_ZSH_DIR"

# --- extras: sourced on entry, stable, re-sourced on edit ---
set -gx NIX_WS_FRAMEWORK_HOOKS $CANONICAL
set -gx WS_ZSH_DIR $proja
_direnv_ws_extras 2> $TMPDIR/err1
test "$_extras_count" = 1; or fail "extras not sourced (count=$_extras_count)"
_direnv_ws_extras 2>> $TMPDIR/err1
test "$_extras_count" = 1; or fail "extras re-sourced without change (count=$_extras_count)"

command touch -d '2000-01-01 00:00:00' $proja/a.fish; or fail "GNU touch required"
_direnv_ws_extras 2>> $TMPDIR/err1
test "$_extras_count" = 2; or fail "extras not re-sourced after file change (count=$_extras_count)"

# --- extras: re-entry after leaving ---
set -gx WS_ZSH_DIR ''
_direnv_ws_extras
set -gx WS_ZSH_DIR $proja
_direnv_ws_extras 2>> $TMPDIR/err1
test "$_extras_count" = 3; or fail "extras not re-sourced on re-entry (count=$_extras_count)"

# --- extras: A→B→A ---
test "$_owner" = A; or fail "owner after A: got '$_owner'"
set -gx WS_ZSH_DIR $projb
_direnv_ws_extras 2>> $TMPDIR/err1
test "$_owner" = B; or fail "owner after A→B: got '$_owner'"
set -gx WS_ZSH_DIR $proja
_direnv_ws_extras 2>> $TMPDIR/err1
test "$_owner" = A; or fail "owner after A→B→A: got '$_owner'"
test "$_extras_count" = 4; or fail "A extras not re-sourced on A→B→A (count=$_extras_count)"

# --- banner/drift silent while hooks identical ---
test -s $TMPDIR/err1; and fail "unexpected warning on identical hooks: $(cat $TMPDIR/err1)"

# --- drift alert: warns once for a fresh workspace after a local edit ---
echo '# local edit' >> $ws/hooks.fish
set -gx WS_ZSH_DIR $projc
_direnv_ws_extras 2> $TMPDIR/err2
test "$_extras_c" = 1; or fail "extras not sourced for third workspace"
grep -q "differs from the pinned framework" $TMPDIR/err2; or fail "drift warning missing after local edit (stderr: $(cat $TMPDIR/err2))"
_direnv_ws_extras 2> $TMPDIR/err3
test -s $TMPDIR/err3; and fail "drift warning repeated within a session"

# --- missing direnv: sourcing must warn, not die ---
set fishbin (command -v fish)
set out (env PATH=/nonexistent $fishbin -c "source $CANONICAL" 2>&1 | string join ' ')
string match -q "*direnv not on PATH*" -- $out; or fail "missing-direnv warning absent: got '$out'"
string match -q "*command not found*" -- $out; and fail "raw command-not-found leaked: $out"

echo "hooks-fish-logic: all tests passed"
