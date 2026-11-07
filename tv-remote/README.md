# tv-remote (docker#189)

A phone-sized remote page for the living-room Roku, at **http://100.69.184.113:8020** (Tailscale only).

- **Roku Express 4K+** at `10.0.0.97`, over Roku's External Control Protocol (port 8060; no pairing, no auth on the LAN).
  It handles the d-pad, OK, back, home, playback, volume and power, typing into search boxes, and one-tap launch for every installed channel.
  Power and volume reach the TV only if HDMI-CEC (Samsung: *Anynet+*) is on.
- **Samsung TV:** next. It needs the TV on the network (WebSocket API on 8002, one-time "Allow" prompt on the TV).

`server.py` is stdlib Python. Every keypress is checked against an allowlist before it goes to the Roku.
If the Roku's DHCP address changes, update `ROKU_URL` in `docker-compose.yml`. A DHCP reservation for it on the router is the better fix.
