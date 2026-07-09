#!/usr/bin/env bash
# Impure integration tests: the template onboarding path a new user takes,
# plus an optional direnv end-to-end test. These need a real Nix daemon
# (nix flake init, nested nix develop), so they can't live in `checks` —
# see tests/checks.nix for the pure regression suite.
#
# Run from anywhere: ./tests/integration.sh
# The scaffolded workspace consumes THIS clone (framework.url is rewritten
# to path:<clone>), so the test covers your working tree, not origin/main.
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
tmp=$(cd "$tmp" && pwd -P)   # resolve symlinks (macOS /var/folders) — direnv allows by real path
trap 'rm -rf "$tmp"' EXIT

log()  { printf '\n== %s\n' "$*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

log "template onboarding"
cd "$tmp"
nix flake init -t "path:$repo#workspace"
[ ! -e hooks.zsh ] || fail "template must not ship a hooks.zsh (sync-hooks materializes it)"
sed -i.orig "s|github:midden-lab/nix-workspace-framework|path:$repo|" flake.nix
rm flake.nix.orig
git init -q
git add -A

log "sync-hooks materializes a byte-identical hooks.zsh"
nix run .#sync-hooks
cmp "$repo/hooks.zsh" hooks.zsh || fail "synced hooks.zsh differs from the canonical copy"
git add hooks.zsh

log "example devShell: banner, NIX_SHELL_NAME, canonical hooks export"
out=$(nix develop .#example --command versions)
grep -F "Example Environment Loaded" <<<"$out" >/dev/null \
  || fail "versions banner missing greeting: $out"
name=$(nix develop .#example --command sh -c 'echo "$NIX_SHELL_NAME"')
[ "$name" = "example" ] || fail "NIX_SHELL_NAME: expected 'example', got '$name'"
nix develop .#example --command sh -c 'cmp -s "$NIX_WS_FRAMEWORK_HOOKS" '"$repo/hooks.zsh" \
  || fail "NIX_WS_FRAMEWORK_HOOKS does not match the canonical hooks.zsh"

log "direnv end-to-end"
if command -v direnv >/dev/null; then
  proj="$tmp-proj"
  mkdir -p "$proj"
  trap 'rm -rf "$tmp" "$proj"' EXIT
  echo "source_env $tmp/example/envrc" > "$proj/.envrc"
  direnv allow "$proj/.envrc"
  # Unset NIX_WORKSPACE_ROOT: if the invoking shell has a real workspace's
  # hooks.zsh loaded, the scaffolded envrc's fallback would defer to it and
  # point at the wrong repo. The test wants the self-location path.
  vars=$(env -u NIX_WORKSPACE_ROOT direnv exec "$proj" sh -c 'echo "$NIX_SHELL_NAME|$WS_PROJECT_ROOT|$WS_ZSH_DIR"')
  [ "$vars" = "example|$proj|$tmp/example" ] \
    || fail "direnv env: expected 'example|$proj|$tmp/example', got '$vars'"
else
  echo "   direnv not on PATH — skipped"
fi

log "integration: all tests passed"
