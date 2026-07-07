# Museum app ↔ Raspberry Pi over the phone's mobile hotspot (no network)

The app connects to the Pi **without any router or internet**. The **phone
shares its mobile hotspot** and runs the app; the **Pi joins that hotspot** as a
Wi-Fi client and runs a tiny TCP server. The app scans the hotspot subnet, finds
the Pi by its handshake, and holds a socket open to it.

```
┌───────────────────────────┐          ┌──────────────────────┐
│ Phone / tablet            │  Wi-Fi   │ Raspberry Pi         │
│  • shares MOBILE HOTSPOT  │◀────────▶│  joins the hotspot   │
│  • runs the Museum app    │  (LAN)   │  runs museum_server  │
└───────────────────────────┘          └──────────────────────┘
        no internet / no router anywhere in this picture
```

Why discovery? The hotspot hands the Pi a **dynamic IP** (Android ≈
`192.168.43.x`, iPhone ≈ `172.20.10.x`), so the app can't hard-code it — it
probes the subnet for a host answering with `{"device":"museum-pi"}`.

## 1. Make the Pi join your hotspot (one time)

Edit the SSID/password at the top of `join_hotspot.sh`, then on the Pi:

```bash
sudo bash join_hotspot.sh
```

Works on Raspberry Pi OS Bookworm (NetworkManager) and older (wpa_supplicant).

> **2.4 GHz:** older Pis (Zero W, Pi 3) are 2.4 GHz only. On Android set the
> hotspot band to **2.4 GHz**; on iPhone turn on **Maximize Compatibility**.

## 2. Run the server on the Pi

```bash
python3 museum_server.py
# [museum] listening on 0.0.0.0:8000 — waiting for the app…
```

Standard library only — nothing to `pip install`. Run it on boot instead:

```bash
sudo cp museum_server.py /home/pi/museum_server.py
sudo cp museum-server.service /etc/systemd/system/
sudo systemctl enable --now museum-server
```

## 3. Use it

1. On the phone: turn **ON the mobile hotspot** (2.4 GHz for older Pis).
2. Power the Pi — it auto-joins the hotspot in ~20s
   (verify: `iwgetid` shows your SSID, `hostname -I` shows its IP).
3. Open the Museum app. The header status chip:
   - **grey** = idle → tap to search
   - **blue spinner** = searching / connecting
   - **green** = connected 🎉
   - **red** = no Pi found (is it powered on and joined to the hotspot?)
4. Tapping an exhibit's **Play Now** sends
   `{"cmd":"select_stage","stage":N,...}` to the Pi.

The scan of one /24 takes a few seconds the first time; afterwards the app
remembers the Pi's address and reconnects instantly.

## Protocol

Newline-delimited JSON, both directions.

| Direction | Example |
|-----------|---------|
| pi → app  | `{"type":"welcome","device":"museum-pi"}`  ← handshake the app scans for |
| app → pi  | `{"cmd":"select_stage","stage":1,"title":"Ancient Civilizations"}` |
| app → pi  | `{"cmd":"play"}` · `{"cmd":"pause"}` · `{"cmd":"ping"}` |
| pi → app  | `{"type":"ack","cmd":"select_stage","stage":1}` |
| pi → app  | `{"type":"status","playing":true}` |

Add hardware (GPIO lights, relays, an amp) at the `# TODO(hardware)` markers in
`museum_server.py`. Keep `device` = `"museum-pi"` — it must match
`PiConnection.deviceId` in the app or discovery won't recognise the Pi.

## Testing without a Pi

Run the server on your computer, join the SAME hotspot from the computer, and
the app will discover it exactly like a real Pi:

```bash
python3 raspberry_pi/museum_server.py
```

Or connect to a fixed address (skips the scan):

```dart
PiConnection.instance.connect(host: '192.168.43.50');
```

## Notes / limits

- **The app must stay on the hotspot too.** The phone is both the hotspot AND a
  client of it — that's normal; iOS/Android allow the local app to reach hotspot
  clients.
- Discovery only scans **private** subnets (10./172.16–31./192.168.) so it never
  probes a real network by accident.
- Multiple tablets can connect to one Pi at once (the server is threaded).
