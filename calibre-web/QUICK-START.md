# Calibre-Web Quick Start Guide

## 🚀 Access Your Library

**Web UI:** http://localhost:8083

## 🔐 First Login

**Default credentials:**
- Username: `admin`
- Password: `admin123`

**⚠️ CHANGE THE PASSWORD IMMEDIATELY!**

## ⚙️ Initial Setup (REQUIRED)

### 1. Configure Database Location
1. After logging in, click **"Admin"** (top right)
2. Click **"Basic Configuration"**
3. Under "Location of Calibre database", enter: `/books`
4. Click **"Save"**
5. Restart the container:
   ```bash
   cd ~/projects/docker/calibre-web
   docker compose restart
   ```

### 2. Wait for Book Scan
- Calibre-Web will automatically scan `/books` and create a database
- This may take a minute depending on how many books you have
- Refresh the page and your books should appear!

## 📱 Connect Mobile Apps (OPDS)

### OPDS Feed URL
```
http://YOUR_SERVER_IP:8083/opds
```

### Recommended Apps
- **Moon+ Reader** (Android) - Best overall
- **FBReader** (Android/iOS) - Free
- **KOReader** (Android) - Open source

### Setup Example (Moon+ Reader)
1. Open Moon+ Reader
2. Go to **"Net Library"** → **"Add"**
3. Select **"OPDS Catalog"**
4. Enter:
   - Name: `My Books`
   - URL: `http://YOUR_SERVER_IP:8083/opds`
   - Username: `admin` (or your username)
   - Password: (your password)
5. Browse and download books!

## 📚 Your Books

Your books are located at:
```
/mnt/boston/media/books/
├── fiction/          (EPUBs)
├── Non-fiction/      (PDFs)
└── Academic/         (PDFs)
```

## 🎯 Quick Tips

- **Read in browser:** Click any EPUB to read it directly
- **Download:** Click the download icon to save to your device
- **Search:** Use the search bar to find books by title/author
- **Send to Kindle:** Configure email in settings (optional)

## 🛠️ Useful Commands

```bash
# View logs
docker compose logs -f

# Restart
docker compose restart

# Stop
docker compose down

# Update
docker compose pull && docker compose up -d
```

---

**Enjoy your ebook library!** 📖✨

