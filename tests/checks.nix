# Pure regression tests, wired as the flake's `checks` output.
# Run with: nix flake check
{ pkgs, framework }:

let
  inherit (pkgs) lib;

  mkW = framework.lib.mkWorkspaceShell { inherit pkgs; common = { packages = [ ]; }; };
  base = { name = "t"; zdotdir = ../templates/workspace/example; greeting = "greeting"; };

  # Forcing any attribute of the result triggers the reserved-key guard.
  throwsOn = key:
    !(builtins.tryEval (builtins.seq (mkW (base // { env = { ${key} = "x"; }; })).name true)).success;

  reserved = [ "packages" "shellHook" "NIX_SHELL_NAME" "NIX_WS_FRAMEWORK_HOOKS" ];

  plain = mkW (base // { env = { TEST_VAR = "yes"; }; });

  apiOk =
    lib.all (k: lib.assertMsg (throwsOn k) "env.${k} must be rejected by the reserved-key guard") reserved
    && lib.assertMsg (plain.TEST_VAR == "yes")
      "plain env vars must pass through to the shell"
    && lib.assertMsg (plain.NIX_SHELL_NAME == "t")
      "NIX_SHELL_NAME must equal the project name"
    && lib.assertMsg (lib.hasSuffix "hooks.zsh" plain.NIX_WS_FRAMEWORK_HOOKS)
      "NIX_WS_FRAMEWORK_HOOKS must point at the canonical hooks.zsh"
    && lib.assertMsg (builtins.tryEval (builtins.seq (mkW base).name true)).success
      "the minimal call (defaulted packages/env/versionChecks) must evaluate";

  # Greeting and label are hostile on purpose: quotes and $(...) must
  # render literally, never execute (issue #2).
  bannerShell = mkW (base // {
    name = "banner";
    greeting = ''🚀 Test "Environment" Loaded. $(echo injected)'';
    versionChecks = [{ label = "Zsh's:    "; command = "echo 5.9"; }];
  });
  versionsBin = lib.findFirst (p: lib.getName p == "versions")
    (throw "versions script missing from the shell's packages")
    bannerShell.nativeBuildInputs;
in
{
  # Eval-level tests of the stable mkWorkspaceShell API; the assert fails
  # the check at eval time, before anything builds.
  api-contract = assert apiOk; pkgs.runCommand "api-contract" { } ''
    echo "eval-level API assertions passed" > $out
  '';

  # hooks.zsh behavior in headless zsh with a mocked direnv: prompt marker
  # (both theme branches, no accumulation), extras once per session, and
  # the drift alert.
  hooks-zsh-logic = pkgs.runCommand "hooks-zsh-logic"
    {
      nativeBuildInputs = [ pkgs.zsh ];
      CANONICAL = ../hooks.zsh;
    } ''
    mkdir mock
    printf '#!/bin/sh\nexit 0\n' > mock/direnv
    chmod +x mock/direnv
    PATH=$PWD/mock:$PATH zsh -f ${./hooks-logic.zsh}
    touch $out
  '';

  # SPIKE (#18): bash and fish ports of the hooks logic, same semantics.
  hooks-bash-logic = pkgs.runCommand "hooks-bash-logic"
    {
      nativeBuildInputs = [ pkgs.bash ];
      CANONICAL = ../hooks.bash;
    } ''
    mkdir mock
    printf '#!/bin/sh\nexit 0\n' > mock/direnv
    chmod +x mock/direnv
    NOMOCK_PATH=$PATH PATH=$PWD/mock:$PATH bash ${./hooks-bash-logic.sh}
    touch $out
  '';

  hooks-fish-logic = pkgs.runCommand "hooks-fish-logic"
    {
      nativeBuildInputs = [ pkgs.fish ];
      CANONICAL = ../hooks.fish;
    } ''
    mkdir mock
    printf '#!/bin/sh\nexit 0\n' > mock/direnv
    chmod +x mock/direnv
    HOME=$TMPDIR PATH=$PWD/mock:$PATH fish ${./hooks-fish-logic.fish}
    touch $out
  '';

  # The generated `versions` script renders the greeting and version lines.
  banner-render = pkgs.runCommand "banner-render" { } ''
    out_text=$(${versionsBin}/bin/versions)
    printf '%s\n' "$out_text"
    printf '%s\n' "$out_text" | grep -F '🚀 Test "Environment" Loaded. $(echo injected)'
    printf '%s\n' "$out_text" | grep -F "Zsh's:" | grep -F "5.9"
    if printf '%s\n' "$out_text" | grep -x ".*injected"; then
      echo "greeting command substitution executed" >&2; exit 1
    fi
    touch $out
  '';

  zsh-syntax = pkgs.runCommand "zsh-syntax" { nativeBuildInputs = [ pkgs.zsh ]; } ''
    zsh -n ${../hooks.zsh}
    zsh -n ${../templates/workspace/example/.zshrc}
    touch $out
  '';
}
