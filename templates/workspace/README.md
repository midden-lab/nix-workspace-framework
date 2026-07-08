# workspace

Private, per-project development environments built on [nix-workspace-framework](https://github.com/midden-lab/nix-workspace-framework).

Each directory here defines one project's devShell. Project repos contain only a one-line `.envrc` shim pointing back at this repo — all environment logic lives here.

## Setup (new machine)

1. Nix with `experimental-features = nix-command flakes`; direnv + nix-direnv
2. Add to `~/.zshrc` (after your prompt/oh-my-zsh setup): `source <this repo>/hooks.zsh`
3. Per project repo: `echo 'source_env <this repo>/<project>/envrc' > .envrc && direnv allow`

## Adding a project

Copy `example/`, follow its README, register the devShell in `flake.nix`, and `git add` everything — flakes only see tracked files.

## Updating

```bash
nix flake update framework   # bump the framework library
nix flake update nixpkgs     # bump pinned tool versions
direnv reload                # refresh an active project's cache
```

See the framework repo's README for the full architecture and conventions.
