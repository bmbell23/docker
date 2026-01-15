# Calibre-Web - Ebook Metadata Management & OPDS Server

Calibre-Web is a web-based ebook library manager with excellent metadata editing and OPDS support for mobile readers like Moon+ Reader Pro.

## Features
- 📚 Manage ebook metadata (covers, authors, series, tags, descriptions)
- 🔍 Automatic metadata fetching from Google Books, Goodreads, etc.
- 📡 OPDS server for mobile reading apps (Moon+ Reader Pro, etc.)
- 🏷️ Tag and organize your library
- 👥 Multi-user support
- 📖 Built-in web reader (optional - not needed if using Moon+ Reader)

## Quick Start

### 1. Create required directories
```bash
mkdir -p /home/brandon/calibre-web/config
```

### 2. Create .env file
```bash
cd /home/brandon/projects/docker/calibre-web
cp .env.template .env
```

### 3. Start the container
```bash
docker compose up -d
```

### 4. Wait for Calibre tools to install
The first startup takes ~2 minutes because it installs Calibre tools via DOCKER_MODS.

Check logs:
```bash
docker compose logs -f
```

Wait until you see: `[services.d] done.`

### 5. Initialize Calibre Database

**IMPORTANT**: Calibre-Web needs a Calibre database (metadata.db) to work. We'll create one:

```bash
# Create the database pointing to your books directory
docker exec calibre-web calibredb add --empty --library-path /books
```

This creates `/mnt/boston/media/books/metadata.db` which tracks all your books.

### 6. Access Web Interface

Open: http://localhost:8083

**Default credentials:**
- Username: `admin`
- Password: `admin123`

**CHANGE THESE IMMEDIATELY!**

### 7. Configure Calibre-Web

1. On first login, it will ask for the Calibre library location
2. Enter: `/books`
3. Click "Save"
4. Calibre-Web will scan your books and import them into the database

### 8. Import Existing Books

If you have books already in `/mnt/boston/media/books`, import them:

```bash
# Add all books in the directory to the database
docker exec calibre-web calibredb add -r /books --library-path /books
```

Or use the web interface: Admin → Import Books

## OPDS Setup for Moon+ Reader Pro

### Enable OPDS in Calibre-Web:
1. Go to Admin → Basic Configuration → Feature Configuration
2. Enable "Enable OPDS"
3. Save

### Connect Moon+ Reader Pro:
1. Open Moon+ Reader Pro
2. Go to: My Shelf → Net Library → Add
3. Enter:
   - **Type**: OPDS
   - **Name**: My Books (or whatever you want)
   - **URL**: `http://YOUR_SERVER_IP:8083/opds`
   - **Username**: your calibre-web username
   - **Password**: your calibre-web password
4. Save

Now you can browse and download books directly in Moon+ Reader!

## Metadata Editing

### Edit metadata in web interface:
1. Click on any book
2. Click "Edit Metadata"
3. Edit title, author, series, tags, description, cover, etc.
4. Click "Save"

### Fetch metadata automatically:
1. Click on a book
2. Click "Get Metadata"
3. Select source (Google, Goodreads, etc.)
4. Review and apply

## Management Commands

```bash
# Start Calibre-Web
docker compose up -d

# Stop Calibre-Web
docker compose down

# View logs
docker compose logs -f

# Restart (after config changes)
docker compose restart

# Update to latest version
docker compose pull
docker compose up -d

# Add books via command line
docker exec calibre-web calibredb add /books/somebook.epub --library-path /books

# List all books
docker exec calibre-web calibredb list --library-path /books
```

## Troubleshooting

### "Database not found" error
Make sure you initialized the database:
```bash
docker exec calibre-web calibredb add --empty --library-path /books
```

### Books not showing up
Import them:
```bash
docker exec calibre-web calibredb add -r /books --library-path /books
```

### OPDS not working
1. Make sure OPDS is enabled in Feature Configuration
2. Check the URL is correct: `http://YOUR_IP:8083/opds`
3. Make sure you're using valid credentials

## Notes

- Books are stored at `/mnt/boston/media/books` (same as Kavita)
- Calibre-Web and Kavita can coexist - they both read the same files
- The metadata.db file is created in the books directory
- Config/settings are stored in `/home/brandon/calibre-web/config`

