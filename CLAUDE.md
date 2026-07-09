# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

The **public** nix-workspace-framework: a small, reusable framework for per-project Nix dev environments (flakes + direnv + zsh). It ships via `flake.nix`:

- `lib.mkWorkspaceShell` — the devShell builder (`lib/mk-workspace-shell.nix`)
- `lib.mkSyncHooksApp` — builds a consumer's `nix run .#sync-hooks` app, which regenerates the workspace's `hooks.zsh` from `./hooks.zsh` here at the locked rev
- `templates.workspace` — a starter for a consumer's private workspace repo (`templates/workspace/`; it deliberately contains no hooks.zsh — sync-hooks materializes it)
- `hooks.zsh` (repo root) — the canonical zsh integration; the ONLY hand-edited copy anywhere

Consumers pin this repo as a flake input and call `framework.lib.mkWorkspaceShell { inherit pkgs common; }`. README.md is the user-facing documentation — keep its API section in sync with the lib file.

## Hard Constraints

- **The `mkWorkspaceShell` argument set is a published, stable API**: `{ name, zdotdir, greeting, packages ? [], env ? {}, versionChecks ? [] }`. Renaming, removing, or changing the semantics of any argument breaks downstream workspaces pinned to `main`. Additive optional arguments are fine; anything else needs a deliberate versioning decision (tags) first. The same applies to `lib.mkSyncHooksApp` and the exported `NIX_WS_FRAMEWORK_HOOKS` env var (reserved key; hooks.zsh's drift alert depends on it).
- **This repo is public.** Before any commit: no personal identifiers, hostnames, account names, tokens, or employer-specific strings anywhere (including comments and docs). Audit with the maintainer's local pattern list (kept OUT of this repo — listing the patterns here would itself leak them):
  `grep -rinf ~/.config/nix-workspace-framework/leak-patterns.txt . --exclude-dir=.git` → must be empty. If the pattern file is missing, ask the maintainer; do not inline patterns into this file.
- Commits use the repo-local noreply author email (already configured via `git config user.email` in this clone) — don't override it.
- `hooks.zsh` (repo root) is the **canonical** copy of the zsh integration. Consumer workspaces hold byte-identical generated copies (`nix run .#sync-hooks`); the devShell-exported `NIX_WS_FRAMEWORK_HOOKS` path plus a `cmp` in hooks.zsh warns consumers once per session when their copy is stale. Changes propagate only when a consumer updates + re-syncs — keep changes backward-compatible and called out in commit messages. Never reintroduce a hooks.zsh copy under `templates/`.
- Commit message style: plain sentence-style summaries, no conventional-commits prefixes.

## Verifying Changes

`make test` runs both steps below — it is exactly what CI (.github/workflows/test.yml) runs, so green locally means green in Actions.

```bash
# 1. The regression suite (tests/checks.nix) — run for ANY change.
#    Covers: eval-level API contract (reserved-key guard, env passthrough,
#    NIX_SHELL_NAME / NIX_WS_FRAMEWORK_HOOKS), hooks.zsh logic in headless
#    zsh with a mocked direnv (prompt marker both theme branches, extras
#    once-per-session, drift alert), banner rendering, zsh syntax.
nix flake check

# 2. Integration tests (template onboarding, sync-hooks byte-identity,
#    example devShell, direnv end-to-end when direnv is on PATH). Impure —
#    needs a real Nix daemon, so it's a script rather than a check. It
#    rewrites the scaffold's framework input to this clone, so it tests
#    the working tree.
./tests/integration.sh
```

New behavior in lib/ or hooks.zsh should land with a regression test in `tests/`. The flake's `nixpkgs` input exists only for the checks — the library never uses it; keep it that way.

## Architecture Notes

- `mkWorkspaceShell` is two-stage: `{ pkgs, common }` (bound once per consumer flake) then the per-project attrset. `common.packages` + project `packages` + a generated `versions` script (writeShellScriptBin) form the shell; `NIX_SHELL_NAME` is set by the shell itself.
- The shellHook is interactive-only (`case "$-" in *i*)`): direnv capture and `nix develop --command` runs skip banner and exec; interactive manual `nix develop` prints the banner and execs into zsh with `ZDOTDIR = <project dir store copy>`. That store copy is why secrets may never live in a project dir: the Nix store is world-readable on multi-user installs.
- The devShell ↔ hooks.zsh contract: shell provides `NIX_SHELL_NAME` (prompt marker), `versions` (banner), and `NIX_WS_FRAMEWORK_HOOKS` (canonical hooks path for the drift alert); the consumer's envrc exports `WS_ZSH_DIR` (where hooks.zsh finds `*.zsh` extras). Envrc convention: capture `WS_PROJECT_ROOT="$OLDPWD"` first (inside a `source_env`'d file, `$PWD` is the envrc's own dir, not the project).
- The template ships a `CLAUDE.md` for scaffolded workspaces — if conventions change, update it together with the example project and README.

## Releasing Changes to Consumers

Push to `main`; consumers pick changes up explicitly with `nix flake update framework` (their `flake.lock` pins revs, so pushes never break anyone until they update). Release tags are additive and optional.
