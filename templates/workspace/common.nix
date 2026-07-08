# Shared packages included in every project's devShell.
# Imported by flake.nix and passed to mkWorkspaceShell as `common`.
{ pkgs }:

{
  packages = with pkgs; [
    git
    jq
    vim
    zsh
  ];
}
