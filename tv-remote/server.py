#!/usr/bin/env python3
"""TV remote (docker#189): a phone-sized page that drives the Roku over its External Control
Protocol (ECP, http://<roku>:8060, no auth on the LAN). Stdlib only.

  GET  /                     the remote page
  GET  /api/roku/apps        installed channels [{id, name}]
  POST /api/roku/key/<Key>   one keypress (allowlisted)
  POST /api/roku/launch/<id> open a channel
  POST /api/roku/text        body = text to type into the focused search box

Samsung is the next step: the TV isn't on the network yet (docker#189).
"""
import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROKU = os.environ.get("ROKU_URL", "http://10.0.0.97:8060")
HOST = os.environ.get("LISTEN_HOST", "0.0.0.0")
PORT = int(os.environ.get("PORT", "8020"))
PAGE = (Path(__file__).parent / "index.html").read_bytes()

# ECP key names the page may send; anything else is refused.
KEYS = {"Home", "Back", "Up", "Down", "Left", "Right", "Select", "Play", "Rev", "Fwd",
        "InstantReplay", "Info", "Backspace", "Search", "Enter", "VolumeUp", "VolumeDown",
        "VolumeMute", "PowerOn", "PowerOff", "Power", "InputHDMI1", "InputHDMI2", "InputHDMI3"}


def roku(method, path, timeout=5):
    req = urllib.request.Request(ROKU + path, method=method, data=b"" if method == "POST" else None)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return r.read()


def why(e):
    """Roku's own reason when it gives one (e.g. "ECP command not allowed in Limited mode.")."""
    body = e.read().decode("utf-8", "ignore").strip() if isinstance(e, urllib.error.HTTPError) else ""
    if "Limited mode" in body:
        body += " Fix on the Roku: Settings > System > Advanced system settings > Control by mobile apps > Network access: Default."
    return f"Roku said no: {body}" if body else f"Roku didn't answer ({type(e).__name__})"


def apps():
    root = ET.fromstring(roku("GET", "/query/apps"))
    return [{"id": a.get("id"), "name": a.text} for a in root.findall("app") if a.get("type") == "appl"]


class Handler(BaseHTTPRequestHandler):
    def reply(self, code, body=b"", ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self.reply(200, PAGE, "text/html; charset=utf-8")
        if self.path == "/health":
            return self.reply(200, b"ok")
        if self.path == "/api/roku/apps":
            try:
                return self.reply(200, json.dumps(apps()).encode(), "application/json")
            except OSError as e:
                return self.reply(502, why(e).encode())
        self.reply(404, b"not found")

    def do_POST(self):
        try:
            if m := re.fullmatch(r"/api/roku/key/(\w+)", self.path):
                if m[1] not in KEYS:
                    return self.reply(400, b"unknown key")
                roku("POST", f"/keypress/{m[1]}")
            elif m := re.fullmatch(r"/api/roku/launch/(\w+)", self.path):
                roku("POST", f"/launch/{m[1]}")
            elif self.path == "/api/roku/text":
                n = min(int(self.headers.get("Content-Length") or 0), 200)
                for ch in self.rfile.read(n).decode("utf-8", "ignore"):
                    roku("POST", "/keypress/Lit_" + urllib.parse.quote(ch, safe=""))
            else:
                return self.reply(404, b"not found")
        except OSError as e:
            return self.reply(502, why(e).encode())
        self.reply(204)

    def log_message(self, fmt, *args):   # quiet: one line per request is plenty
        print(self.address_string(), fmt % args, flush=True)


if __name__ == "__main__":
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
