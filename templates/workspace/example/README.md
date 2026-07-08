# example

Project-specific environment configuration for the example workspace.
Copy this directory to start a new project, then:

1. Rename it and update `name`, `greeting`, `packages`, and `versionChecks` in `shell.nix`
2. Update the flake attr in `envrc` (`use flake "$NIX_WORKSPACE_ROOT#<attr>"`) and `WS_ZSH_DIR`
3. Register the devShell in the workspace `flake.nix`
4. `git add` everything (flakes only see tracked files)
5. In the actual project repo: `echo 'source_env ~/path/to/workspace/<project>/envrc' > .envrc && direnv allow`

See the workspace README and the framework repo for the full architecture.
