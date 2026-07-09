# SPIKE (#18): bash port of the workspace shell hooks — source from ~/.bashrc:
#   source ~/path/to/your-workspace/hooks.bash
#
# Mirrors hooks.zsh semantics: direnv init (guarded), prompt marker,
# extras re-sourced on entry and file change, banner and drift alert once
# per session per workspace. Written for bash 3.2 (macOS default): no
# associative arrays, no $'\u...' escapes.
#
# Known deltas vs zsh (spike findings, see issue #18):
# - Marker always prepends to PS1 (no %c-style insertion point in bash themes)
# - Extras glob is *.bash (owner's shell per the single-shell scope)
# - Drift alert expects NIX_WS_FRAMEWORK_HOOKS to point at the bash
#   canonical — the current lib exports the zsh file, so a per-shell
#   export (or a canonical directory) is a required API change
# - PROMPT_COMMAND additions clobber $? for PS1 exit-status displays

# Pure-builtin self-location (no dirname): must work even when PATH is
# broken, since the direnv guard below is the diagnostic for that case.
case "${BASH_SOURCE[0]}" in
  */*) export NIX_WORKSPACE_ROOT="$(cd "${BASH_SOURCE[0]%/*}" && pwd -P)" ;;
  *)   export NIX_WORKSPACE_ROOT="$PWD" ;;
esac

if command -v direnv >/dev/null 2>&1; then
  eval "$(direnv hook bash)"
else
  echo "hooks.bash: direnv not on PATH — workspace environments will not activate. Is the Nix loader in your shell init? (macOS updates can remove it from /etc/zshrc)" >&2
fi

_nix_marker_char='❄︎'
_nix_base_ps1=""
_nix_ws_prompt() {
  if [ -z "$_nix_base_ps1" ]; then
    _nix_base_ps1="$PS1"
  fi
  if [ -n "$NIX_SHELL_NAME" ]; then
    PS1="\[\e[1;36m\]${_nix_marker_char} ${NIX_SHELL_NAME}\[\e[0m\] ${_nix_base_ps1}"
  else
    PS1="$_nix_base_ps1"
  fi
}

_ws_extras_dir=""
_ws_extras_sig=""
_ws_banner_shown="|"

_ws_stat() {  # GNU then BSD stat
  stat -c '%Y:%s' -- "$1" 2>/dev/null || stat -f '%m:%z' -- "$1" 2>/dev/null
}

_ws_extras_signature() {
  local f out=""
  for f in "$1"/*.bash; do
    [ -e "$f" ] || continue
    out="$out$f:$(_ws_stat "$f");"
  done
  printf '%s' "$out"
}

_direnv_ws_extras() {
  if [ -z "$WS_ZSH_DIR" ] || [ ! -d "$WS_ZSH_DIR" ]; then
    _ws_extras_dir=""   # left the project: next entry re-sources
    return 0
  fi
  local sig f
  sig="$(_ws_extras_signature "$WS_ZSH_DIR")"
  if [ "$WS_ZSH_DIR" != "$_ws_extras_dir" ] || [ "$sig" != "$_ws_extras_sig" ]; then
    _ws_extras_dir="$WS_ZSH_DIR"
    _ws_extras_sig="$sig"
    for f in "$WS_ZSH_DIR"/*.bash; do
      [ -e "$f" ] && source "$f"
    done
  fi
  case "$_ws_banner_shown" in
    *"|$WS_ZSH_DIR|"*) return 0 ;;
  esac
  _ws_banner_shown="${_ws_banner_shown}${WS_ZSH_DIR}|"
  command -v versions >/dev/null 2>&1 && versions
  if [ -n "$NIX_WS_FRAMEWORK_HOOKS" ] && [ -r "$NIX_WS_FRAMEWORK_HOOKS" ] \
     && [ -r "$NIX_WORKSPACE_ROOT/hooks.bash" ] \
     && ! cmp -s "$NIX_WS_FRAMEWORK_HOOKS" "$NIX_WORKSPACE_ROOT/hooks.bash"; then
    echo "hooks.bash differs from the pinned framework — run: nix run $NIX_WORKSPACE_ROOT#sync-hooks" >&2
  fi
  return 0
}

PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_nix_ws_prompt; _direnv_ws_extras"
