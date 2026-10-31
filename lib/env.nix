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

  # True when `path` is an absolute path.
  isAbsolute = path: builtins.substring 0 1 (toString path) == "/";

  # The directory the evaluation was started from. It is the checkout when
  # the configuration is built from inside it.
  cwd = fromEnv "PWD" "";

  # True when the current directory is a checkout of *this* configuration.
  #
  # `lib/env.nix` is what makes the check specific: another project may well
  # have a flake.nix of its own, and mistaking its directory for this one
  # would point the secret files at the wrong place.
  #
  # In a pure evaluation `builtins.pathExists` is false for anything outside
  # the Nix store, so this is false there, which is correct: a pure
  # evaluation is a placeholder build.
  cwdIsCheckout =
    cwd != "" && builtins.pathExists "${cwd}/flake.nix" && builtins.pathExists "${cwd}/lib/env.nix";

  # The checkout this configuration is deployed from.
  #
  # Everything that names a file in the repository is resolved against it, so
  # no absolute path is written into the configuration. `scripts/rebuild.sh`
  # exports it; building from inside the checkout finds it on its own; a
  # pure evaluation falls back to the flake's own source directory, which is
  # a placeholder that holds no secret files.
  repoRoot = fromEnv "NIX_VPS_ROOT" (if cwdIsCheckout then cwd else toString ../.);

  # True when the checkout root is a real checkout rather than the flake's
  # own source copy, i.e. when the deployment knows where its files are.
  # A build that cannot tell is a build that cannot find the secret files.
  repoRootIsCheckout = fromEnv "NIX_VPS_ROOT" "" != "" || cwdIsCheckout;

  # The directory holding the per-machine secret files, relative to the
  # checkout. It is resolved against `repoRoot` above, so a deployment never
  # names an absolute path for its own files.
  #
  # The files are gitignored, so they are never in git and never in the Nix
  # store -- the store is world-readable, and Nix only ever holds the *path*
  # to a file.
  secretsDir = fromEnv "SECRETS_DIR" "secrets";

  # Resolve a path against the checkout. A relative path stays inside the
  # repository; an absolute one is used as it is.
  resolvePath = path: if isAbsolute path then toString path else "${repoRoot}/${path}";
in
{
  inherit
    fromEnv
    repoRoot
    repoRootIsCheckout
    secretsDir
    resolvePath
    ;

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
