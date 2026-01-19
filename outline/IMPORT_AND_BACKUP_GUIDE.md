# Outline Import & Backup Guide

## 📥 Importing Your Markdown Files

### Quick Start

1. **Get an API Token**
   - Log into Outline at http://100.123.154.40:8000
   - Click your profile → Settings
   - Go to "API Tokens" section
   - Click "Create a token"
   - Give it a name like "Import Script"
   - Copy the token (it looks like: `ol_api_xxxxxxxxxxxxxxxxxxxxxxxx`)

2. **Configure the Import Script**
   ```bash
   # Edit the import script
   nano scripts/import-markdown.sh

   # Find this line and paste your API token:
   API_TOKEN="ol_api_xxxxxxxxxxxxxxxxxxxxxxxx"

   # Optionally change the source directory (default: /mnt/boston/media/notes)
   SOURCE_DIR="/mnt/boston/media/notes"
   ```

3. **Place Your Markdown Files**
   ```bash
   # Copy your .md files to the import directory
   cp /path/to/your/notes/*.md /mnt/boston/media/notes/
   ```

4. **Run the Import**
   ```bash
   cd /home/brandon/projects/docker/outline
   ./scripts/import-markdown.sh
   ```

### What Happens During Import

- Creates a collection called "Imported Notes" (or uses existing one)
- Each `.md` file becomes a document in Outline
- Filename (without .md) becomes the document title
- Markdown formatting is preserved
- Documents are automatically published

### Import Tips

- **File naming**: Use descriptive filenames as they become document titles
- **Subdirectories**: The script only imports from the top-level directory
- **Large files**: Very large files may take longer to import
- **Duplicates**: Running the script again will create duplicate documents

## 💾 Backing Up Your Outline Data

### Manual Backup

```bash
cd /home/brandon/projects/docker/outline
./scripts/backup-outline.sh
```

This creates a backup in `/mnt/boston/media/backups/outline/YYYYMMDD_HHMMSS/` containing:

1. **database.sql.gz** - Complete database (all documents, users, settings)
2. **minio-storage.tar.gz** - All uploaded files, images, attachments
3. **docker-compose.yml** - Your configuration
4. **markdown-export/** - All documents as `.md` files (requires API token)

### Enable Markdown Export in Backups

To also export all documents as readable `.md` files during backup:

```bash
# Edit the backup script
nano scripts/backup-outline.sh

# Find this line and add your API token:
API_TOKEN="ol_api_xxxxxxxxxxxxxxxxxxxxxxxx"
```

Now backups will include a `markdown-export/` folder with all your documents organized by collection.

### Automated Daily Backups

Set up automatic backups every day at 2 AM:

```bash
# Open crontab editor
crontab -e

# Add this line:
0 2 * * * cd /home/brandon/projects/docker/outline && ./scripts/backup-outline.sh >> /var/log/outline-backup.log 2>&1

# Save and exit
```

Check backup logs:
```bash
tail -f /var/log/outline-backup.log
```

### Backup Retention

Backups can grow large over time. To keep only the last 7 days:

```bash
# Add to crontab (runs daily at 3 AM)
0 3 * * * find /mnt/boston/media/backups/outline/ -type d -mtime +7 -exec rm -rf {} +
```

## 🔄 Restoring from Backup

### Full Restore

To restore everything from a backup:

```bash
cd /home/brandon/projects/docker/outline

# List available backups
ls -lh /mnt/boston/media/backups/outline/

# Restore from a specific backup
./scripts/restore-outline.sh /mnt/boston/media/backups/outline/20260119_143000
```

**⚠️ Warning**: This will **replace all current data**!

### Partial Restore (Database Only)

If you only need to restore the database:

```bash
# Stop Outline
docker-compose stop outline

# Restore database
gunzip -c /mnt/boston/media/backups/outline/20260119_143000/database.sql.gz | \
  docker exec -i outline_postgres psql -U outline outline

# Restart Outline
docker-compose start outline
```

### Partial Restore (Files Only)

If you only need to restore uploaded files:

```bash
# Stop Outline
docker-compose stop outline

# Backup current files (just in case)
mv ./data/minio ./data/minio.backup

# Restore files
tar -xzf /mnt/boston/media/backups/outline/20260119_143000/minio-storage.tar.gz -C ./data/

# Restart Outline
docker-compose start outline
```

## 📁 Accessing Your Data Remotely

### Option 1: Use Outline's Web Interface
- Access from any device: http://100.123.154.40:8000
- Works on mobile, tablet, desktop
- Full editing capabilities

### Option 2: Use the Markdown Exports
If you enabled markdown export in backups:

```bash
# Latest markdown export is in the most recent backup
cd /mnt/boston/media/backups/outline/

# Find the latest backup
ls -lt | head -5

# Access the markdown files
cd 20260119_143000/markdown-export/
```

You can:
- Read these files with any text editor
- Sync them to other devices
- Edit them (but changes won't sync back to Outline)

### Option 3: Use the API
For programmatic access:

```bash
# Get all documents
curl -X POST http://100.123.154.40:8000/api/documents.list \
  -H "Authorization: Bearer YOUR_API_TOKEN" \
  -H "Content-Type: application/json"
```

See [Outline API docs](https://www.getoutline.com/developers) for more.

## 🔍 Troubleshooting

### Import Script Issues

**"API_TOKEN is not set"**
- You need to generate an API token in Outline first
- Edit `import-markdown.sh` and set the `API_TOKEN` variable

**"Collection not found"**
- The script will automatically create the collection
- Check that your API token has the correct permissions

**Import fails for some files**
- Check file encoding (should be UTF-8)
- Very large files may timeout
- Special characters in filenames may cause issues

### Backup Script Issues

**"Permission denied"**
- Make sure scripts are executable: `chmod +x *.sh`
- You may need sudo for some operations

**Backup directory doesn't exist**
- Create it: `mkdir -p /mnt/boston/media/backups/outline`

**Database backup fails**
- Ensure PostgreSQL container is running: `docker ps | grep postgres`
- Check database credentials in the script match docker-compose.yml

### Restore Issues

**"Database restore failed"**
- Make sure Outline is stopped first
- Check that the backup file is not corrupted: `gunzip -t backup.sql.gz`

**Outline won't start after restore**
- Check logs: `docker logs outline`
- Database may need migrations: wait a few minutes
- Try restarting: `docker-compose restart outline`

