# Deployment values that come from the environment.
#
# A deployment supplies them through the `.env` file in the repository root.
# `.env` is gitignored; `.env.example` is the committed template.
#
# Nix cannot read `.env` on its own. A flake evaluation is pure, so the
# environment is invisible to it, and the flake source is the tracked tree, so
# an untracked `.env` is not part of it either. `scripts/rebuild.sh` therefore
# exports the values and re-runs the evaluation with `--impure`.
#
# Under a pure evaluation every lookup falls back to its placeholder, so a
# plain checkout of this repository always evaluates to something harmless.
let
  # The value of the environment variable `name`, or `fallback` when it is
  # unset or empty.
  fromEnv =
    name: fallback:
    let
      value = builtins.getEnv name;
    in
    if value == "" then fallback else value;
in
{
  inherit fromEnv;

  # The base domain this machine serves, e.g. "example.com". The public
  # hostnames are derived from it.
  domain = fromEnv "PUBLIC_DOMAIN" "example.com";

  # The contact address registered with the ACME certificate authority.
  # Used for expiry notices and abuse reports.
  acmeEmail = fromEnv "ACME_EMAIL" "admin@example.com";

  # The public IPv4 address of this machine. Every hostname it serves needs a
  # DNS A record pointing here.
  publicIp = fromEnv "PUBLIC_IP" "203.0.113.10";
}
