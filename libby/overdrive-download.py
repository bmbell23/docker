#!/usr/bin/env python3
"""
overdrive-download.py — download an ACSM from OverDrive using Playwright.

Usage:
    python3 overdrive-download.py <library_key> <card_number> <pin> <title_id> [output_dir]

Example:
    python3 libby/overdrive-download.py ppld 420754455 0523 12008387 /mnt/boston/media/downloads/books

Outputs a JSON line: {"success": true, "path": "..."}  or  {"success": false, "error": "..."}
"""

import sys
import json
from pathlib import Path
from playwright.sync_api import sync_playwright

DEFAULT_OUTPUT = "/mnt/boston/media/downloads/books"
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
      "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36")


def log(msg):
    print(f"[overdrive-dl] {msg}", flush=True)


def download_acsm(library_key: str, card_number: str, pin: str,
                  title_id: str, output_dir: str = DEFAULT_OUTPUT) -> str:
    """
    Log in to {library_key}.overdrive.com, download the ACSM for title_id,
    save it to output_dir, and return the saved file path.
    """
    output_path = Path(output_dir)
    output_path.mkdir(parents=True, exist_ok=True)

    base_url = f"https://{library_key}.overdrive.com"
    signin_url = f"{base_url}/account/ozone/sign-in?forward=%2F"
    media_url = f"{base_url}/media/{title_id}"
    download_url = f"{base_url}/media/download/ebook-epub-adobe/{title_id}"

    with sync_playwright() as p:
        browser = p.chromium.launch(headless=True)
        ctx = browser.new_context(accept_downloads=True, user_agent=UA)
        page = ctx.new_page()

        # ── 1. Sign in ───────────────────────────────────────────────────────
        log(f"Signing in to {base_url}…")
        page.goto(signin_url, wait_until="domcontentloaded", timeout=45_000)
        page.wait_for_timeout(2_000)

        # Handle library selection if it appears
        if "select-library" in page.url.lower() or page.query_selector("select"):
            log("Library selection page detected.")
            try:
                # Try to select the first option that isn't the placeholder
                page.select_option("select", index=1)
                page.keyboard.press("Enter")
                page.wait_for_load_state("networkidle", timeout=15_000)
            except Exception as e:
                log(f"Warning: Library selection failed (might be okay if already selected): {e}")

        # Try the standard username/password form (be more flexible for different OverDrive sites)
        username_sels = [
            "input[name='username']",
            "input[name='cardnumber']", 
            "input[name='LibraryCard']",
            "input[type='email']",
            "input[placeholder*='card' i]",
            "input[placeholder*='email' i]",
            "input:not([type='checkbox']):not([type='hidden'])",  # First non-checkbox input
        ]
        password_sels = [
            "input[name='password']",
            "input[name='pin']",
            "input[name='PIN']",
            "input[type='password']",
            "input[placeholder*='password' i]",
            "input[placeholder*='pin' i]",
        ]
        
        username_input = None
        password_input = None
        form_debug = []
        
        # Try to find username input
        for sel in username_sels:
            try:
                elm = page.locator(sel).first
                if elm.is_visible(timeout=1_000):
                    username_input = elm
                    log(f"Found username field: {sel}")
                    break
            except:
                pass
        
        if not username_input:
            # Debug: show what inputs are on the page
            all_inputs = page.locator("input").all()
            for inp in all_inputs[:10]:
                form_debug.append(f"  input name={inp.get_attribute('name')} type={inp.get_attribute('type')} placeholder={inp.get_attribute('placeholder')}")
            debug_msg = "Could not find username field. Inputs on page:\n" + "\n".join(form_debug)
            raise Exception(f"Could not find sign-in form on {base_url}: {debug_msg}")
        
        # Fill username and wait for password field to appear
        username_input.fill(card_number)
        log(f"Filled username, waiting for password field...")
        page.wait_for_timeout(1_000)
        
        # Now try to find password input (it may have appeared dynamically)
        for sel in password_sels:
            try:
                elm = page.locator(sel).first
                if elm.is_visible(timeout=5_000):
                    password_input = elm
                    log(f"Found password field: {sel}")
                    break
            except:
                pass
        
        if not password_input:
            # Debug: show what inputs are on the page NOW
            all_inputs = page.locator("input").all()
            form_debug = []
            for inp in all_inputs[:15]:
                form_debug.append(f"  input name={inp.get_attribute('name')} type={inp.get_attribute('type')} placeholder={inp.get_attribute('placeholder')}")
            debug_msg = "Could not find password field after filling username. Inputs on page now:\n" + "\n".join(form_debug)
            raise Exception(debug_msg)
        
        password_input.fill(pin)

        # Click the sign-in button (try multiple labels)
        signed_in = False
        for label in ["Sign In", "Sign in", "Log In", "Login", "Submit"]:
            try:
                # First try finding by text on buttons/inputs
                btn = page.locator(f"button:has-text('{label}'), input[value='{label}']").first
                if btn.is_visible(timeout=1_000):
                    btn.click()
                    signed_in = True
                    break
            except Exception:
                pass
        
        if not signed_in:
            log("No named sign-in button found, pressing Enter...")
            page.keyboard.press("Enter")

        # Wait for navigation away from the sign-in page
        try:
            page.wait_for_url(lambda url: "sign-in" not in url.lower() and "login" not in url.lower(),
                              timeout=30_000)
        except Exception:
            # Fallback: just wait for the page to settle
            page.wait_for_load_state("domcontentloaded", timeout=15_000)
            page.wait_for_timeout(2_000)
            # If we're still on the login page, sign-in failed
            if page.query_selector(username_sel):
                raise Exception(f"Sign-in failed for {library_key}.overdrive.com — check credentials")
        log("Signed in.")

        # Dismiss any "Card error" or stale-card popups that may appear after login
        for dismiss_text in ["Cancel", "Close", "×"]:
            try:
                btn = page.get_by_role("button", name=dismiss_text).first
                if btn.is_visible(timeout=3_000):
                    btn.click()
                    log(f"Dismissed popup ({dismiss_text!r})")
                    page.wait_for_timeout(500)
                    break
            except Exception:
                pass

        # ── 2. Borrow via OverDrive website ──────────────────────────────────
        # (Libby API borrow doesn't sync to OverDrive website)
        log(f"Navigating to media page to borrow...")
        page.goto(media_url, wait_until="domcontentloaded", timeout=20_000)
        page.wait_for_timeout(2_000)

        # Click the Borrow button
        # Try different selectors for the Borrow button/link
        borrow_selectors = [
            "a:has-text('BORROW')", "button:has-text('BORROW')",
            "a:has-text('Borrow')", "button:has-text('Borrow')"
        ]
        
        borrow_btn = None
        for selector in borrow_selectors:
            try:
                btn = page.locator(selector).first
                if btn.is_visible(timeout=2_000):
                    borrow_btn = btn
                    break
            except:
                continue

        if borrow_btn:
            log(f"Clicking first Borrow button ({borrow_btn.inner_text().strip()})...")
            borrow_btn.click()
            page.wait_for_timeout(3_000)
            
            # Find the confirmation button
            # Usually there are now TWO "Borrow" buttons visible:
            # 1. The original one on the page (TitleAction)
            # 2. The new one in the modal (button-column)
            # The new one is usually the LAST one in the DOM among visible ones.
            confirm_btn = None
            try:
                all_visible_borrows = [
                    b for b in page.locator(", ".join(borrow_selectors)).all()
                    if b.is_visible()
                ]
                if len(all_visible_borrows) > 1:
                    # If more than one, pick the last one (likely the modal one)
                    confirm_btn = all_visible_borrows[-1]
                elif len(all_visible_borrows) == 1:
                    # If only one, it might be the same one or a direct borrow happened
                    # But if we saw a modal, there should be a new button.
                    # We'll check if its parent has modal-related classes if we want to be sure.
                    pass 
            except Exception as e:
                log(f"Error finding confirmation button: {e}")
            
            if confirm_btn:
                log(f"Clicking confirmation Borrow button ({confirm_btn.inner_text().strip()})...")
                confirm_btn.click()
                page.wait_for_timeout(4_000)
            else:
                log("No second Borrow button found - may have been a direct borrow")
        else:
            log("Borrow button not found - book may already be borrowed")

        # ── 3. Download ACSM from loans page ────────────────────────────────
        log(f"Navigating to loans page to download...")
        loans_url = f"{base_url}/account/loans"
        page.goto(loans_url, wait_until="domcontentloaded", timeout=20_000)
        page.wait_for_timeout(2_000)

        # Find the loan in the table by title_id or title
        # Look for a download button/link related to our media
        download_success = False
        
        try:
            with page.expect_download(timeout=30_000) as dl_info:
                # Try multiple strategies to trigger download:
                
                # Strategy 1: Look for a download link/button for this specific media
                # OverDrive usually has format selectors (dropdowns) next to each loan
                download_links = page.locator(f"[data-media-id='{title_id}']").all()
                
                if download_links:
                    log(f"Found {len(download_links)} element(s) with media ID")
                    # Look for download button/link within or near these elements
                    for elem in download_links:
                        try:
                            # Try to find a download or format selector
                            dl_btn = elem.locator("button:has-text('Download'), a:has-text('Download'), a:has-text('EPUB'), button:has-text('EPUB'), a:has-text('Adobe DRM')").first
                            if dl_btn.is_visible(timeout=2_000):
                                log(f"Clicking download button: {dl_btn.inner_text()[:30]}")
                                dl_btn.click()
                                download_success = True
                                break
                        except:
                            pass
                
                # Strategy 2: If no media-id selector worked, look for any download button on the loans page
                if not download_success:
                    log("Trying general download button search...")
                    # Look for download buttons that might be near our title
                    buttons = page.locator("button:has-text('Download'), a:has-text('Download'), [class*='download']").all()
                    for btn in buttons:
                        try:
                            if btn.is_visible(timeout=1_000):
                                txt = btn.inner_text()
                                if title_id in page.locator("div, tr").filter(has=btn).inner_text().upper() or \
                                   any(word in txt.lower() for word in ['download', 'epub', 'adobe']):
                                    log(f"Clicking download button: {txt[:30]}")
                                    btn.click()
                                    download_success = True
                                    break
                        except:
                            pass
                
                # If we did find and click a button, wait for download
                if download_success:
                    page.wait_for_timeout(2_000)
                else:
                    log("Warning: No download button found, trying direct download URL as fallback...")
                    page.goto(download_url, timeout=10_000)
            
            download = dl_info.value
            fname = download.suggested_filename or f"loan-{title_id}.acsm"
            dest = output_path / fname
            download.save_as(str(dest))
            log(f"Saved → {dest}")
            download_success = True
        except Exception as e:
            # Fallback: try direct URL one more time
            if not download_success:
                log(f"Download page method failed, trying direct URL: {e}")
                try:
                    with page.expect_download(timeout=15_000) as dl_info:
                        page.goto(download_url, timeout=10_000)
                    download = dl_info.value
                    fname = download.suggested_filename or f"loan-{title_id}.acsm"
                    dest = output_path / fname
                    download.save_as(str(dest))
                    log(f"Saved → {dest}")
                except Exception as e2:
                    raise Exception(f"Download page method and direct URL both failed. Last error: {e2}")

        browser.close()
        return str(dest)


if __name__ == "__main__":
    if len(sys.argv) < 5:
        print(__doc__)
        sys.exit(1)

    _, lib_key, card, pin_val, tid, *rest = sys.argv
    out = rest[0] if rest else DEFAULT_OUTPUT

    try:
        saved = download_acsm(lib_key, card, pin_val, tid, out)
        print(json.dumps({"success": True, "path": saved}))
    except Exception as e:
        print(json.dumps({"success": False, "error": str(e)}))
        sys.exit(1)
