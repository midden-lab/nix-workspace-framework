# Builds a workspace devShell: shared packages + project packages, a
# generated `versions` banner script, and the dual-mode shellHook.
#
# Called from a consumer flake:
#   mkWorkspaceShell = framework.lib.mkWorkspaceShell { inherit pkgs common; };
#
# Stable API: { name, zdotdir, greeting, packages ? [], env ? {}, versionChecks ? [] }
{ pkgs, common }:

{ name
, zdotdir            # path — the project dir; ZDOTDIR for the manual fallback
, greeting
, packages ? [ ]
, env ? { }          # static env vars (e.g. TF_IN_AUTOMATION)
, versionChecks ? [ ]  # [ { label; command; } ] rendered by `versions`
}:

let
  inherit (pkgs) lib;

  # `env` is for plain env vars only; silently overriding these would
  # break the shell in confusing ways, so fail loudly instead.
  #
  # `env` is passed through to mkDerivation's own `env` argument below,
  # which already throws on collision with any other derivation attr
  # (NIX_SHELL_NAME, shellHook, name, ...) — verified empirically. The one
  # gap: `packages` is mkShell-specific and stripped before mkDerivation
  # ever sees it, so a clash there is invisible to nixpkgs' own check and
  # must stay guarded here. The other three stay too, for one consistent
  # message instead of depending on nixpkgs' internal wording.
  reservedKeys = [ "packages" "shellHook" "NIX_SHELL_NAME" "NIX_WS_FRAMEWORK_HOOKS" ];
  clashes = builtins.filter (k: env ? ${k}) reservedKeys;

  # greeting and labels are data — escape them so quotes and $(...) render
  # literally. Each check's `command` is intentionally code and stays raw.
  versions = pkgs.writeShellScriptBin "versions" ''
    echo ${lib.escapeShellArg greeting}
    echo "--------------------------------------------------------"
    echo "🤖 Tool Versions:"
    ${lib.concatMapStrings
      (c: "echo ${lib.escapeShellArg "  ${c.label}"}\" $(${c.command})\"\n")
      versionChecks}
    echo "--------------------------------------------------------"
  '';
in

lib.throwIf (clashes != [ ])
  "mkWorkspaceShell (${name}): `env` may not override reserved keys: ${lib.concatStringsSep ", " clashes}"

(pkgs.mkShell {
  packages = common.packages ++ packages ++ [ versions ];

  NIX_SHELL_NAME = name;

  # Store path of the framework's canonical hooks.zsh at the locked rev.
  # hooks.zsh compares itself against this for the once-per-session
  # drift alert ("run nix run .#sync-hooks").
  NIX_WS_FRAMEWORK_HOOKS = "${../hooks.zsh}";

  # Two activation paths:
  #   direnv  → DIRENV_IN_ENVRC is set; skip banner and exec. hooks.zsh
  #             runs `versions` once per session instead.
  #   manual  → `nix develop`; show banner, exec into zsh with ZDOTDIR
  #             pointing at the project's config dir (store copy).
  #   Non-interactive `nix develop --command` runs skip banner and exec.
  shellHook = ''
    case "$-" in *i*)
      if [ -z "$DIRENV_IN_ENVRC" ]; then
        versions
        if [ -z "$IN_NIX_ZSH" ]; then
          export IN_NIX_ZSH=1
          export ZDOTDIR=${zdotdir}
          exec ${pkgs.zsh}/bin/zsh
        fi
      fi
    ;; esac
  '';

  # Static user env vars, passed through mkDerivation's own `env`
  # argument (not merged into the top-level attrset) so a name collision
  # with a *future* mkShell/mkDerivation argument throws instead of
  # silently overriding it. Values must be strings/bools/ints/derivations
  # — mkDerivation enforces this too.
  inherit env;
})
