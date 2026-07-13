#!/usr/bin/env bash
#
# STEP 2 of 2 on the Pi. Install the Mosquitto MQTT broker and the Python
# subscriber that drives the exhibit hardware, and start both on boot.
#
#     sudo bash install_broker.sh
#
# After this the Pi listens for MQTT on port 1883. The app discovers it on the
# hotspot subnet and connects — no router, no internet.

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root:  sudo bash install_broker.sh" >&2
  exit 1
fi

HERE="$(cd "$(dirname "$0")" && pwd)"

echo ">> Installing Mosquitto + Python MQTT client…"
apt-get update -y || true
apt-get install -y mosquitto mosquitto-clients python3-paho-mqtt

echo ">> Configuring the broker (anonymous, listens on the hotspot)…"
# Offline / LAN-only broker: no internet, so anonymous access on the local
# hotspot is fine. Lock this down with a password file if you need to.
cat >/etc/mosquitto/conf.d/museum.conf <<EOF
listener 1883 0.0.0.0
allow_anonymous true
EOF

systemctl enable mosquitto
systemctl restart mosquitto

echo ">> Installing the exhibit subscriber service…"
install -m 0755 "$HERE/museum_mqtt.py" /home/pi/museum_mqtt.py
install -m 0644 "$HERE/museum-mqtt.service" /etc/systemd/system/museum-mqtt.service
systemctl daemon-reload
systemctl enable --now museum-mqtt

cat <<EOF

Done. The Pi is now an MQTT broker on port 1883 with the exhibit subscriber
running.

Quick self-test on the Pi (in two terminals):
  mosquitto_sub -t 'museum/#' -v
  mosquitto_pub -t 'museum/command' -m '{"cmd":"ping"}'

On the phone: turn on the hotspot, open the Museum app — the status chip
searches, finds this broker, and turns green.
EOF
