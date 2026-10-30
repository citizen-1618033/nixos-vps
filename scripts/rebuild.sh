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

action="${1:-switch}"
if [ "$#" -gt 0 ]; then
  shift
fi

: "${FLAKE_OUTPUT:=nixos}"

# `git+file://` keeps the source pinned to the tracked tree, the same way
# `--flake .#<name>` does from inside the repository.
exec nixos-rebuild "$action" --flake "git+file://$repo_root#$FLAKE_OUTPUT" --impure "$@"
