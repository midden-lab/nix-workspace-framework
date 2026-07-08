# Workspace zsh hooks — source this from ~/.zshrc:
#   source ~/path/to/your-workspace/hooks.zsh
#
# Initializes direnv and adds hooks for the Nix prompt marker, workspace
# extras sourcing, and the once-per-session version banner.

# Workspace root, derived from this file's own location, so the repo
# path is defined in exactly one place (the source line in ~/.zshrc).
export NIX_WORKSPACE_ROOT="${${(%):-%N}:A:h}"

autoload -Uz add-zsh-hook

# --- direnv ---
# Registered before our precmd hook so WS_ZSH_DIR is already exported
# when _direnv_ws_extras runs.
eval "$(direnv hook zsh)"

# Nix prompt marker, shown when a Nix env is active. Themes whose PROMPT
# contains %c (e.g. robbyrussell) get "nix-shell ❄ " inserted before the
# directory name; themes without %c (e.g. agnoster, powerline styles) get
# a "❄ <name>" marker prepended instead. Saves the base prompt once so it
# never accumulates on repeated renders.
_nix_base_prompt=""
_nix_direnv_prompt() {
  if [[ -z "$_nix_base_prompt" ]]; then
    _nix_base_prompt="$PROMPT"
  fi
  if [[ -n "$NIX_SHELL_NAME" ]]; then
    if [[ "$_nix_base_prompt" == *%c* ]]; then
      PROMPT="${_nix_base_prompt/\%c/nix-shell ❄ %c}"
    else
      PROMPT="%B%F{cyan}❄ ${NIX_SHELL_NAME}%f%b ${_nix_base_prompt}"
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
}
add-zsh-hook precmd _direnv_ws_extras
