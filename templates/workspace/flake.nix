{
  description = "Per-project development environments (private workspace)";

  inputs = {
    # Pin to a specific rev for reproducibility (nix flake update to bump).
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    framework.url = "github:midden-lab/nix-workspace-framework";
  };

  outputs = { self, nixpkgs, framework }:
    let
      systems = [ "aarch64-darwin" "x86_64-darwin" "aarch64-linux" "x86_64-linux" ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system:
        f (import nixpkgs { inherit system; config.allowUnfree = true; }));
    in
    {
      devShells = forAllSystems (pkgs:
        let
          common = import ./common.nix { inherit pkgs; };
          mkWorkspaceShell = framework.lib.mkWorkspaceShell { inherit pkgs common; };
          project = path: import path { inherit pkgs mkWorkspaceShell; };
        in
        {
          # One devShell per project directory. Attr names may not
          # contain dots (directory my.project → attr my-project).
          example = project ./example/shell.nix;
        });
    };
}
