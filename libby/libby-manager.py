#!/usr/bin/env python3
"""
libby-manager.py — Command-line manager for Overdrive/Libby loans.

Uses odmpy's LibbyClient to authenticate, list, download, and return loans.
Downloaded .acsm files are placed into the Calibre watch folder so the
existing acsm-watcher pipeline picks them up automatically.

Authentication (first time):
  1. Open the Libby app on your phone
  2. Menu → Get Card → Copy to Another Device → note the 8-digit code
  3. Run: python3 libby-manager.py setup

Commands:
  setup               Authenticate via 8-digit Libby setup code
  status              Show auth status and loan/hold counts
  loans               List active loans as JSON
  holds               List active holds as JSON
  download <loan-id>  Download ebook .acsm to the Calibre watch folder
  return <loan-id>    Return a loan
  borrow <title-id> <card-id>  Borrow a title (if available)
"""

import json
import os
import re
import sys
from pathlib import Path

SETTINGS_DIR = Path(__file__).parent / "settings"
WATCH_DIR = Path("/mnt/boston/media/downloads/books")

# ---------------------------------------------------------------------------
# Bootstrap: verify odmpy is installed
# ---------------------------------------------------------------------------
try:
    from odmpy.libby import LibbyClient, LibbyFormats
except ImportError:
    print("ERROR: odmpy is not installed.")
    print("Install with:  pip3 install 'git+https://github.com/ping/odmpy.git' --break-system-packages")
    sys.exit(1)


def get_client() -> LibbyClient:
    client = LibbyClient(settings_folder=str(SETTINGS_DIR))
    # OverDrive's sentry-read.svc.overdrive.com now presents a cert for
    # *.odrsre.overdrive.com — a hostname mismatch that Python 3.13's stricter
    # SSL rejects.  The endpoint is genuine (curl verifies fine), so we disable
    # Python's hostname check on this one session only.
    import urllib3
    urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
    client.libby_session.verify = False
    return client


