# Testing Libby Chip Status - Quick Reference

## Check Current Chip Status

```bash
cd /home/brandon/projects/docker

python3 << 'EOF'
import urllib3; urllib3.disable_warnings()
from odmpy.libby import LibbyClient
import jwt

client = LibbyClient(settings_folder='libby/settings', logger=None)
client.libby_session.verify = False

# Decode the JWT token to see chip details
token = client.libby_session.headers.get('Authorization', '').replace('Bearer ', '')
payload = jwt.decode(token, options={'verify_signature': False})

print("=== CHIP STATUS ===")
print(f"Chip ID: {payload.get('chip', {}).get('id')}")
print(f"Patron Borrowing (prbn): {payload.get('chip', {}).get('prbn')}")
print(f"  'm' = Mobile/Full (can download)")
print(f"  'l' = Limited (cannot download)")
print()

# Test if we can download
print("=== TESTING DOWNLOAD CAPABILITY ===")
# Get a current loan to test with
sync = client.make_request('chip/sync')
loans = sync.get('loans', [])
if loans:
    loan = loans[0]
    loan_id = str(loan.get('id'))
    card_id = str(loan.get('cardId'))
    print(f"Testing with loan: {loan.get('title')}")
    print(f"  Loan ID: {loan_id}, Card ID: {card_id}")
    
    try:
        from odmpy.libby import LibbyFormats
        acsm = client.fulfill_loan_file(loan_id, card_id, LibbyFormats.EBookEPubAdobe)
        print(f"✅ SUCCESS! Downloaded ACSM ({len(acsm)} bytes)")
        print(f"   Chip has full download access!")
    except Exception as e:
        error = str(e)
        if '403' in error or 'Forbidden' in error:
            print(f"❌ FAILED: 403 Forbidden")
            print(f"   Chip has limited (prbn:'l') status")
        else:
            print(f"❌ FAILED: {error}")
else:
    print("No active loans to test with. Borrow a book first.")
EOF
```

## Re-clone Chip from Mobile (If Limited)

If the chip shows `prbn:'l'`, try re-cloning from mobile:

### Step 1: Backup Current Settings
```bash
cp libby/settings/libby.json libby/settings/libby.json.backup
```

### Step 2: Delete Current Chip
```bash
rm libby/settings/libby.json
```

### Step 3: Clone from Mobile
1. Open Libby app on your phone
2. Go to Settings → "Copy to Another Device"
3. A 8-digit code appears
4. On the server:
```bash
cd /home/brandon/projects/docker
python3 << 'EOF'
from odmpy.libby import LibbyClient

code = input("Enter 8-digit code from mobile app: ")
client = LibbyClient(settings_folder='libby/settings', logger=None, setup_mode=True)
client.clone_by_code(code)
print("✓ Cloned successfully!")
EOF
```

### Step 4: Re-run Status Check
Run the status check script above. If `prbn` is still `'l'`, the mobile clone didn't help.

## Test Download with Working Chip

If chip shows `prbn:'m'`:

```bash
python3 << 'EOF'
import urllib3; urllib3.disable_warnings()
from odmpy.libby import LibbyClient, LibbyFormats

client = LibbyClient(settings_folder='libby/settings', logger=None)
client.libby_session.verify = False

# Find an available book
import requests
r = requests.get('https://thunder.api.overdrive.com/v2/libraries/ppld/media?query=nora+roberts&mediaTypes=ebook&languages=en&perPage=5', verify=False)
items = r.json().get('items', [])
available = next((i for i in items if i.get('isAvailable')), None)

if not available:
    print("No available books found in search")
    exit(1)

title_id = str(available['id'])
title = available['title']
print(f"Testing with: {title} (ID: {title_id})")

# Get a PPLD card
sync = client.make_request('chip/sync')
ppld_card = next((c for c in sync.get('cards', []) if 'ppld' in c.get('advantageKey', '').lower()), None)
if not ppld_card:
    print("No PPLD card found")
    exit(1)

card_id = str(ppld_card['cardId'])
print(f"Using card: {ppld_card['library']['name']} ({card_id})")

# Borrow
print("Borrowing...")
client.make_request(f'card/{card_id}/loan/{title_id}', method='POST',
                    json_data={'period': 14, 'units': 'days', 'lucky_day': None,
                               'title_format': 'ebook-epub-adobe'})

# Download
print("Downloading ACSM...")
acsm = client.fulfill_loan_file(title_id, card_id, LibbyFormats.EBookEPubAdobe)
print(f"✅ Got ACSM file ({len(acsm)} bytes)")

# Save to watch folder
watch_folder = '/mnt/boston/media/downloads/books'
filename = f"{watch_folder}/{title.replace('/', '-')[:50]}.acsm"
with open(filename, 'wb') as f:
    f.write(acsm)
print(f"✅ Saved to: {filename}")
print("Watch folder will auto-import in ~30 seconds")

# Return
print("Returning loan...")
client.make_request(f'card/{card_id}/loan/{title_id}', method='DELETE', return_res=True)
print("✅ Complete! Check Calibre in 1 minute.")
EOF
```

## Update libby-web/app.py If Working

If the download test above works, update `api_download()` in `libby-web/app.py`:

```python
# Replace Playwright section with:
try:
    # Borrow
    client.make_request(
        f"card/{card_id}/loan/{title_id}", method="POST",
        json_data={"period": 14, "units": "days", "lucky_day": None,
                   "title_format": "ebook-epub-adobe"},
    )
    
    # Download ACSM directly via API
    from odmpy.libby import LibbyFormats
    acsm_bytes = client.fulfill_loan_file(title_id, card_id, LibbyFormats.EBookEPubAdobe)
    
    # Save to watch folder
    filename = f"{title[:50].replace('/', '-')}-{title_id}.acsm"
    dest = WATCH_DIR / filename
    dest.write_bytes(acsm_bytes)
    
    # Return loan
    client.make_request(f"card/{card_id}/loan/{title_id}", method="DELETE", return_res=True)
    
    return jsonify({"success": True, "filename": filename})
except Exception as e:
    # Cleanup
    try:
        client.make_request(f"card/{card_id}/loan/{title_id}", method="DELETE")
    except:
        pass
    return jsonify({"error": str(e)}), 500
```

Then rebuild and restart:
```bash
cd libby-web
docker compose build --no-cache
docker rm -f libby-web
docker compose up -d
```
