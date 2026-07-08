# ZDOTDIR entrypoint for the manual `nix develop` fallback path.
# When shell.nix execs into zsh with ZDOTDIR pointing here, this file
# loads instead of ~/.zshrc. It re-sources the user's global config and
# loads workspace extras.
#
# With direnv, this file is never used — direnv injects the Nix env
# directly into the user's existing zsh session.

# --- Load the user's global config ---
_ws_zdotdir="$ZDOTDIR"
ZDOTDIR="$HOME"
[[ -f "$HOME/.zshenv" ]] && source "$HOME/.zshenv"
[[ -f "$HOME/.zshrc" ]]  && source "$HOME/.zshrc"
ZDOTDIR="$_ws_zdotdir"
unset _ws_zdotdir

# --- Load workspace extras (aliases, functions) ---
[[ -f "${ZDOTDIR}/extras.zsh" ]] && source "${ZDOTDIR}/extras.zsh"

# Prompt marker comes from hooks.zsh (_nix_direnv_prompt) — NIX_SHELL_NAME
# is set by the devShell, so no static marker here.
