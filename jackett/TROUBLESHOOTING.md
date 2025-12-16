# Jackett Troubleshooting Guide

## Current Issues Fixed

### ✅ Issue 1: The Pirate Bay "num_files" Error
**Error:** `Selector "num_files" didn't match`
**Status:** Fixed with FlareSolverr setup
**Solution:** Remove and re-add The Pirate Bay indexer after configuring FlareSolverr

### ✅ Issue 2: 1337x Cloudflare Challenge
**Error:** `Challenge detected but FlareSolverr is not configured`
**Status:** Fixed with FlareSolverr integration
**Solution:** FlareSolverr now handles Cloudflare bypass automatically

## Quick Fix Steps

1. **Configure FlareSolverr in Jackett:**
   - Go to: http://100.123.154.40:9117
   - Settings → FlareSolverr URL: `http://127.0.0.1:8191`
   - Save settings

2. **Reset Problematic Indexers:**
   - Remove: The Pirate Bay, 1337x
   - Re-add them from the indexer list
   - Test each indexer

3. **Add Reliable Alternatives:**
   - TorrentGalaxy (excellent TPB alternative)
   - LimeTorrents (good general content)
   - YTS (high-quality movies)
   - EZTV (TV shows)

## Verification Commands

```bash
# Check service status
docker-compose ps

# Check logs for errors
docker-compose logs --tail=20

# Test FlareSolverr connectivity
docker-compose exec jackett curl -s http://127.0.0.1:8191

# Restart services if needed
docker-compose restart
```

## Common Error Patterns

### "Selector didn't match" errors
- Usually means the indexer definition is outdated
- **Fix:** Remove and re-add the indexer

### "Challenge detected" errors  
- Cloudflare protection blocking access
- **Fix:** Ensure FlareSolverr is configured and running

### "Connection refused" errors
- Network connectivity issues
- **Fix:** Check VPN container status, restart services

## Best Practices

1. **Use Multiple Indexers:** Don't rely on just one or two
2. **Regular Testing:** Test indexers weekly
3. **Monitor Logs:** Check for errors regularly
4. **Keep Updated:** Update Jackett monthly

## Emergency Fallback Indexers

If TPB and 1337x continue to fail, these are very reliable:
- **TorrentGalaxy** - Best overall alternative
- **LimeTorrents** - Consistent uptime
- **Zooqle** - Good for movies/TV
- **YTS** - Movies only, excellent quality
