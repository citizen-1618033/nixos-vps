#!/usr/bin/env bash
# Create the secret files this configuration expects.
#
# The files live in the repository checkout, in the directory named by
# SECRETS_DIR (default: "secrets", i.e. <checkout>/secrets). The directory is
# gitignored, so nothing in it is ever committed and nothing in it ever
# reaches the Nix store -- Nix only ever holds the *path* to a file.
#
# The files are created mode 0600, owned by whoever runs this script. The
# Portainer setup token is generated for you; everything else is empty for
# you to fill in.
#
# Usage: scripts/init-secrets.sh [directory]
#
#   directory  where to put the files, relative to the repository root.
#              Defaults to $SECRETS_DIR, or "secrets".
#
# Run this once per machine, before the first `nixos-rebuild switch`.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# Read the deployment values, if there are any, so that this script and
# scripts/rebuild.sh agree on where the files live.
env_file="${ENV_FILE:-$repo_root/.env}"
if [ -f "$env_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
fi

# The secrets directory, relative to the checkout unless it is absolute.
dir="${1:-${SECRETS_DIR:-secrets}}"
case "$dir" in
  /*) ;;
  *) dir="$repo_root/$dir" ;;
esac

install -d -m 0700 "$dir"

create() {
  file="$1"
  if [ -e "$file" ]; then
    echo "kept     $file (already exists, not modified)"
  else
    : >"$file"
    chmod 0600 "$file"
    echo "created  $file"
  fi
}

create "$dir/portainer.env"
create "$dir/caddy.env"

# The Portainer setup token: a fresh Portainer refuses to be claimed by
# anyone who finds the port, so it needs a one-time token. Generate one here
# instead of asking the operator to invent one, and never write it down
# anywhere but the file that needs it.
if ! grep -q '^PORTAINER_SETUP_TOKEN=' "$dir/portainer.env"; then
  # 16 random bytes, hex encoded. Read from /dev/urandom rather than from
  # openssl, which is not necessarily on PATH on NixOS.
  token="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf 'PORTAINER_SETUP_TOKEN=%s\n' "$token" >>"$dir/portainer.env"
  chmod 0600 "$dir/portainer.env"
  echo "token    $dir/portainer.env (setup token generated)"
fi

cat <<EOF

Next steps
----------
1. Read the Portainer setup token:

     grep PORTAINER_SETUP_TOKEN $dir/portainer.env

   It stays valid until you complete the first-run setup, so there is no
   time pressure. You can delete the line afterwards.

2. Deploy the configuration:

     cd $repo_root && ./scripts/rebuild.sh

3. Open https://portainer.app.<your-domain> and paste the token.

About $dir/caddy.env
--------------------
Optional. It is only needed for ACME EAB credentials or any other Caddy
setting that wants an environment variable. Leave it empty and ignore it.
EOF
