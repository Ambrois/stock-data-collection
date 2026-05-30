# Systemd Notes

These are generalized operational notes for running the Shiny dashboard as a self-hosted service. They intentionally avoid real hostnames, domains, local usernames, absolute personal paths, and secret file names so the repo can remain public.

## Runtime Topology

```text
public DNS name
  -> DNS provider record
  -> HTTPS reverse proxy
  -> Shiny app systemd service
  -> local PostgreSQL/TimescaleDB
```

The reverse proxy terminates HTTPS and forwards requests to the Shiny process. The Shiny process connects to a local database using credentials loaded from an environment file outside the repository.

## Units

`stockdb-shiny.service`

- Custom systemd unit for the Shiny dashboard.
- Runs the app from the repository's `shiny_app/` directory.
- Starts R with `shiny::runApp(...)` bound to a local or private interface.
- Loads database credentials from an environment file outside the repo.
- Depends on network and PostgreSQL availability.

`reverse-proxy.service`

- Package-managed reverse proxy such as Caddy or nginx.
- Provides the public HTTPS entrypoint.
- Forwards dashboard traffic to the Shiny service.
- Owns TLS certificate management.

`cloudflare-ddns.service`

- Optional oneshot unit for dynamic DNS updates.
- Runs `scripts/cloudflare_ddns.sh`.
- Loads Cloudflare token and DNS settings from an environment file outside the repo.
- Updates the configured DNS record when the public IP changes.
- `inactive (dead)` is normal after a successful oneshot run.

`cloudflare-ddns.timer`

- Optional timer for `cloudflare-ddns.service`.
- Runs after boot and then on a recurring schedule.
- Can use `Persistent=true` so missed runs are caught up after boot.

## Secrets

Secrets should live outside the repository in service-managed environment files. Do not commit real API tokens, database passwords, hostnames, public IP addresses, or personal filesystem paths.

Typical secret/config values include:

- Shiny database password.
- Cloudflare API token.
- Cloudflare zone and DNS record names.
- Alpaca API credentials for ingestion jobs.

Cloudflare tokens should be scoped narrowly to DNS edits for the relevant zone.

## Debugging Priorities

If the dashboard works locally but not externally, check in this order:

1. DNS record vs current public IP.
2. Firewall and network forwarding rules.
3. Reverse proxy listener and upstream route.
4. Shiny service listener.
5. PostgreSQL service and Shiny database credentials.

Useful command patterns:

```bash
systemctl status <shiny-service> <reverse-proxy-service> <ddns-timer>
journalctl -u <shiny-service> -n 100 --no-pager
journalctl -u <reverse-proxy-service> -n 100 --no-pager
journalctl -u <ddns-service> -n 100 --no-pager
systemctl list-timers <ddns-timer> --no-pager
ss -ltnp
dig +short <public-dashboard-domain>
curl -4 https://api.ipify.org
```
