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
  reservedKeys = [ "packages" "shellHook" "NIX_SHELL_NAME" "NIX_WS_FRAMEWORK_HOOKS" ];
  clashes = builtins.filter (k: env ? ${k}) reservedKeys;

  versions = pkgs.writeShellScriptBin "versions" ''
    echo "${greeting}"
    echo "--------------------------------------------------------"
    echo "🤖 Tool Versions:"
    ${lib.concatMapStrings
      (c: "echo \"  ${c.label} $(${c.command})\"\n")
      versionChecks}
    echo "--------------------------------------------------------"
  '';
in

lib.throwIf (clashes != [ ])
  "mkWorkspaceShell (${name}): `env` may not override reserved keys: ${lib.concatStringsSep ", " clashes}"

(pkgs.mkShell ({
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
} // env))
