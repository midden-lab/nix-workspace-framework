{ pkgs, mkWorkspaceShell }:

mkWorkspaceShell {
  name = "example";
  zdotdir = ./.;
  greeting = "🚀 Example Environment Loaded Successfully.";

  packages = with pkgs; [
    # Project-specific packages go here, e.g.:
    # kubectl
    # opentofu
  ];

  # Static env vars, e.g.:
  # env = { TF_IN_AUTOMATION = "true"; };

  versionChecks = [
    { label = "Python:   "; command = "python3 --version 2>&1 || echo 'not installed'"; }
    { label = "Git:      "; command = "git --version"; }
  ];
}
