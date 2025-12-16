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

## FlareSolverr Configuration (IMPORTANT)

FlareSolverr is now included to bypass Cloudflare protection on sites like 1337x.

**Configure FlareSolverr in Jackett:**
1. Go to Jackett web UI: `http://100.123.154.40:9117`
2. Click the wrench icon (Settings) in top right
3. Scroll down to "FlareSolverr" section
4. Set **FlareSolverr URL** to: `http://127.0.0.1:8191`
5. Click "Save"

**After configuring FlareSolverr:**
- Remove and re-add 1337x indexer
- Remove and re-add The Pirate Bay indexer
- Test both indexers

## Troubleshooting

### Common Issues:

**1. "Challenge detected but FlareSolverr is not configured"**
- Configure FlareSolverr URL as shown above
- Remove and re-add the failing indexer

**2. "Selector 'num_files' didn't match" (Pirate Bay)**
- Remove The Pirate Bay indexer completely
- Re-add it from the indexer list
- If still failing, try alternative indexers

**3. Can't access UI:**
- Check if port 9117 is available
- Ensure VPN container is running

**4. Indexers failing:**
- Some sites may be blocked or down
- Try alternative indexers (see recommended-indexers.md)

**5. Slow searches:**
- Normal - Jackett queries multiple sites
- FlareSolverr adds extra time for Cloudflare bypass

