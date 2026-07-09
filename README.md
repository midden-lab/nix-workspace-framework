# nix-workspace-framework

[![test](https://github.com/midden-lab/nix-workspace-framework/actions/workflows/test.yml/badge.svg)](https://github.com/midden-lab/nix-workspace-framework/actions/workflows/test.yml)

Declarative, per-project development environments using Nix flakes, direnv, and zsh. Each project gets a reproducible devShell that auto-activates on `cd`, with pinned tool versions, team-shareable aliases, and a clean separation between shared infrastructure, project tooling, and personal settings.

The framework is intentionally small: one Nix function (`mkWorkspaceShell`), one zsh integration file (`hooks.zsh`), and a set of conventions. Your actual environments live in a **private workspace repo** that consumes this framework as a flake input — your project definitions, env vars, and aliases never need to be public.

## Quick start

```bash
# 1. Scaffold your private workspace repo
mkdir ~/workspace/my-workspaces && cd ~/workspace/my-workspaces
nix flake init -t github:midden-lab/nix-workspace-framework#workspace
git init && git add .

# 2. Materialize hooks.zsh from the pinned framework, then commit
nix run .#sync-hooks
git add hooks.zsh && git commit -m "Init workspace repo"

# 3. Wire up zsh (after your oh-my-zsh/prompt setup in ~/.zshrc)
#    source ~/workspace/my-workspaces/hooks.zsh

# 4. Point a project repo at the example environment
cd ~/src/some-project
echo 'source_env ~/workspace/my-workspaces/example/envrc' > .envrc
direnv allow

# 5. cd in — the environment activates, the banner prints once per session
```

Prerequisites: Nix with `experimental-features = nix-command flakes`, [direnv](https://direnv.net) + [nix-direnv](https://github.com/nix-community/nix-direnv) (`~/.config/direnv/direnvrc` sourcing nix-direnv), zsh.

## Architecture

```
this repo (public)
├── flake.nix                      lib.mkWorkspaceShell + lib.mkSyncHooksApp + templates.workspace
├── hooks.zsh                      canonical zsh integration (single hand-edited copy)
├── lib/mk-workspace-shell.nix     the shell builder
└── templates/workspace/           starter for your private workspace repo
                                   (includes a CLAUDE.md so Claude Code can help
                                   you set up and maintain your workspace)

your workspace repo (private)
├── flake.nix                      devShell per project; framework as flake input
├── flake.lock                     pins nixpkgs AND this framework
├── common.nix                     packages shared by all your projects
├── hooks.zsh                      GENERATED from the framework via `nix run .#sync-hooks`
└── <project>/
    ├── shell.nix                  declarative mkWorkspaceShell call
    ├── envrc                      direnv logic (use flake, exports)
    ├── extras.zsh                 team-shareable aliases (optional)
    ├── profile.zsh                shell functions direnv can't deliver (optional)
    ├── .zshrc                     ZDOTDIR entrypoint for manual nix develop (optional)
    └── README.md

your project repos (anywhere)
└── .envrc                         one line: source_env <workspace>/<project>/envrc
```

## How activation works

**direnv path (primary):** `cd` into a project repo → the one-line `.envrc` shim `source_env`s your workspace repo's project envrc → `use flake "$NIX_WORKSPACE_ROOT#<attr>"` loads the devShell (cached by nix-direnv, near-instant after first load) → `hooks.zsh` sources the project's `*.zsh` extras and prints the version banner (once per session per project). Extras re-source whenever you enter a project or edit their files — the project you're in is always authoritative, and edits apply on the next prompt — so they must be idempotent: aliases and function definitions only, no one-shot side effects. Leaving the directory unloads the env; run `versions` anytime to reprint the banner.

**Manual fallback:** `nix develop <workspace>#<attr>` prints the banner and execs into zsh with `ZDOTDIR` pointing at the project's config (which re-sources your global zsh setup and the project extras). Non-interactive runs (`nix develop --command ...`) skip banner and exec entirely.

## Anatomy of a project envrc

Each project's envrc in your workspace repo follows the same five-line skeleton (see `templates/workspace/example/envrc`):

```bash
export WS_PROJECT_ROOT="$OLDPWD"

NIX_WORKSPACE_ROOT="${NIX_WORKSPACE_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export NIX_WORKSPACE_ROOT

use flake "$NIX_WORKSPACE_ROOT#myproject"

export WS_ZSH_DIR="$NIX_WORKSPACE_ROOT/myproject"
export KUBECONFIG="$WS_PROJECT_ROOT/.kube/config"   # dynamic exports last
```

Line by line:

1. **`WS_PROJECT_ROOT="$OLDPWD"` — first, always.** direnv evaluates the shim `.envrc` in the project repo, then `source_env` pushd's into this file's directory — so here, `$PWD` is the *workspace* project dir, not the project repo. `$OLDPWD` still holds the project repo at this moment; capture it before anything else changes directories. Every project-anchored export hangs off it.
2. **`NIX_WORKSPACE_ROOT` self-location fallback.** Normally hooks.zsh exports this, but direnv can run where your zsh hooks never loaded (editor direnv plugins, `direnv exec` in scripts). The `${VAR:-...}` form keeps the existing value when present and derives it from this file's own path otherwise — so the workspace path stays hardcoded in exactly one place: the project shim.
3. **`use flake`** loads the devShell (cached by nix-direnv).
4. **`WS_ZSH_DIR`** tells hooks.zsh where to find this project's `*.zsh` extras.
5. **Dynamic exports** go last, anchored to `$WS_PROJECT_ROOT`. Static vars belong in shell.nix's `env` argument instead; never export `NIX_SHELL_NAME` here — the devShell sets it.

## The stable API

`mkWorkspaceShell` is called in two stages:

```nix
mkWorkspaceShell = framework.lib.mkWorkspaceShell { inherit pkgs common; };
# common = { packages = [ ... ]; }

mkWorkspaceShell {
  name = "myproject";          # becomes $NIX_SHELL_NAME (prompt marker key)
  zdotdir = ./.;               # project dir; ZDOTDIR for the manual fallback
  greeting = "🚀 ...";         # banner headline
  packages = with pkgs; [ ];   # project-specific packages
  env = { };                   # static env vars (reserved keys rejected: packages,
                               #   shellHook, NIX_SHELL_NAME, NIX_WS_FRAMEWORK_HOOKS)
  versionChecks = [            # rendered by the generated `versions` command
    { label = "Git:      "; command = "git --version"; }
  ];
}
```

The devShell ↔ hooks.zsh contract: the shell provides `NIX_SHELL_NAME` (drives the prompt marker) and a `versions` executable (the banner); the envrc exports `WS_ZSH_DIR` (where hooks.zsh finds `*.zsh` extras to source).

## Conventions that make this work

- **Flake source = git tree**: `git add` new files before `nix develop`/`use flake` can see them
- **Env var placement**: static vars → `env` argument; dynamic/project-anchored vars → the envrc (which captures the project repo root as `WS_PROJECT_ROOT` from `$OLDPWD` — inside a `source_env`'d file, `$PWD` is the envrc's own directory, not the project)
- **Secrets and personal config** (accounts, tokens, hostnames) stay in `$HOME` files, never in the workspace repo; `extras.zsh` should be team-shareable. This is mechanical, not just hygiene: `zdotdir = ./.` copies the whole project directory into the Nix store, which is **world-readable on multi-user Nix installs** — any file in a project dir becomes readable by every local user once the shell evaluates
- **devShell attr names can't contain dots**: directory `my.project` → attr `my-project`
- **hooks.zsh is generated, not hand-edited**: the canonical copy lives in this repo; your workspace holds a byte-identical copy (it must exist at a stable path for `~/.zshrc`, and it self-locates your repo). `nix run .#sync-hooks` regenerates it from the rev pinned in your `flake.lock`, so hooks and library never skew. Every devShell also exports `NIX_WS_FRAMEWORK_HOOKS` (the canonical file at the locked rev), and hooks.zsh warns once per session if your copy differs — so you'll know when an update touched the hooks

## Updating

```bash
nix flake update framework    # in your workspace repo — bumps the pinned framework
nix run .#sync-hooks          # regenerate hooks.zsh from the new pin (commit it)
direnv reload                 # in a project — refresh the nix-direnv cache
exec zsh                      # pick up the refreshed hooks in your current terminal
```

## Known limitations

- **The prompt marker assumes a static `PROMPT`.** hooks.zsh captures the base prompt once, on first render, then inserts the marker (`nix-shell ❄︎` before `%c` for themes like robbyrussell, a prepended `❄︎ <name>` otherwise). Themes that rewrite `PROMPT` on every precmd — powerlevel10k, some starship setups — will clobber the marker or be frozen by the captured copy. Static-PROMPT themes (robbyrussell, agnoster and most oh-my-zsh themes) work as intended. A p10k segment driven by `$NIX_SHELL_NAME` would be the native alternative for those setups.
- **Only the first `%c` gets the marker.** A theme with multiple `%c` occurrences sees the insertion once.
- **Aliases persist after you leave a project.** direnv unloads env vars on exit, but zsh has no unload channel for aliases and functions, so the last-entered project's definitions remain in a shell that's outside every project (`exec zsh` resets). *Inside* a project you always have that project's own definitions — extras re-source on entry. True unload is a tracked investigation, not a current feature.

## Testing

`make test` runs everything CI runs: `make check` (the pure suite below) and `make integration` (`tests/integration.sh` — template onboarding and a direnv end-to-end test, which need a real Nix daemon).

`nix flake check` runs the regression suite (`tests/checks.nix`): API-contract tests for `mkWorkspaceShell`, behavioral tests for hooks.zsh in headless zsh (prompt marker, extras sourcing, drift alert), banner rendering, and syntax checks. The flake's `nixpkgs` input exists only for these checks; the library always takes `pkgs` from your flake, and you can add `inputs.framework.inputs.nixpkgs.follows = "nixpkgs"` to keep a single nixpkgs in your lock.

## License

MIT — see [LICENSE](LICENSE).