def _search_libraries(query: str) -> list:
    """Search the OverDrive Thunder API for libraries by name."""
    import urllib.request, urllib.parse
    url = "https://thunder.api.overdrive.com/v2/libraries?" + urllib.parse.urlencode({
        "format": "json",
        "search": query,
        "perPage": 10,
    })
    req = urllib.request.Request(url, headers={"Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        import json
        return json.loads(r.read()).get("items", [])


def cmd_setup():
    """
    Authenticate directly with your library card number and PIN.
    No phone needed — no setup codes.
    """
    client = get_client()

    if client.has_chip() and client.identity.get("cards"):
        print("Already authenticated. Run 'status' to verify.")
        print("Delete libby/settings/libby.json to re-authenticate.")
        return

    print("Step 1: Getting identity chip from Libby API...")
    client.get_chip()
    print("  ✓ Chip obtained.\n")

    # Search for the library
    while True:
        query = input("Enter your library name (e.g. 'Seattle Public', 'NYPL'): ").strip()
        if not query:
            continue
        print(f"  Searching for '{query}'...")
        try:
            results = _search_libraries(query)
        except Exception as e:
            print(f"  Search failed: {e}")
            continue

        if not results:
            print("  No libraries found. Try a shorter or different search term.")
            continue

        print()
        for i, lib in enumerate(results, 1):
            print(f"  {i}. {lib['name']}  (key: {lib.get('preferredKey','?')}, websiteId: {lib['websiteId']})")
        print()

        choice = input(f"Enter number (1-{len(results)}) or 0 to search again: ").strip()
        if choice == "0":
            continue
        try:
            idx = int(choice) - 1
            if 0 <= idx < len(results):
                library = results[idx]
                break
        except ValueError:
            pass
        print("  Invalid choice.")

    website_id = str(library["websiteId"])
    print(f"\n  Selected: {library['name']} (websiteId: {website_id})")

    print("\nStep 2: Getting auth form for this library...")
    form = client.auth_form(website_id)
    # Pick the ILS — use the first form's ilsName
    forms = form if isinstance(form, list) else [form]
    ils = forms[0].get("ilsName", "default") if forms else "default"
    print(f"  ILS: {ils}\n")

    print("Step 3: Enter your library credentials:")
    username = input("  Library card number: ").strip()
    import getpass
    password = getpass.getpass("  PIN/Password: ")

    print("\nStep 4: Linking card to this device...")
    try:
        result = client.link_card(website_id=website_id, username=username,
                                  password=password, ils=ils)
        print("  Link result:", result.get("result", result))
    except Exception as e:
        print(f"  ERROR linking card: {e}")
        sys.exit(1)

    # Verify
    sync = client.sync()
    cards = sync.get("cards", [])
    loans = sync.get("loans", [])
    if cards:
        client.save_settings({"__libby_sync_code": "card-auth"})
        print(f"\n✓ Authenticated! {len(cards)} card(s), {len(loans)} active loan(s).")
        for card in cards:
            print(f"  - {card.get('advantageKey','?')} (card ID: {card.get('cardId','?')})")
    else:
        print("\nWARNING: Sync returned no cards. Check your credentials and try again.")


def cmd_status():
    """Show authentication status."""
    client = get_client()
    if not client.has_chip():
        print("Not authenticated. Run: python3 libby-manager.py setup")
        sys.exit(1)

    sync = client.sync()
    if sync.get("result") != "synchronized":
        print("Authentication problem — sync result:", sync.get("result"))
        sys.exit(1)

    cards = sync.get("cards", [])
    loans = sync.get("loans", [])
    holds = sync.get("holds", [])
    print(f"✓ Authenticated")
    print(f"  Cards : {len(cards)}")
    for card in cards:
        print(f"    - {card.get('advantageKey', '?')} (card ID: {card.get('cardId', '?')})")
    print(f"  Loans : {len(loans)}")
    print(f"  Holds : {len(holds)}")


def cmd_loans():
    """Print active loans as JSON."""
    client = get_client()
    loans = client.get_loans()
    simplified = []
    for loan in loans:
        formats = [f["id"] for f in loan.get("formats", [])]
        simplified.append({
            "id":       loan["id"],
            "card_id":  loan["cardId"],
            "title":    loan.get("title", ""),
            "author":   loan.get("firstCreatorName", ""),
            "type":     loan.get("type", {}).get("id", ""),
            "formats":  formats,
            "expires":  loan.get("expireDate", ""),
        })
    print(json.dumps(simplified, indent=2))


def cmd_holds():
    """Print active holds as JSON."""
    client = get_client()
    holds = client.get_holds()
    simplified = []
    for hold in holds:
        simplified.append({
            "id":           hold["id"],
            "card_id":      hold["cardId"],
            "title":        hold.get("title", ""),
            "author":       hold.get("firstCreatorName", ""),
            "type":         hold.get("type", {}).get("id", ""),
            "queue_position": hold.get("holdListPosition"),
            "available":    hold.get("isAvailable", False),
        })
    print(json.dumps(simplified, indent=2))


def _sanitize_filename(name: str) -> str:
    """Strip characters that are invalid in filenames."""
    return re.sub(r'[<>:"/\\|?*]', "", name).strip()


def cmd_download(loan_id: str):
    """Download an ebook loan as .acsm into the Calibre watch folder."""
    client = get_client()
    loans = client.get_loans()

    loan = next((l for l in loans if str(l["id"]) == str(loan_id)), None)
    if not loan:
        print(f"ERROR: No active loan found with ID '{loan_id}'")
        print("Active loan IDs:", [l["id"] for l in loans])
        sys.exit(1)

    # Determine format — prefer ebook-epub-adobe (produces .acsm)
    loan_format = None
    for fmt in (LibbyFormats.EBookEPubAdobe, LibbyFormats.EBookPDFAdobe):
        if LibbyClient.has_format(loan, fmt):
            loan_format = fmt
            break

    if not loan_format:
        print(f"ERROR: Loan '{loan['title']}' has no downloadable DRM ebook format.")
        print("Available formats:", [f["id"] for f in loan.get("formats", [])])
        sys.exit(1)

    title = _sanitize_filename(loan.get("title", loan_id))
    author = _sanitize_filename(loan.get("firstCreatorName", ""))
    ext = ".acsm"

    filename = f"{title} - {author}{ext}" if author else f"{title}{ext}"
    dest = WATCH_DIR / filename

    print(f"Downloading '{loan['title']}' as {loan_format} ...")
    data = client.fulfill_loan_file(loan_id=loan["id"], card_id=loan["cardId"], format_id=loan_format)

    WATCH_DIR.mkdir(parents=True, exist_ok=True)
    dest.write_bytes(data)
    print(f"✓ Saved to: {dest}")
    print("  The acsm-watcher will pick this up within 30 seconds and import it into Calibre.")


def cmd_return(loan_id: str):
    """Return a loan."""
    client = get_client()
    loans = client.get_loans()

    loan = next((l for l in loans if str(l["id"]) == str(loan_id)), None)
    if not loan:
        print(f"ERROR: No active loan found with ID '{loan_id}'")
        sys.exit(1)

    title = loan.get("title", loan_id)
    confirm = input(f"Return '{title}'? [y/N] ").strip().lower()
    if confirm != "y":
        print("Aborted.")
        return

    client.return_loan(loan)
    print(f"✓ Returned: {title}")


def cmd_borrow(title_id: str, card_id: str):
    """Borrow a title by title ID and card ID (IDs come from the OverDrive catalog)."""
    client = get_client()
    sync = client.sync()
    cards = {c["cardId"]: c for c in sync.get("cards", [])}
    if card_id not in cards:
        print(f"ERROR: Card '{card_id}' not found. Your cards:")
        for cid, card in cards.items():
            print(f"  {cid}: {card.get('advantageKey', '?')}")
        sys.exit(1)

    print(f"Borrowing title ID {title_id} on card {card_id} ...")
    result = client.borrow_title(title_id=title_id, title_format="ebook", card_id=card_id)
    print("✓ Borrowed:", json.dumps(result, indent=2))


# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------

COMMANDS = {
    "setup":    (cmd_setup,    0),
    "status":   (cmd_status,   0),
    "loans":    (cmd_loans,    0),
    "holds":    (cmd_holds,    0),
    "download": (cmd_download, 1),
    "return":   (cmd_return,   1),
    "borrow":   (cmd_borrow,   2),
}

if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] not in COMMANDS:
        print(__doc__)
        print("Commands:", ", ".join(COMMANDS))
        sys.exit(0)

    cmd_name = sys.argv[1]
    fn, nargs = COMMANDS[cmd_name]
    args = sys.argv[2:]

    if len(args) < nargs:
        print(f"ERROR: '{cmd_name}' requires {nargs} argument(s), got {len(args)}")
        sys.exit(1)

    fn(*args[:nargs])
