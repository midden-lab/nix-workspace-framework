# nix-workspace-framework

Declarative, per-project development environments using Nix flakes, direnv, and zsh. Each project gets a reproducible devShell that auto-activates on `cd`, with pinned tool versions, team-shareable aliases, and a clean separation between shared infrastructure, project tooling, and personal settings.

The framework is intentionally small: one Nix function (`mkWorkspaceShell`), one zsh integration file (`hooks.zsh`), and a set of conventions. Your actual environments live in a **private workspace repo** that consumes this framework as a flake input — your project definitions, env vars, and aliases never need to be public.

## Quick start

```bash
# 1. Scaffold your private workspace repo
mkdir ~/workspace/my-workspaces && cd ~/workspace/my-workspaces
nix flake init -t github:midden-lab/nix-workspace-framework#workspace
git init && git add . && git commit -m "Init workspace repo"

# 2. Wire up zsh (after your oh-my-zsh/prompt setup in ~/.zshrc)
#    source ~/workspace/my-workspaces/hooks.zsh

# 3. Point a project repo at the example environment
cd ~/src/some-project
echo 'source_env ~/workspace/my-workspaces/example/envrc' > .envrc
direnv allow

# 4. cd in — the environment activates, the banner prints once per session
```

Prerequisites: Nix with `experimental-features = nix-command flakes`, [direnv](https://direnv.net) + [nix-direnv](https://github.com/nix-community/nix-direnv) (`~/.config/direnv/direnvrc` sourcing nix-direnv), zsh.

## Architecture

```
this repo (public)
├── flake.nix                      lib.mkWorkspaceShell + templates.workspace
├── lib/mk-workspace-shell.nix     the shell builder
└── templates/workspace/           starter for your private workspace repo

your workspace repo (private)
├── flake.nix                      devShell per project; framework as flake input
├── flake.lock                     pins nixpkgs AND this framework
├── common.nix                     packages shared by all your projects
├── hooks.zsh                      your working copy of the zsh integration
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

**direnv path (primary):** `cd` into a project repo → the one-line `.envrc` shim `source_env`s your workspace repo's project envrc → `use flake "$NIX_WORKSPACE_ROOT#<attr>"` loads the devShell (cached by nix-direnv, near-instant after first load) → `hooks.zsh` sources the project's `*.zsh` extras and prints the version banner, once per session per project. Leaving the directory unloads the env; run `versions` anytime to reprint the banner.

**Manual fallback:** `nix develop <workspace>#<attr>` prints the banner and execs into zsh with `ZDOTDIR` pointing at the project's config (which re-sources your global zsh setup and the project extras). Non-interactive runs (`nix develop --command ...`) skip banner and exec entirely.

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
  env = { };                   # static env vars (reserved keys rejected:
                               #   packages, shellHook, NIX_SHELL_NAME)
  versionChecks = [            # rendered by the generated `versions` command
    { label = "Git:      "; command = "git --version"; }
  ];
}
```

The devShell ↔ hooks.zsh contract: the shell provides `NIX_SHELL_NAME` (drives the prompt marker) and a `versions` executable (the banner); the envrc exports `WS_ZSH_DIR` (where hooks.zsh finds `*.zsh` extras to source).

## Conventions that make this work

- **Flake source = git tree**: `git add` new files before `nix develop`/`use flake` can see them
- **Env var placement**: static vars → `env` argument; dynamic/project-anchored vars → the envrc (which captures the project repo root as `WS_PROJECT_ROOT` from `$OLDPWD` — inside a `source_env`'d file, `$PWD` is the envrc's own directory, not the project)
- **Secrets and personal config** (accounts, tokens, hostnames) stay in `$HOME` files, never in the workspace repo; `extras.zsh` should be team-shareable
- **devShell attr names can't contain dots**: directory `my.project` → attr `my-project`
- **hooks.zsh is copied, not imported**: your workspace repo owns its working copy (it must self-locate your repo's path). It changes rarely; diff against `templates/workspace/hooks.zsh` when updating the framework

## Updating

```bash
nix flake update framework    # in your workspace repo — bumps the pinned framework lib
direnv reload                 # in a project — refresh the nix-direnv cache
# hooks.zsh: diff your copy against templates/workspace/hooks.zsh occasionally
```

## License

MIT — see [LICENSE](LICENSE).
