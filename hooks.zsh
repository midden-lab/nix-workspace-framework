# Workspace zsh hooks — source this from ~/.zshrc:
#   source ~/path/to/your-workspace/hooks.zsh
#
# Canonical copy: nix-workspace-framework/hooks.zsh. Workspace repos hold
# byte-identical generated copies — refresh with `nix run .#sync-hooks`,
# never hand-edit a workspace copy.
#
# Initializes direnv and adds hooks for the Nix prompt marker, workspace
# extras sourcing, and the once-per-session version banner.

# Workspace root, derived from this file's own location, so the repo
# path is defined in exactly one place (the source line in ~/.zshrc).
export NIX_WORKSPACE_ROOT="${${(%):-%N}:A:h}"

autoload -Uz add-zsh-hook

# --- direnv ---
# Registered before our precmd hook so WS_ZSH_DIR is already exported
# when _direnv_ws_extras runs. Guarded: a missing direnv usually means
# the Nix PATH loader vanished from shell init (macOS updates restore
# the stock /etc/zshrc), and a raw command-not-found here is cryptic.
if (( $+commands[direnv] )); then
  eval "$(direnv hook zsh)"
else
  print -ru2 -- "hooks.zsh: direnv not on PATH — workspace environments will not activate. Is the Nix loader in your shell init? (macOS updates can remove it from /etc/zshrc)"
fi

# Nix prompt marker, shown when a Nix env is active. Themes whose PROMPT
# contains %c (e.g. robbyrussell) get "nix-shell ❄ " inserted before the
# directory name; themes without %c (e.g. agnoster, powerline styles) get
# a "❄ <name>" marker prepended instead. Saves the base prompt once so it
# never accumulates on repeated renders.
#
# The snowflake carries VS15 (U+FE0E, text presentation): some terminals
# (e.g. Ghostty) otherwise render bare U+2744 emoji-wide while zsh counts
# it as one column, and the width mismatch breaks the prompt line on
# redraw.
_nix_marker_char=$'❄︎'
_nix_base_prompt=""
_nix_direnv_prompt() {
  if [[ -z "$_nix_base_prompt" ]]; then
    _nix_base_prompt="$PROMPT"
  fi
  if [[ -n "$NIX_SHELL_NAME" ]]; then
    if [[ "$_nix_base_prompt" == *%c* ]]; then
      PROMPT="${_nix_base_prompt/\%c/nix-shell ${_nix_marker_char} %c}"
    else
      PROMPT="%B%F{cyan}${_nix_marker_char} ${NIX_SHELL_NAME}%f%b ${_nix_base_prompt}"
    fi
  else
    PROMPT="$_nix_base_prompt"
  fi
}
add-zsh-hook precmd _nix_direnv_prompt

# Source workspace extras (aliases, functions) and print the version
# banner, once per session per workspace. precmd rather than chpwd so it
# also fires when a terminal opens directly inside a project directory.
# direnv can only export env vars, so aliases/functions need this
# side-channel keyed on WS_ZSH_DIR.
typeset -gA _ws_extras_loaded
_direnv_ws_extras() {
  [[ -n "$WS_ZSH_DIR" && -d "$WS_ZSH_DIR" ]] || return 0
  [[ -n "${_ws_extras_loaded[$WS_ZSH_DIR]}" ]] && return 0
  _ws_extras_loaded[$WS_ZSH_DIR]=1
  local f
  for f in "$WS_ZSH_DIR"/*.zsh(N); do
    source "$f"
  done
  (( $+commands[versions] )) && versions

  # Drift alert: the devShell exports the store path of the framework's
  # canonical hooks.zsh at the locked rev (NIX_WS_FRAMEWORK_HOOKS); warn
  # once per session when this workspace's copy differs.
  if [[ -n "$NIX_WS_FRAMEWORK_HOOKS" && -r "$NIX_WS_FRAMEWORK_HOOKS" \
        && -r "$NIX_WORKSPACE_ROOT/hooks.zsh" ]] \
     && ! cmp -s "$NIX_WS_FRAMEWORK_HOOKS" "$NIX_WORKSPACE_ROOT/hooks.zsh"; then
    print -ru2 -- "hooks.zsh differs from the pinned framework — run: nix run $NIX_WORKSPACE_ROOT#sync-hooks"
  fi
}
add-zsh-hook precmd _direnv_ws_extras
