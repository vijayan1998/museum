# Museum app ↔ Raspberry Pi over MQTT (phone hotspot, no network)

The app talks to the Pi with **MQTT** (`mqtt_client` package) and **no router or
internet**. The **phone shares its mobile hotspot** and runs the app as an MQTT
client; the **Pi joins that hotspot** and runs the **Mosquitto broker** plus a
Python subscriber that drives the exhibit hardware.

```
┌───────────────────────────┐          ┌──────────────────────────────┐
│ Phone / tablet            │  Wi-Fi   │ Raspberry Pi                 │
│  • shares MOBILE HOTSPOT  │◀────────▶│  joins the hotspot           │
│  • Museum app = MQTT client│  (LAN)  │  Mosquitto broker :1883      │
│                           │          │  museum_mqtt.py (subscriber) │
└───────────────────────────┘          └──────────────────────────────┘
        no internet / no router anywhere in this picture
```

Because the hotspot hands the Pi a **dynamic IP** (Android ≈ `192.168.43.x`,
iPhone ≈ `172.20.10.x`), the app can't hard-code the broker — it scans the
hotspot subnet for an open MQTT port (1883) and connects.

## On the Pi — two steps

```bash
# 1) Join the phone's hotspot (edit SSID/password at the top first)
sudo bash join_hotspot.sh

# turn the phone hotspot ON, confirm the Pi joined:
iwgetid            # -> your hotspot SSID
hostname -I        # -> the IP the phone gave the Pi

# 2) Install the broker + exhibit subscriber (starts them on boot)
sudo bash install_broker.sh
```

`install_broker.sh` installs Mosquitto + `python3-paho-mqtt`, opens port 1883 on
the hotspot, and runs `museum_mqtt.py` as a service.

> **2.4 GHz:** older Pis (Zero W, Pi 3) are 2.4 GHz only. On Android set the
> hotspot band to **2.4 GHz**; on iPhone turn on **Maximize Compatibility**.

## On the phone

1. Turn **ON the mobile hotspot** (2.4 GHz for older Pis).
2. Power the Pi — it auto-joins the hotspot and starts the broker.
3. Open the Museum app. The header status chip:
   - **grey** = idle → tap to search
   - **blue spinner** = searching / connecting
   - **green** = connected to the broker 🎉
   - **red** = no broker found (is the Pi on the hotspot with Mosquitto up?)
4. Tapping an exhibit's **Play Now** publishes
   `{"cmd":"select_stage","stage":N,...}` to `museum/command`.

First scan of a /24 takes a few seconds; afterwards the app remembers the
broker's address and reconnects instantly.

## Topics

| Topic | Direction | Example |
|-------|-----------|---------|
| `museum/command`  | app → pi | `{"cmd":"select_stage","stage":1,"title":"Ancient Civilizations"}` |
| `museum/command`  | app → pi | `{"cmd":"play"}` · `{"cmd":"pause"}` · `{"cmd":"ping"}` |
| `museum/status`   | pi → app | `{"playing":true}` · `{"stage":1}` · `{"pong":true}` (retained) |
| `museum/announce` | pi → app | `{"device":"museum-pi"}` (retained) |

Add hardware (GPIO lights, relays, an amp) at the `# TODO(hardware)` markers in
`museum_mqtt.py`.

## Self-test on the Pi (no app needed)

```bash
# terminal 1 — watch everything
mosquitto_sub -t 'museum/#' -v
# terminal 2 — send a command
mosquitto_pub -t 'museum/command' -m '{"cmd":"ping"}'
# terminal 1 should print:  museum/status {"pong": true}
```

## Testing the app without a Pi

Run a broker + the subscriber on your computer, join the SAME hotspot from the
computer, and the app discovers it exactly like a real Pi:

```bash
brew install mosquitto && brew services start mosquitto   # macOS
pip3 install paho-mqtt
python3 raspberry_pi/museum_mqtt.py
```

Or connect to a fixed broker address (skips the scan):

```dart
PiConnection.instance.connect(host: '192.168.43.50');   // port 1883 default
```

## App plumbing (Flutter)

- `lib/services/pi_connection.dart` — `PiConnection` (MQTT via `mqtt_client`):
  `discover()` scans the hotspot for the broker, connects, subscribes to
  `museum/status` + `museum/announce`, and exposes `sendCommand()` +
  a `messages` stream. Auto-reconnects (re-discovers) on drop.
- `lib/widgets/pi_status_chip.dart` — the header status chip.
- `lib/homescreen.dart` — discovers on launch; **Play Now** publishes the stage.

## Notes / limits

- Anonymous broker is fine on an isolated offline hotspot. To lock it down, add a
  Mosquitto password file and set `username_pw_set(...)` in `museum_mqtt.py` and
  `client.connectionMessage.authenticateAs(...)` in the app.
- Discovery only scans **private** subnets (10./172.16–31./192.168.) so it never
  probes a real network by accident.
- MQTT is plain TCP (dart:io sockets), so no Android cleartext-HTTP config is
  needed — only the INTERNET permission (already in the manifest).
