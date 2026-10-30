# Caddy: TLS termination and reverse proxy for everything this host serves.
#
# Shape of the deployment:
#
#   internet --443/tcp--> Caddy (real Let's Encrypt certificate)
#                         `--127.0.0.1:9443--> Portainer container
#
# Caddy obtains and renews the certificate itself over the ACME HTTP-01
# challenge, which requires an inbound A record for each hostname in
# hostConfig.vhosts pointing at this VPS, and inbound TCP port 80 to work.
#
# Certificates are per fully-qualified name. If the apex domain is served by
# a different machine, this one only ever asks for the names listed here, and
# the two machines never interfere.
{
  config,
  lib,
  pkgs,
  hostConfig,
  ...
}:
let
  portainerPort = config.portainer.publishedPort;

  # "portainer" is a shorthand for the Portainer UI. Everything else is
  # treated as an upstream address and proxied verbatim.
  resolveUpstream =
    upstream:
    if upstream == "portainer" then
      {
        url = "https://127.0.0.1:${toString portainerPort}";
        # Portainer serves 9443 with a self-signed certificate, so the name
        # and the chain cannot be verified. This hop never leaves the host,
        # so skipping verification does not weaken the public TLS session.
        insecure = true;
      }
    else
      {
        url = upstream;
        insecure = false;
      };
in
{
  services.caddy = {
    enable = true;

    # Contact address for the ACME account (Let's Encrypt). Used for expiry
    # and abuse notices.
    email = hostConfig.acmeEmail;

    # Opens TCP 80 and TCP/UDP 443 in the NixOS firewall. TCP 80 is needed
    # for the ACME HTTP-01 challenge; it also serves the automatic
    # HTTP-to-HTTPS redirect.
    openFirewall = true;

    # Reload instead of restart when the generated Caddyfile changes, so
    # in-flight requests are not dropped.
    enableReload = true;

    virtualHosts = lib.listToAttrs (
      map (
        vhost:
        let
          resolved = resolveUpstream vhost.upstream;

          transport = lib.optionalString resolved.insecure ''
            transport http {
              tls_insecure_skip_verify
            }
          '';
        in
        {
          name = vhost.name;
          value = {
            extraConfig = ''
              reverse_proxy ${resolved.url} {
                ${transport}
              }

              header {
                Strict-Transport-Security "max-age=31536000"
                X-Content-Type-Options "nosniff"
                Referrer-Policy "strict-origin-when-cross-origin"
                -Server
              }
            '';
          };
        }
      ) hostConfig.vhosts
    );
  };
}
