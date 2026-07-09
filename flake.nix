{
  description = "Per-project Nix dev environments with direnv + zsh integration";

  # Used only by the `checks` output (the regression tests) — the library
  # itself always takes `pkgs` from the consumer. Consumers who want to
  # avoid a second nixpkgs in their lock can set
  # `inputs.framework.inputs.nixpkgs.follows = "nixpkgs"`.
  inputs.nixpkgs.url = "github:NixOS/nixpkgs/c4013e501c048ae7c4a8940c92837636042bf6c3";

  outputs = { self, nixpkgs }: {
    # The workspace shell builder. Called from a consumer flake as:
    #   mkWorkspaceShell = framework.lib.mkWorkspaceShell { inherit pkgs common; };
    #   mkWorkspaceShell { name = ...; zdotdir = ./.; ... }
    lib.mkWorkspaceShell = import ./lib/mk-workspace-shell.nix;

    # `nix run .#sync-hooks` for consumer workspaces: regenerates the
    # workspace's hooks.zsh from this framework's canonical copy at the
    # locked rev. Wire up in a workspace flake as:
    #   apps = forAllSystems (pkgs: { sync-hooks = framework.lib.mkSyncHooksApp pkgs; });
    lib.mkSyncHooksApp = pkgs: {
      type = "app";
      program = "${pkgs.writeShellScript "sync-hooks" ''
        set -eu
        if [ ! -f flake.nix ]; then
          echo "sync-hooks: run this from the workspace repo root (no flake.nix here)" >&2
          exit 1
        fi
        install -m 644 ${./hooks.zsh} ./hooks.zsh
        echo "hooks.zsh synced from the pinned framework — review and commit it."
      ''}";
    };

    templates.workspace = {
      path = ./templates/workspace;
      description = "Private workspace repo consuming this framework (one example project)";
    };
    templates.default = self.templates.workspace;

    # Regression suite: `nix flake check` (see tests/checks.nix).
    checks = nixpkgs.lib.genAttrs
      [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ]
      (system: import ./tests/checks.nix {
        pkgs = import nixpkgs { inherit system; };
        framework = self;
      });
  };
}
