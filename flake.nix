{
  description = "Per-project Nix dev environments with direnv + zsh integration";

  outputs = { self }: {
    # The workspace shell builder. Called from a consumer flake as:
    #   mkWorkspaceShell = framework.lib.mkWorkspaceShell { inherit pkgs common; };
    #   mkWorkspaceShell { name = ...; zdotdir = ./.; ... }
    lib.mkWorkspaceShell = import ./lib/mk-workspace-shell.nix;

    templates.workspace = {
      path = ./templates/workspace;
      description = "Private workspace repo consuming this framework (one example project)";
    };
    templates.default = self.templates.workspace;
  };
}
