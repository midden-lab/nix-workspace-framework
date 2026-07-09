# SPIKE (#18): fish port of the workspace shell hooks — source from
# ~/.config/fish/config.fish:
#   source ~/path/to/your-workspace/hooks.fish
#
# Mirrors hooks.zsh semantics: direnv init (guarded), prompt marker,
# extras re-sourced on entry and file change, banner and drift alert once
# per session per workspace. Requires fish >= 3.5 (`path` builtin).
#
# Known deltas vs zsh (spike findings, see issue #18):
# - Marker wraps fish_prompt (fish has no PROMPT string to edit); themes
#   that redefine fish_prompt after this file loads will drop the marker
# - Extras glob is *.fish (owner's shell per the single-shell scope)
# - Drift alert expects NIX_WS_FRAMEWORK_HOOKS to point at the fish
#   canonical — needs the same per-shell export API change as bash

set -gx NIX_WORKSPACE_ROOT (path resolve (path dirname (status filename)))

if type -q direnv
    direnv hook fish | source
else
    echo "hooks.fish: direnv not on PATH — workspace environments will not activate. Is the Nix loader in your shell init? (macOS updates can remove it from /etc/zshrc)" >&2
end

# --- prompt marker: wrap the current fish_prompt ---
set -g _nix_marker_char '❄︎'
if functions -q fish_prompt
    functions -c fish_prompt _ws_base_fish_prompt
end
function fish_prompt
    if test -n "$NIX_SHELL_NAME"
        set_color -o cyan
        printf '%s %s ' $_nix_marker_char $NIX_SHELL_NAME
        set_color normal
    end
    if functions -q _ws_base_fish_prompt
        _ws_base_fish_prompt
    else
        printf '> '
    end
end

# --- extras + banner + drift, on every prompt ---
set -g _ws_extras_dir ""
set -g _ws_extras_sig ""
set -g _ws_banner_shown

function _ws_stat
    command stat -c '%Y:%s' -- $argv[1] 2>/dev/null
    or command stat -f '%m:%z' -- $argv[1] 2>/dev/null
end

function _ws_extras_signature
    set -l out ""
    for f in $argv[1]/*.fish
        set out "$out$f:"(_ws_stat $f)";"
    end
    echo -n $out
end

function _direnv_ws_extras --on-event fish_prompt
    if test -z "$WS_ZSH_DIR"; or not test -d "$WS_ZSH_DIR"
        set -g _ws_extras_dir ""   # left the project: next entry re-sources
        return 0
    end
    set -l sig (_ws_extras_signature $WS_ZSH_DIR)
    if test "$WS_ZSH_DIR" != "$_ws_extras_dir"; or test "$sig" != "$_ws_extras_sig"
        set -g _ws_extras_dir $WS_ZSH_DIR
        set -g _ws_extras_sig "$sig"
        for f in $WS_ZSH_DIR/*.fish
            source $f
        end
    end
    if contains -- $WS_ZSH_DIR $_ws_banner_shown
        return 0
    end
    set -ga _ws_banner_shown $WS_ZSH_DIR
    type -q versions; and versions
    if test -n "$NIX_WS_FRAMEWORK_HOOKS" -a -r "$NIX_WS_FRAMEWORK_HOOKS" -a -r "$NIX_WORKSPACE_ROOT/hooks.fish"
        if not cmp -s $NIX_WS_FRAMEWORK_HOOKS $NIX_WORKSPACE_ROOT/hooks.fish
            echo "hooks.fish differs from the pinned framework — run: nix run $NIX_WORKSPACE_ROOT#sync-hooks" >&2
        end
    end
end
