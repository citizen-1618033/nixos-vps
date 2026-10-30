#!/usr/bin/env bash
# Create the secret files this configuration expects.
#
# The files are created empty, mode 0600, owned by root. You fill them in
# yourself. They are never in git and never in the Nix store -- Nix only
# ever holds the *path* to a file.
#
# Usage: scripts/init-secrets.sh [directory]      (default: /etc/nix-vps)
#
# Run this once per machine, before the first `nixos-rebuild switch`.

set -euo pipefail

dir="${1:-/etc/nix-vps}"

if [ "$(id -u)" -ne 0 ]; then
  echo "error: must run as root (it creates $dir with root-only permissions)" >&2
  exit 1
fi

install -d -m 0700 -o root -g root "$dir"

create() {
  file="$1"
  if [ -e "$file" ]; then
    echo "kept     $file (already exists, not modified)"
  else
    : >"$file"
    chown root:root "$file"
    chmod 0600 "$file"
    echo "created  $file"
  fi
}

create "$dir/portainer.env"
create "$dir/caddy.env"

cat <<EOF

Next steps
----------
1. Generate a Portainer setup token and put it in $dir/portainer.env:

     openssl rand -hex 16 | sed 's/^/PORTAINER_SETUP_TOKEN=/' >> $dir/portainer.env

   The token stays valid until you complete the first-run setup, so there is
   no time pressure. You can delete the line afterwards.

2. Deploy the configuration:

     cd /root/nix-vps && ./scripts/rebuild.sh

3. Open https://portainer.app.<your-domain> and paste the token.

About $dir/caddy.env
--------------------
Optional. It is only needed for ACME EAB credentials or any other Caddy
setting that wants an environment variable. Leave it empty and ignore it.
EOF
