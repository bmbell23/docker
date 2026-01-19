# Outline Scripts

This directory contains utility scripts for managing your Outline wiki instance.

## 📜 Available Scripts

### setup.sh
**Purpose**: Initial setup and configuration of Outline

**Usage**:
```bash
./scripts/setup.sh
```

**What it does**:
- Generates secure random keys (SECRET_KEY, UTILS_SECRET)
- Configures all services in docker-compose.yml
- Creates MinIO bucket for file storage
- Starts all Outline services

**When to use**: First-time setup of Outline

---

### import-markdown.sh
**Purpose**: Bulk import markdown files into Outline

**Usage**:
```bash
./scripts/import-markdown.sh
```

**Prerequisites**:
1. Generate an API token in Outline (Settings → API Tokens)
2. Edit the script and set `API_TOKEN` variable
3. Place `.md` files in `/mnt/boston/media/notes/` (or configure `SOURCE_DIR`)

**What it does**:
- Creates a collection called "Imported Notes"
- Imports all `.md` files from the source directory
- Converts filenames to document titles
- Preserves markdown formatting

**Configuration**:
- `API_TOKEN`: Your Outline API token (required)
- `OUTLINE_URL`: Outline instance URL (default: http://100.123.154.40:8000)
- `COLLECTION_NAME`: Target collection name (default: "Imported Notes")
- `SOURCE_DIR`: Directory containing `.md` files (default: /mnt/boston/media/notes)

---

### backup-outline.sh
**Purpose**: Complete backup of Outline data

**Usage**:
```bash
./scripts/backup-outline.sh
```

**What it backs up**:
1. **PostgreSQL database** - All wiki content, users, settings
2. **MinIO storage** - Uploaded files, images, attachments
3. **Configuration** - docker-compose.yml
4. **Markdown export** - All documents as `.md` files (optional, requires API token)

**Backup location**: `/mnt/boston/media/backups/outline/YYYYMMDD_HHMMSS/`

**Optional configuration**:
- Set `API_TOKEN` in the script to enable markdown exports

**Automated backups**:
```bash
# Add to crontab for daily backups at 2 AM
crontab -e
0 2 * * * cd /home/brandon/projects/docker/outline && ./scripts/backup-outline.sh >> /var/log/outline-backup.log 2>&1
```

---

### restore-outline.sh
**Purpose**: Restore Outline from a backup

**Usage**:
```bash
./scripts/restore-outline.sh /path/to/backup/directory
```

**Example**:
```bash
./scripts/restore-outline.sh /mnt/boston/media/backups/outline/20260119_143000
```

**What it does**:
1. Stops Outline service
2. Restores PostgreSQL database
3. Restores MinIO storage
4. Restarts Outline service

**⚠️ Warning**: This will **replace all current data**!

---

## 🔧 Script Permissions

All scripts are executable. If you need to make them executable again:

```bash
chmod +x scripts/*.sh
```

## 📚 Documentation

For detailed guides and examples, see:
- **[../README.md](../README.md)** - Main Outline documentation
- **[../IMPORT_AND_BACKUP_GUIDE.md](../IMPORT_AND_BACKUP_GUIDE.md)** - Detailed import and backup guide
- **[../QUICKSTART.md](../QUICKSTART.md)** - Quick start guide

## 🐛 Troubleshooting

### "Permission denied" errors
```bash
chmod +x scripts/*.sh
```

### "API_TOKEN is not set" (import/backup scripts)
1. Log into Outline
2. Go to Settings → API Tokens
3. Create a new token
4. Edit the script and set `API_TOKEN="your_token_here"`

### Backup/restore fails
- Ensure Docker containers are running: `docker ps`
- Check disk space: `df -h`
- Verify backup directory exists and is writable
- Check logs for specific errors

### Import fails
- Verify API token is valid
- Check that `.md` files are UTF-8 encoded
- Ensure source directory exists and contains `.md` files
- Check Outline logs: `docker logs outline`

