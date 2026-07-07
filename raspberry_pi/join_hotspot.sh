#!/usr/bin/env bash
#
# Make the Raspberry Pi auto-join the PHONE'S mobile hotspot — NO router and NO
# internet needed. The phone shares its hotspot AND runs the Museum app; the Pi
# connects to that hotspot as a Wi-Fi client and runs museum_server.py. The app
# then discovers the Pi automatically on the hotspot subnet.
#
#     ┌───────────────────────────┐        ┌───────────────────┐
#     │ Phone: hotspot + the app  │◀─Wi-Fi▶│ Pi: this script + │
#     │                           │  (LAN) │ museum_server.py  │
#     └───────────────────────────┘        └───────────────────┘
#
# Set your hotspot's SSID / password below, then run once with sudo:
#
#     sudo bash join_hotspot.sh
#
# Tips for the phone's hotspot:
#   • Older Pis (Zero W, Pi 3) are 2.4 GHz only. On the phone, set the hotspot
#     band to "2.4 GHz" (Android) or turn on "Maximize Compatibility" (iPhone).
#   • Keep the hotspot ON and the app OPEN — the app IS the hotspot's client too.

set -euo pipefail

SSID="MyPhoneHotspot"       # <-- your phone's hotspot name
PASSPHRASE="hotspotpass"    # <-- your phone's hotspot password (8+ chars)
COUNTRY="US"                # <-- your 2-letter Wi-Fi regulatory country
HOSTNAME="museum-pi"        # advertised as museum-pi.local (nice-to-have)

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash join_hotspot.sh" >&2
  exit 1
fi

echo ">> Setting Wi-Fi country ($COUNTRY) and unblocking the radio…"
raspi-config nonint do_wifi_country "$COUNTRY" 2>/dev/null || true
rfkill unblock wlan || true

if command -v nmcli >/dev/null 2>&1 && systemctl is-active --quiet NetworkManager; then
  # --- Raspberry Pi OS Bookworm (NetworkManager) ---------------------------
  echo ">> Adding the hotspot connection via NetworkManager…"
  nmcli connection delete museum-hotspot >/dev/null 2>&1 || true
  nmcli connection add type wifi ifname wlan0 con-name museum-hotspot \
    ssid "$SSID"
  nmcli connection modify museum-hotspot \
    wifi-sec.key-mgmt wpa-psk \
    wifi-sec.psk "$PASSPHRASE" \
    connection.autoconnect yes \
    connection.autoconnect-priority 10
  nmcli connection up museum-hotspot || \
    echo "   (couldn't connect now — will auto-join when the hotspot is on)"
else
  # --- Older Raspberry Pi OS (wpa_supplicant) ------------------------------
  echo ">> Adding the hotspot to wpa_supplicant…"
  WPA=/etc/wpa_supplicant/wpa_supplicant.conf
  touch "$WPA"
  if ! grep -q "country=" "$WPA"; then
    sed -i "1i country=${COUNTRY}" "$WPA"
  fi
  if ! grep -q "ssid=\"${SSID}\"" "$WPA"; then
    {
      echo ""
      echo "network={"
      echo "    ssid=\"${SSID}\""
      echo "    psk=\"${PASSPHRASE}\""
      echo "    key_mgmt=WPA-PSK"
      echo "    priority=10"
      echo "}"
    } >> "$WPA"
  fi
  wpa_cli -i wlan0 reconfigure 2>/dev/null || systemctl restart dhcpcd || true
fi

echo ">> Enabling museum-pi.local (avahi) as a bonus name…"
apt-get install -y avahi-daemon >/dev/null 2>&1 || true
hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true

cat <<EOF

Done.

On the phone:
  1. Turn ON your mobile hotspot (2.4 GHz band for older Pis).
  2. Power the Pi — it auto-joins the hotspot within ~20s.
  3. Start the server on the Pi:   python3 museum_server.py
     (or install it as a service — see README.md)
  4. Open the Museum app. The status chip searches the hotspot,
     finds the Pi, and turns green.

Check the Pi actually joined:   iwgetid    (should print "${SSID}")
See the IP the phone gave it:   hostname -I
EOF
