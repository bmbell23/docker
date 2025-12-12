# Immich Main Instance

This is the main Immich instance running on the Docker host.

## Configuration

- **Web URL**: http://100.123.154.40:2283
- **Media Location**: `/mnt/boston/media/pictures`
- **Database Location**: `/home/brandon/immich/postgres`
- **Version**: v2.3.1

## Setup

1. Copy `.env.template` to `.env`
2. Update `DB_PASSWORD` in `.env` with a secure password
3. Run: `docker compose up -d`

## Updating

To update Immich to a new version:
1. Edit `IMMICH_VERSION` in `.env`
2. Run: `docker compose pull`
3. Run: `docker compose up -d`

## Video Transcoding

- **Hardware Acceleration**: VAAPI enabled for better video performance
- **Transcoding**: Configured for improved video compatibility and aspect ratio handling
- **Monitoring**: Use `./monitor-transcoding.sh` to check transcoding status
- **Missing Videos**: Use `./check-missing-videos.sh` to find missing video files

## Troubleshooting Video Issues

If videos won't play or have aspect ratio issues:

1. Check hardware acceleration: `./monitor-transcoding.sh`
2. Verify transcoding settings in Admin > Settings > Video Transcoding
3. Look for missing files: `./check-missing-videos.sh`
4. Check container logs: `docker logs immich_server --tail 50`

## Notes

- The postgres data directory remains at `/home/brandon/immich/postgres` (not in this repo)
- Media files are stored on the NAS mount at `/mnt/boston/media/pictures`
- Hardware acceleration uses VAAPI with `/dev/dri/card0`
