#!/usr/bin/env bash
# Rebuild this machine from the flake, with the deployment's values taken
# from the environment.
#
# The values live in the `.env` file in the repository root (`.env.example` is
# the template). Nix cannot read them on its own: a flake evaluation is pure,
# so the environment is invisible to it, and the flake source is the tracked
# tree, so an untracked `.env` is not part of it either. This script exports
# the values and then re-runs the evaluation with --impure.
#
# The script also exports NIX_VPS_ROOT, the path of this checkout. Every path
# in the configuration is relative to the checkout, so the evaluation needs to
# know where it is; see lib/env.nix.
#
# Usage: scripts/rebuild.sh [action] [extra nixos-rebuild arguments]
#
#   action  the nixos-rebuild action to run. Default: switch.
#           Other useful actions: build, boot, dry-activate.
#
# Examples:
#   scripts/rebuild.sh
#   scripts/rebuild.sh build
#   scripts/rebuild.sh switch --dry-activate

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
env_file="${ENV_FILE:-$repo_root/.env}"

if [ ! -f "$env_file" ]; then
  echo "error: $env_file not found." >&2
  echo "       Copy .env.example to .env and fill in your own values:" >&2
  echo "         cp .env.example .env" >&2
  exit 1
fi

# `set -a` exports every variable the file sets. A key with an empty value
# exports an empty string, which the configuration reads as unset and replaces
# with its placeholder.
set -a
# shellcheck disable=SC1090
. "$env_file"
set +a

# Where the checkout is. The configuration resolves every file it names
# against this, so the absolute path never has to be written down anywhere.
export NIX_VPS_ROOT="$repo_root"

action="${1:-switch}"
if [ "$#" -gt 0 ]; then
  shift
fi

: "${FLAKE_OUTPUT:=nixos}"

# The secret files live in the checkout and are gitignored. `git+file://`
# copies only the *tracked* files into the Nix store, so they stay out of it
# -- the store is world-readable, and a secret in it is a published secret.
#
# A `path:` flake would copy the whole directory, secrets included, and leak
# them into the store. Refuse to run rather than do that.
if git -C "$repo_root" rev-parse --git-dir >/dev/null 2>&1; then
  tracked_secrets="$(git -C "$repo_root" ls-files -- 'secrets' 'secrets/**' || true)"
  if [ -n "$tracked_secrets" ]; then
    echo "error: these secret files are tracked by git and would be copied" >&2
    echo "       into the world-readable Nix store:" >&2
    echo "$tracked_secrets" | sed 's/^/         /' >&2
    echo "       Untrack them and add the directory to .gitignore:" >&2
    echo "         git rm --cached -r secrets" >&2
    echo "         printf 'secrets/\\n' >> .gitignore" >&2
    exit 1
  fi
else
  echo "error: $repo_root is not a git checkout." >&2
  echo "       The flake is evaluated from the tracked tree, so that the" >&2
  echo "       secret files in it stay out of the Nix store. Clone the" >&2
  echo "       repository instead of copying the directory." >&2
  exit 1
fi

# `git+file://` keeps the source pinned to the tracked tree, the same way
# `--flake .#<name>` does from inside the repository.
exec nixos-rebuild "$action" --flake "git+file://$repo_root#$FLAKE_OUTPUT" --impure "$@"
