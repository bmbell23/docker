# 🔐 How to Login to Deemix

Deemix doesn't use regular username/password login. Instead, you need to get your **ARL token** from Deezer.

## 📝 Step-by-Step Guide

### Step 1: Log into Deezer

1. Go to [deezer.com](https://www.deezer.com/)
2. Log in with your account (the one you just created)

### Step 2: Get Your ARL Token

**Option A: Using Browser Developer Tools (Chrome/Edge/Brave)**

1. While logged into Deezer, press **F12** (or right-click → Inspect)
2. Click the **Application** tab (or **Storage** tab in Firefox)
3. In the left sidebar, expand **Cookies**
4. Click on **https://www.deezer.com**
5. Look for a cookie named **arl**
6. Copy the **Value** (it's a long string of letters and numbers)

**Option B: Using Firefox**

1. While logged into Deezer, press **F12**
2. Click the **Storage** tab
3. Expand **Cookies** in the left sidebar
4. Click on **https://www.deezer.com**
5. Find the **arl** cookie
6. Copy the **Value**

### Step 3: Add ARL to Deemix

1. Open Deemix web interface: **http://dockerhost:6595**
2. Click the **settings icon** (⚙️) in the top right
3. Scroll down to the **Login** section
4. Paste your ARL token into the **ARL** field
5. Click **Save** or **Login**

### Step 4: Test It

1. Go back to the main Deemix page
2. Try searching for a song or pasting a Deezer/Spotify link
3. If it works, you're all set!

## ⚠️ Important Notes

- **Free accounts work!** You don't need Deezer Premium
- The ARL token expires after a while (weeks/months)
- When it expires, just get a new one using the same steps
- Don't share your ARL token - it's like a password
- If downloads fail, your ARL might have expired - get a new one

## 🔄 If Your ARL Expires

You'll know your ARL expired if:
- Downloads suddenly stop working
- You get "not authorized" errors
- Deemix says you're not logged in

**Solution:** Just repeat Steps 1-3 above to get a fresh ARL token.

## 💡 Quality Settings

Once logged in, you can set download quality:

1. Click settings (⚙️)
2. Under **Download Settings**, choose:
   - **FLAC** - Lossless (best quality, ~30-50MB per song)
   - **MP3 320kbps** - High quality (recommended, ~8-12MB per song)
   - **MP3 128kbps** - Smaller files (~3-5MB per song)

## 🎵 Ready to Download!

Once you have your ARL set up:
- Paste any Deezer or Spotify URL
- Click download
- Files go to `/mnt/boston/media/music/`
- No rate limits!

