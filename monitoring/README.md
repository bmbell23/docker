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
- Mongo: put the Mattermost incoming-webhook URL, alone on one line, in
  `alertmanager/secrets/mongo_webhook_url` (gitignored). It's read at send time, so no restart is needed.
- Rule or scrape changes: `curl -X POST localhost:9090/-/reload`. Alertmanager: `curl -X POST localhost:9093/-/reload`.
- Validate before reloading:
  `docker exec prometheus promtool check config /etc/prometheus/prometheus.yml`,
  `docker exec alertmanager amtool check-config /etc/alertmanager/alertmanager.yml`.

## Storage
History lives in the named volumes `monitoring_prometheus_data`, `monitoring_grafana_data`, and
`monitoring_alertmanager_data`, under the Docker root on `/mnt/docker`. Prometheus keeps 30 days
or 10 GB, whichever comes first. **Never `down -v`**, because it deletes the history.

## Adding a machine
Install node_exporter on it (port 9100), then add it to the `node` job in
`prometheus/prometheus.yml` with an `instance:` label. Then reload.
The planned additions are the Proxmox host, pve01, k3s01, and the GPU exporter once the card is in.

## Silencing
Use http://100.69.184.113:9093 → New Silence, for example during planned maintenance.
