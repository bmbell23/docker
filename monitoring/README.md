# Monitoring

```
node_exporter (each machine) ─┐
cAdvisor (dockerhost)  ───────┼─> Prometheus ──rules──> Alertmanager ──> Mongo (Mattermost)
                              │       │
                              └───────┴──> Grafana (history)
```

| Container | Host port | URL |
|---|---|---|
| `grafana` | 8016 | http://100.69.184.113:8016 |
| `prometheus` | 9090 | http://100.69.184.113:9090 |
| `alertmanager` | 9093 | http://100.69.184.113:9093 |
| `node-exporter` | 9100 (host network) | http://100.69.184.113:9100/metrics |
| `cadvisor` | (internal) | scraped on the compose network |
| `blackbox-exporter` | (internal) | probes URLs; job `k3s-ingress` (docker#121) |
| `pve-exporter` | (internal) | pve01's VM state, read-only PVEAuditor token; job `pve` (docker#123) |

k3s node readiness comes from kube-state-metrics on the cluster (proxmox#66), NodePort
`10.0.0.201:30808`, job `kube-state-metrics`.

`pve-exporter` reads `monitoring/.env` (gitignored; copy `.env.example`). The token is in
Vaultwarden as "pve01 monitoring token". Without that file `docker compose` refuses to start
the stack, so a deploy fails loudly instead of running a blind exporter.

## Who owns what
- **This stack, scrape targets, retention:** docker/ (Dakota).
- **Alert rules** (`prometheus/rules/*.yml`): Daisy tunes thresholds; changes still land here by PR.
- **Mongo** (the Mattermost webhook/bot that posts alerts): agent-bus (Bianca).

## Deploy
```bash
cd /home/brandon/projects/docker/monitoring
docker compose up -d
```
- Grafana's first login is `admin` / `admin`, and it forces a new password. Save it in Vaultwarden.
  Anonymous visitors get read-only Viewer access.
- Mongo: Alertmanager posts its standard webhook JSON to `http://agentbus_mongo:9095/alert`,
  agent-bus's bridge, which posts as @mongo in #infra (docker#96). No secret on this side.
- The config dirs are mounted as directories, so a merged change is in the container right
  away; a `/-/reload` applies it. File mounts kept the pre-pull copy (docker#96).
- **Merges apply themselves** (docker#104): the reconciler runs the repo's `./deploy`, which checks
  and reloads Prometheus/Alertmanager/blackbox_exporter when their config changed, and runs `up -d` when the compose
  file did. A config that fails its check fails the deploy (Mongo says so), and the old config keeps running.
  Stamps: `logs/deploy/mon-*-applied.sha256`.
- By hand: `curl -X POST localhost:9090/-/reload`. Alertmanager: `curl -X POST localhost:9093/-/reload`.
- Validate before reloading:
  `docker exec prometheus promtool check config /etc/prometheus/prometheus.yml`,
  `docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml`.
- Rule tests live in `prometheus/tests/`:
  `docker exec -w /etc/prometheus/tests prometheus sh -c 'promtool test rules *_test.yml'`.

## Storage
History lives in the named volumes `monitoring_prometheus_data`, `monitoring_grafana_data`, and
`monitoring_alertmanager_data`, under the Docker root on `/mnt/docker`. Prometheus keeps 30 days
or 10 GB, whichever comes first. **Never `down -v`**, because it deletes the history.

## Adding a machine
Install node_exporter on it (port 9100), then add it to the `node` job in
`prometheus/prometheus.yml` with an `instance:` label. The merge reloads it.
Watched now: dockerhost, the Proxmox host (plus SMART), pve01, k3s01-03. Still planned: the GPU exporter once the card is in.

## Probing a URL
**A new dockerhost service:** give it a Dashboard card. The Dashboard probes every card URL and
exports `dashboard_card_up` (job `dashboard-cards`); `ServiceDown` (critical, 5m) pages Mongo with
the service and its owner (docker#127, Dashboard#66).

Anything else: add it to the `k3s-ingress` job's targets (or a new job with the same relabelling) in
`prometheus/prometheus.yml`. Modules are in `blackbox/blackbox.yml`; `http_2xx` skips cert
verification on purpose, since it's an up/down check (Rancher's cert is self-signed).

## Silencing
Use http://100.69.184.113:9093 → New Silence, for example during planned maintenance.
