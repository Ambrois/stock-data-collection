# Systemd Notes

These are operational notes for the self-hosted Shiny app on `lilcenter`.

## Runtime Topology

```text
stockdb.ambrois.uk
  -> Cloudflare DNS A record
  -> home router port forwards 80/443
  -> caddy.service
  -> stockdb-shiny.service on :3838
  -> local PostgreSQL on :5432
```

## Units

`stockdb-shiny.service`

- Custom unit: `/etc/systemd/system/stockdb-shiny.service`
- Runs the Shiny app from `/home/mh/stock_data_collection/shiny_app`
- Starts R with `shiny::runApp(host="0.0.0.0", port=3838)`
- Loads DB secret from `/etc/stockdb/shiny.env`
- Depends on network and Postgres being available

`caddy.service`

- Package-managed unit
- Config: `/etc/caddy/Caddyfile`
- Public HTTPS entrypoint for `stockdb.ambrois.uk`
- Current app route is `reverse_proxy localhost:3838`
- Caddy owns TLS certificate management

`cloudflare-ddns.service`

- Custom oneshot unit: `/etc/systemd/system/cloudflare-ddns.service`
- Runs `/home/mh/stock_data_collection/scripts/cloudflare_ddns.sh`
- Loads Cloudflare token/settings from `/etc/stockdb/cloudflare-ddns.env`
- Updates the `stockdb.ambrois.uk` A record if the residential public IP changed
- `inactive (dead)` is normal after successful runs

`cloudflare-ddns.timer`

- Custom timer: `/etc/systemd/system/cloudflare-ddns.timer`
- Triggers `cloudflare-ddns.service`
- Runs 5 minutes after boot, then daily
- Uses `Persistent=true` so missed runs are caught up after boot

## Secrets

Secrets live outside the repo:

```text
/etc/stockdb/shiny.env
/etc/stockdb/cloudflare-ddns.env
```

The Cloudflare token should be scoped only to DNS edits for `ambrois.uk`.

## Debugging Priorities

If the site works on LAN but not externally, check in this order:

1. Cloudflare DNS A record vs current residential public IP
2. Router port forwards for 80/443 to this host
3. Caddy listener and reverse proxy
4. Shiny listener on `0.0.0.0:3838`
5. PostgreSQL and `/etc/stockdb/shiny.env`

Useful commands:

```bash
systemctl status stockdb-shiny.service caddy.service cloudflare-ddns.timer
journalctl -u stockdb-shiny.service -n 100 --no-pager
journalctl -u caddy.service -n 100 --no-pager
journalctl -u cloudflare-ddns.service -n 100 --no-pager
systemctl list-timers cloudflare-ddns.timer --no-pager
ss -ltnp
dig +short stockdb.ambrois.uk
curl -4 https://api.ipify.org
```
