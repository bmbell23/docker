# Pi-hole — network-wide ad & site blocking

DNS sinkhole for the whole network. Any device using this server as its DNS
gets ads, trackers, and adult sites blocked before the connection ever happens.

- **Web UI**: http://100.69.184.113:8053/admin (password in `.env`)
- **DNS**: port 53 on `10.0.0.160` (LAN), `100.69.184.113` (Tailscale), `127.0.0.1` (local).
  Not bound to `0.0.0.0` — systemd-resolved holds the `127.0.0.53:53` stub.
- **Upstream**: Cloudflare Family `1.1.1.3` / `1.0.0.3` (filters malware + adult
  content upstream too, as a second layer behind the blocklists)

## Making devices actually use it

Pi-hole only filters devices that send DNS queries to it:

- **Whole LAN**: in the router's DHCP settings, set the DNS server to
  `10.0.0.160`. Every device picks it up on its next DHCP renewal.
- **Tailscale devices**: in the Tailscale admin console → DNS, add
  `100.69.184.113` as a global nameserver (enable "Override local DNS").
- **Single device**: set its DNS manually to `10.0.0.160`.

## Blocking / unblocking a site

```bash
./scripts/block.sh example.com        # blocks example.com + all subdomains
./scripts/unblock.sh example.com
```

Or in the web UI: **Domains** → enter domain → "Add to denied list"
(check *wildcard* to include subdomains).

## Blocklists

`./scripts/setup-blocklists.sh` (idempotent) subscribes:

| List | Purpose |
|------|---------|
| StevenBlack unified | ads + malware (Pi-hole default) |
| OISD big | broad ads/trackers/malware, low false positives |
| OISD NSFW | adult content |
| StevenBlack porn-only | adult content, second source |

Lists refresh automatically every Sunday (built-in gravity cron). Force a
refresh with `docker exec pihole pihole -g`.

## Limits (what DNS blocking can't do)

- **YouTube ads** and other ads served from the *same domain* as the content
  (YouTube, Twitch, some Facebook/Instagram in-app ads) can't be blocked at the
  DNS level. Use uBlock Origin in browsers for those.
- Blocking is by domain, not URL — you can block `reddit.com`, not
  `reddit.com/r/something`.
- A device with a hardcoded DNS (e.g. `8.8.8.8`) bypasses Pi-hole unless the
  router also blocks outbound port 53.

## Ops

- Restart (docker restart is broken on this host):
  `PID=$(docker inspect pihole --format '{{.State.Pid}}'); kill $PID; cd /home/brandon/projects/docker/pihole && docker compose up -d`
- If DNS breaks network-wide, the fastest rollback is pointing the router's
  DNS back to the ISP/1.1.1.1 — devices recover on DHCP renewal.
- Config/DB lives in `./data/` (gitignored).
