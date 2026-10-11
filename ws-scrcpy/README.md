# ws-scrcpy: the phone in a browser tab

Mirrors and controls Brandon's Pixel 10 Pro Fold from a web page (docker#171, agent-bus
thread 026). WebForge pins it as the 📱 Phone tab (WebForge#359).

- **URL:** http://100.69.184.113:8017 (Tailscale only; whoever opens it controls the phone)
- **Upstream:** [NetrisTV/ws-scrcpy](https://github.com/NetrisTV/ws-scrcpy), built from a pinned
  commit (`WS_SCRCPY_REF` in the Dockerfile). No releases since v0.8.1 (2024), no official image.
- **Tested:** 2026-10-11, Fold on Android 17, Edge: video, touch and keyboard work with the
  **H264 Converter** player (`player=mse`).

## How it's wired

- `network_mode: host`, using the **host's** adb server on `127.0.0.1:5037`. The phone is
  connected there over Tailscale (Wireless debugging, `adb devices` →
  `100.78.213.32:<port>`). The container's own `adb` (Debian, protocol 41) only talks to that
  server; it never starts its own.
- Listens only on `100.69.184.113:8017`, via a build-time patch (`LISTEN_HOST`), because
  upstream binds every interface. Its startup log still *prints* every interface; `ss -lnt |
  grep 8017` is the truth.
- When a stream opens, adb forwards a host `127.0.0.1` port to the phone's `tcp:8886`
  (`adb forward --list`).

## URLs

- Device list: `http://100.69.184.113:8017/`; click **H264 Converter** on the device row.
- Straight to the stream (what a pinned tab wants):

  ```
  http://100.69.184.113:8017/#!action=stream&udid=<serial>&player=mse&ws=ws%3A%2F%2F100.69.184.113%3A8017%2F%3Faction%3Dproxy-adb%26remote%3Dtcp%253A8886%26udid%3D<serial, encoded twice>
  ```

  `<serial>` is the adb serial, e.g. `100.78.213.32%3A44347` (and `100.78.213.32%253A44347`
  inside `ws=`). **It includes the wireless-debugging port, which changes** whenever Wireless
  debugging is toggled or the phone reboots, so the direct link goes stale with it. The
  device list never does.

## Reconnect

When the phone drops (reboot, Wireless debugging toggled): on the phone, Developer options →
Wireless debugging shows the new port; on dockerhost, `phone connect <port>` (dotfiles) or
`adb connect 100.78.213.32:<port>`. ws-scrcpy watches the adb server and shows the phone again
on its own; no container restart. Reload the page.

## Deploy

Opted into `./deploy` (STACKS): a merge that changes the compose file, Dockerfile or
`config.yaml` rebuilds and recreates it. To bump upstream, change `WS_SCRCPY_REF`.
