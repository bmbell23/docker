# Immich Setup and Credentials Issue

## Current Status
- **Service**: Running and accessible at http://100.123.154.40:2283
- **Database**: Connected and healthy
- **Problem**: No users exist in the database

## Issue
The Immich database has no user accounts. This happened because Immich was crashing during startup (due to database connection timeouts) before it could create the initial admin user.

## Solution: Create Admin User via Web UI

### Step 1: Access Immich
Open your browser and go to:
- **Local**: http://192.168.0.158:2283
- **Tailscale**: http://100.123.154.40:2283

### Step 2: Initial Setup
Since there are no users, Immich should show the "Getting Started" or "Welcome" page where you can create the first admin user.

1. Click "Getting Started" or similar button
2. Fill in the admin user details:
   - **Email**: brandon@forge-freedom.com (or your preferred email)
   - **Password**: (choose a secure password)
   - **Name**: Brandon (or your preferred name)
3. Click "Sign Up" or "Create Account"

### Step 3: Verify User Creation
After creating the account, you should be able to log in immediately.

## If Web UI Doesn't Show Setup Page

If the web UI doesn't show the initial setup page, you can create a user via the CLI:

```bash
# Enter the Immich server container
docker exec -it immich_server /bin/bash

# Create admin user (replace with your details)
immich user create \
  --email brandon@forge-freedom.com \
  --password "YourSecurePassword" \
  --name "Brandon" \
  --admin

# Exit the container
exit
```

## Verify User Exists

Check the database to confirm the user was created:

```bash
docker exec immich_postgres psql -U postgres -d immich -c 'SELECT email, name, "isAdmin" FROM "user";'
```

Expected output:
```
           email            |  name   | isAdmin 
----------------------------+---------+---------
 brandon@forge-freedom.com  | Brandon | t
```

## Failed Login Attempts

The logs show failed login attempts for `brandon@forge-freedom.com`:
```
Failed login attempt for user brandon@forge-freedom.com from ip address ::ffff:100.78.34.122
```

This is because the user doesn't exist yet. Once you create the user via the web UI or CLI, you'll be able to log in.

## Troubleshooting

### "Invalid user token" errors
These are websocket connection errors from old sessions. They're harmless and will stop once you log in with a valid account.

### Can't access web UI
Verify Immich is accessible:
```bash
curl -I http://192.168.0.158:2283
```

Should return `HTTP/1.1 200 OK`.

### Database connection issues
Check if the database is healthy:
```bash
docker exec immich_postgres pg_isready -U postgres
```

Should return: `/var/run/postgresql:5432 - accepting connections`

### Container keeps restarting
Check logs:
```bash
docker logs immich_server --tail 50
```

If you see "CONNECT_TIMEOUT database:5432", the iptables rules may be missing. Run:
```bash
sudo ~/projects/docker/scripts/fix-all-docker-iptables.sh
```

## Configuration

### Environment Variables
Immich configuration is in `immich-main/.env`:
- Database: `postgres` user, `immich` database
- Host: `database` (Docker network hostname)
- Port: 5432

### Docker Compose
Service definition: `immich-main/docker-compose.yml`
- Port: 2283:2283
- Network: immich_default (172.31.0.0/16)
- Depends on: redis, database

## Next Steps After Setup

1. **Upload photos**: Use the mobile app or web UI
2. **Configure storage**: Set up external libraries if needed
3. **Enable machine learning**: Face detection, object recognition (already running)
4. **Mobile app**: Download from App Store/Play Store and connect to http://100.123.154.40:2283

## Security Notes

- Change the default password after first login
- Consider enabling 2FA in settings
- The service is accessible via Tailscale (100.123.154.40) - ensure your Tailscale network is secure
- Local network access (192.168.0.158) is also available

## Related Documentation
- `DOCKER_IPTABLES_FIX.md` - Network access issues
- `DOCKER_IPTABLES_PERSISTENCE.md` - Making iptables rules persistent
- `immich-main/TROUBLESHOOTING.md` - Official Immich troubleshooting guide

