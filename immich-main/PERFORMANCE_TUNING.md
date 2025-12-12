# Immich Performance Tuning Guide

## Problem
Immich was consuming excessive CPU resources (300%+ CPU usage) causing system instability and crashes. This was primarily due to:
- Multiple concurrent video transcoding jobs (ffmpeg processes)
- Machine learning tasks running simultaneously
- No resource limits on Docker containers

## Solution Applied

### 1. Docker Resource Limits (docker-compose.yml)
Added CPU and memory limits to prevent Immich from overwhelming the system:

**immich-server:**
- CPU limit: 2.5 cores (out of 4 available)
- Memory limit: 3GB
- Reserved: 1 core, 1GB

**immich-machine-learning:**
- CPU limit: 2.0 cores
- Memory limit: 2GB
- Reserved: 0.5 cores, 512MB

### 2. Environment Variables (.env)
- `CPU_CORES=2` - Limits Immich to use only 2 CPU cores for processing

### 3. Admin UI Job Concurrency Settings
You **MUST** also adjust the job concurrency settings in the Immich Admin UI:

1. Log into Immich as admin
2. Go to **Administration** → **Settings** → **Job Settings**
3. Reduce the following concurrent job values:

   **Recommended Settings for 4-core system:**
   - **Video Transcoding**: 1 (default is 1, keep it low!)
   - **Smart Search**: 1
   - **Face Detection**: 1
   - **Facial Recognition**: 1 (cannot be changed)
   - **Thumbnail Generation**: 2-3 (don't exceed CPU core count)
   - **Metadata Extraction**: 3-4

   **Important:** Video transcoding is the most CPU-intensive task. Keep it at 1 to prevent system overload.

4. Click **Save** at the bottom of the page

## Applying Changes

After editing the docker-compose.yml and .env files, restart Immich:

```bash
cd /home/brandon/projects/docker/immich-main
docker compose down
docker compose up -d
```

## Monitoring System Load

Check if Immich is still overloading the system:

```bash
# Check overall system load
uptime

# Check CPU usage by process
top -b -n 1 | head -20

# Check Immich container resource usage
docker stats immich_server immich_machine_learning
```

**Healthy load average:** Should be below 4.0 on a 4-core system
**Current load before fix:** 20+ (extremely high!)

## Additional Optimizations

### Enable Hardware Transcoding (Optional)
If you have Intel Quick Sync or NVIDIA GPU, you can enable hardware transcoding to reduce CPU load:
- See: https://docs.immich.app/features/hardware-transcoding

### Reduce Transcoding Quality
In Admin UI → Video Transcoding Settings:
- Lower **Target Resolution** from 720p to 480p (if acceptable)
- Change **Preset** from "ultrafast" to "fast" or "medium" (better compression, slower encoding)
- Set **Transcode Policy** to "required" (only transcode when necessary)

### Schedule Heavy Jobs
Consider running heavy jobs (Smart Search, Face Detection) during off-peak hours when the system isn't being used.

## Troubleshooting

If the system is still overloaded:
1. Check `docker logs immich_server` for errors
2. Further reduce job concurrency in Admin UI
3. Lower CPU_CORES to 1 in .env file
4. Consider adding swap space (currently 0)
5. Monitor with: `journalctl -f` and `dmesg -w`

## References
- [Immich Environment Variables](https://docs.immich.app/install/environment-variables)
- [Immich System Settings](https://docs.immich.app/administration/system-settings)
- [Hardware Transcoding](https://docs.immich.app/features/hardware-transcoding)

