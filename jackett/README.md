# Jackett - Torrent Indexer Proxy

Jackett works as a proxy server: it translates queries from apps (like qBittorrent, Sonarr, Radarr) into tracker-site-specific HTTP queries, parses the HTML response, then sends results back to the requesting software.

## Quick Start

1. **Start Jackett:**
   ```bash
   docker-compose up -d
   ```

2. **Access Web UI:**
   - URL: `http://100.123.154.40:9117`
   - No default credentials - set up on first access

3. **Add Indexers:**
   - Click "Add indexer"
   - Search for your preferred torrent sites
   - Configure credentials for each site
   - Test the indexer

4. **Integrate with qBittorrent:**
   - In Jackett, copy the Torznab Feed URL for each indexer
   - In qBittorrent: Tools → Search plugins → Install a new one
   - Use Jackett's API key and Torznab URLs

## Configuration

- **Config location:** `/home/brandon/jackett/config`
- **Download location:** `/mnt/boston/media/torrents` (shared with qBittorrent)
- **Port:** 9117

## Common Indexers

Popular public indexers to add:
- The Pirate Bay
- 1337x
- RARBG
- EZTV
- YTS

## API Key

After first setup, find your API key in Jackett's web UI (top right corner).
You'll need this to integrate with other apps.

## Troubleshooting

- **Can't access UI:** Check if port 9117 is available
- **Indexers failing:** Some sites may be blocked or down
- **Slow searches:** Normal - Jackett queries multiple sites

