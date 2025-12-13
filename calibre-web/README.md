# Calibre-Web - Ebook Library Manager

A web-based ebook library manager and reader with mobile app support.

## 📚 What This Does

- **Web-based ebook library** - Browse and manage your ebook collection
- **Built-in EPUB reader** - Read books directly in your browser
- **PDF viewer** - View PDFs without downloading
- **OPDS feed** - Connect mobile reading apps to your library
- **Send to Kindle** - Email books directly to your Kindle
- **Metadata management** - Edit book info, covers, tags, series
- **Multi-format support** - EPUB, PDF, MOBI, AZW3, CBR, CBZ, and more

## 🚀 Quick Start

### 1. Create config directory
```bash
mkdir -p /home/brandon/calibre-web/config
```

### 2. Start the service
```bash
cd ~/projects/docker/calibre-web
docker compose up -d
```

### 3. Access the web UI
Open your browser to: **http://localhost:8083**

### 4. Initial Setup

**First login:**
- Username: `admin`
- Password: `admin123`

**IMPORTANT: Change the password immediately!**

**Configure the database location:**
1. Click "Admin" → "Basic Configuration"
2. Set "Location of Calibre database" to: `/books`
3. Click "Save"
4. Restart the container: `docker compose restart`

The app will scan your books and create a database automatically.

## 📱 Mobile Apps (OPDS Support)

Connect your mobile reading apps to access your library:

### OPDS Feed URL
```
http://YOUR_SERVER_IP:8083/opds
```

### Recommended Android Apps
- **Moon+ Reader** - Best overall, excellent OPDS support
- **FBReader** - Free and open source
- **KOReader** - Powerful, open source
- **Librera** - Great UI, feature-rich

### Setup in Moon+ Reader
1. Open Moon+ Reader
2. Go to "Net Library" → "Add"
3. Select "OPDS Catalog"
4. Enter:
   - Name: `My Books`
   - URL: `http://YOUR_SERVER_IP:8083/opds`
   - Username: (your Calibre-Web username)
   - Password: (your Calibre-Web password)
5. Browse and download books directly to your phone!

## 📖 Features

### Reading
- **In-browser EPUB reader** - Beautiful, responsive reader
- **PDF viewer** - Read PDFs without downloading
- **Download books** - Grab files for offline reading
- **Send to Kindle** - Email books to your Kindle (requires email config)

### Library Management
- **Metadata editing** - Edit titles, authors, tags, series
- **Cover management** - Upload custom covers
- **Series tracking** - Organize books in series
- **Tags and categories** - Organize your library
- **Search** - Find books by title, author, tag, etc.

### User Management
- **Multiple users** - Create accounts for family members
- **Permissions** - Control who can upload, edit, delete
- **Reading progress** - Track what you've read

## 🔧 Configuration

### Email (for Send to Kindle)
1. Go to "Admin" → "Edit Basic Configuration" → "E-Mail Server Settings"
2. Configure your SMTP settings
3. Add your Kindle email in your user profile

### Upload Books
1. Go to "Admin" → "Edit Basic Configuration" → "Feature Configuration"
2. Enable "Enable Uploads"
3. Upload books via the web UI

**Note:** Your books directory is mounted read-only for safety. To add books:
- Upload via the web UI (they'll go to `/config/uploads`)
- Or manually copy to `/mnt/boston/media/books/` and restart the container

## 📂 Directory Structure

```
/home/brandon/calibre-web/
├── config/              # Database, user settings, uploaded books
└── /mnt/boston/media/books/  # Your ebook library (read-only)
    ├── fiction/
    ├── Non-fiction/
    └── Academic/
```

## 🛠️ Useful Commands

```bash
# View logs
docker compose logs -f

# Restart service
docker compose restart

# Stop service
docker compose down

# Update to latest version
docker compose pull
docker compose up -d
```

## 🌐 Access Points

- **Web UI:** http://localhost:8083
- **OPDS Feed:** http://localhost:8083/opds
- **Admin Panel:** http://localhost:8083/admin

## 📝 Notes

- Books directory is mounted **read-only** to prevent accidental changes
- Database is created automatically on first scan
- Supports multiple ebook formats: EPUB, PDF, MOBI, AZW3, CBR, CBZ, TXT
- OPDS feed works with most mobile reading apps
- Can send books to Kindle via email (requires SMTP setup)

## 🔒 Security

- Change default admin password immediately
- Consider setting up reverse proxy with HTTPS for remote access
- Use strong passwords for all users
- Limit upload permissions to trusted users

---

**Enjoy your personal ebook library!** 📚✨

