# MusicBrainz Picard - Music Metadata Editor

MusicBrainz Picard is a powerful music tagger with a full GUI for editing metadata. Access it through your web browser!

## Features
- 🎵 Full GUI for editing music metadata
- 🔍 Automatic lookup from MusicBrainz database
- 🖼️ Album art download and embedding
- 📝 Batch editing of multiple files
- 🎨 Visual interface - drag and drop files
- ✏️ Manual editing of all ID3 tags
- 🌐 Web-accessible via noVNC

## Quick Start

### 1. Start Picard
```bash
cd /home/brandon/projects/docker/picard
docker compose up -d
```

### 2. Access the GUI
Open your browser and go to:
- **Local:** http://localhost:5800
- **Network:** http://100.123.154.40:5800

You'll see the full Picard GUI in your browser!

### 3. Using Picard

**Basic Workflow:**
1. Click "Add Files" or "Add Folder" in the left panel
2. Navigate to `/music` and select files/folders to edit
3. Files appear in the left "Unclustered Files" section
4. Click "Cluster" to group files by album
5. Click "Lookup" to search MusicBrainz for metadata
6. Picard will match your files to the database
7. Drag matched files from left to right panel to accept
8. Edit any fields manually in the bottom panel
9. Click "Save" to write changes to files

**Manual Editing:**
- Select any file in the right panel
- Bottom panel shows all metadata fields
- Click any field to edit it directly
- Changes are highlighted in yellow
- Click "Save" to write to file

**Album Art:**
- Right-click on an album → "Cover Art" → "Choose from file browser"
- Or let Picard download it automatically from MusicBrainz

### 4. Trigger Navidrome Rescan

After editing metadata, force Navidrome to pick up changes:

```bash
# Option 1: Restart Navidrome (picks up changes immediately)
cd /home/brandon/projects/docker/navidrome
docker compose restart

# Option 2: Wait 5 minutes for automatic scan
# Navidrome scans every 5 minutes automatically
```

## Management Commands

```bash
# Start Picard
docker compose up -d

# Stop Picard
docker compose down

# View logs
docker compose logs -f

# Restart Picard
docker compose restart

# Update to latest version
docker compose pull
docker compose up -d
```

## Tips

### Keyboard Shortcuts
- **Ctrl+O** - Add files
- **Ctrl+S** - Save changes
- **Ctrl+Shift+S** - Save all
- **Delete** - Remove from list

### Best Practices
1. **Work on copies first** if you're new to Picard
2. **Use "Lookup in Browser"** if automatic matching fails
3. **Check the bottom panel** before saving to verify changes
4. **Save frequently** - changes aren't written until you click Save
5. **Use Cluster** before Lookup for better matching

### Common Tasks

**Fix split albums:**
1. Select all tracks from the same album
2. Right-click → "Lookup in Browser"
3. Find the correct release on MusicBrainz
4. Drag the tagger icon to Picard

**Batch edit artist name:**
1. Select multiple files
2. Bottom panel shows editable fields
3. Change "Artist" field
4. Click "Save"

**Add album art:**
1. Select album in right panel
2. Right-click → "Cover Art" → "Choose from file browser"
3. Select image file
4. Click "Save"

## Troubleshooting

### Can't access web interface
- Verify container is running: `docker ps | grep picard`
- Check port 5800 is not in use: `sudo netstat -tlnp | grep 5800`
- Check logs: `docker compose logs`

### Changes not showing in Navidrome
- Wait 5 minutes for automatic scan, or restart Navidrome
- Check that files were actually saved (look at file modification time)
- Verify Navidrome has read access to the music files

### Picard can't find matches
- Try "Lookup in Browser" for manual search
- Check that files have some existing metadata
- Use "Scan" instead of "Lookup" for acoustic fingerprinting (slower but more accurate)

## Security Notes

- Default VNC password is "picard" - change it in docker-compose.yml
- Picard has **write access** to your music library
- Consider putting behind reverse proxy for HTTPS if accessing remotely
- Limit port exposure if accessible from internet

## Links
- Official Docs: https://picard.musicbrainz.org/docs/
- MusicBrainz Database: https://musicbrainz.org/
- Docker Image: https://github.com/mikenye/docker-picard

