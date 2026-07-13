#!/usr/bin/env bash
#
# STEP 1 of 2 on the Pi. Make the Raspberry Pi auto-join the PHONE'S mobile
# hotspot — NO router and NO internet needed. The phone shares its hotspot AND
# runs the Museum app; the Pi connects to that hotspot as a Wi-Fi client, then
# runs an MQTT broker (see install_broker.sh) that the app talks to.
#
#     ┌───────────────────────────┐        ┌──────────────────────────┐
#     │ Phone: hotspot + the app  │◀─Wi-Fi▶│ Pi: this + Mosquitto +   │
#     │        (MQTT client)      │  (LAN) │ museum_mqtt.py           │
#     └───────────────────────────┘        └──────────────────────────┘
#
# Set your hotspot's SSID / password below, then run once with sudo:
#
#     sudo bash join_hotspot.sh
#
# Older Pis (Zero W, Pi 3) are 2.4 GHz only — set the phone hotspot band to
# "2.4 GHz" (Android) or turn on "Maximize Compatibility" (iPhone).

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
  nmcli connection add type wifi ifname wlan0 con-name museum-hotspot ssid "$SSID"
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

hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true

cat <<EOF

Done with step 1.

Next:
  • Turn ON the phone hotspot (2.4 GHz for older Pis) so the Pi can join.
  • Verify the Pi joined:  iwgetid    (should print "${SSID}")
  • See its IP:           hostname -I
  • Then run step 2:      sudo bash install_broker.sh
EOF
