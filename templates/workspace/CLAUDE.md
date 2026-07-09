# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A private, per-project dev-environment workspace built on [nix-workspace-framework](https://github.com/midden-lab/nix-workspace-framework) (the `framework` flake input). Each project directory defines one devShell; the actual project repos contain only a one-line `.envrc` shim pointing at `<project>/envrc` here. Environments auto-activate via direnv on `cd`; `hooks.zsh` (sourced from `~/.zshrc`) supplies the prompt marker, alias sourcing, and once-per-session banner.

This repo is typically private — project envrcs often carry env vars you don't want public. Keep it that way.

## Layout

- `flake.nix` — one devShell per project; inputs `nixpkgs` + `framework`, both pinned in `flake.lock`
- `common.nix` — packages shared by every project's shell
- `hooks.zsh` — GENERATED from the framework's canonical copy via `nix run .#sync-hooks`; never hand-edit it (project shells warn once per session when it drifts from the pinned framework)
- `<project>/shell.nix` — declarative call: `{ pkgs, mkWorkspaceShell }: mkWorkspaceShell { name, zdotdir, greeting, packages, env, versionChecks }`
- `<project>/envrc` — direnv logic: `WS_PROJECT_ROOT="$OLDPWD"` capture first, then `use flake "$NIX_WORKSPACE_ROOT#<attr>"`, `WS_ZSH_DIR`, and dynamic exports
- `<project>/extras.zsh` / `profile.zsh` / `.zshrc` — team-shareable aliases / shell functions / manual-fallback entrypoint (all optional)

## Working Rules

- **Flake source = git tree**: `git add` any new or renamed file before `nix develop` or `use flake` can see it — the most common "why doesn't Nix see my file" trap
- After changing a `shell.nix` or `flake.nix`: verify with `nix develop .#<attr> --command versions`, then `direnv reload` inside the project to refresh the nix-direnv cache
- Env var placement: static vars → the `env` argument in shell.nix; dynamic/project-anchored vars → the envrc (anchored to `$WS_PROJECT_ROOT`, e.g. `export KUBECONFIG="$WS_PROJECT_ROOT/.kube/config"`); `NIX_SHELL_NAME` is set by the devShell — never export it from an envrc
- Never hardcode this repo's path in envrc/zsh files — use `$NIX_WORKSPACE_ROOT` (exported by hooks.zsh; envrc files self-locate as a fallback). The only allowed hardcoded paths: the one-line project shims and the `source .../hooks.zsh` line in `~/.zshrc`
- Secrets and personal config (accounts, tokens, hostnames) stay in `$HOME` files, never committed here; `extras.zsh` must be team-shareable. Not just repo hygiene: project dirs are copied into the Nix store (`zdotdir`), which is world-readable on multi-user Nix installs — a secret in a project dir leaks to every local user even if it's never committed
- devShell attr names can't contain dots: directory `my.project` → attr `my-project`
- `extras.zsh`/`profile.zsh` re-source automatically on the next prompt after an edit or on re-entering the project — keep them idempotent (aliases/functions only, no one-shot side effects). Definitions persist after leaving a project (zsh has no unload channel); `exec zsh` resets
- New project: copy `example/` and follow its README; register the devShell in `flake.nix`; `git add` everything

## Updating

- `nix flake update nixpkgs` — bump tool versions; `nix flake update framework` — bump the framework library
- After a framework bump: `nix run .#sync-hooks` to regenerate hooks.zsh, commit it, `exec zsh` to pick it up

## Verification

```bash
nix flake check
nix develop .#<attr> --command versions                      # banner with real versions
nix develop .#<attr> --command sh -c 'echo $NIX_SHELL_NAME'  # attr's project name
direnv exec <project-repo> sh -c 'echo $NIX_SHELL_NAME'      # direnv path end-to-end
```
