#!/usr/bin/env python3
"""MQTT subscriber for the Museum Flutter app — runs on the Raspberry Pi.

The Pi runs the Mosquitto broker (see install_broker.sh); this script connects
to that local broker, announces the device, subscribes to commands from the app,
drives the exhibit hardware, and publishes status back.

Topics
  museum/command  (app -> pi)  {"cmd":"select_stage","stage":1,"title":"..."}
                               {"cmd":"play"} / {"cmd":"pause"} / {"cmd":"ping"}
  museum/status   (pi -> app)  {"playing":true} / {"stage":1} / {"pong":true}
  museum/announce (pi -> app)  {"device":"museum-pi"}   (retained)

Needs paho-mqtt:  sudo apt install python3-paho-mqtt   (or pip install paho-mqtt)
Works with paho-mqtt v1 and v2.

Wire real hardware where the `# TODO(hardware)` markers are.
"""

import json

import paho.mqtt.client as mqtt

BROKER = "localhost"     # the broker runs on this same Pi
PORT = 1883
COMMAND_TOPIC = "museum/command"
STATUS_TOPIC = "museum/status"
ANNOUNCE_TOPIC = "museum/announce"
DEVICE_ID = "museum-pi"

# --- Optional GPIO wiring -------------------------------------------------
# Uncomment on a real Pi to drive exhibit hardware.
#
#   import RPi.GPIO as GPIO
#   GPIO.setmode(GPIO.BCM)
#   STAGE_PINS = {1: 17, 2: 27, 3: 22}  # exhibit -> GPIO pin
#   for pin in STAGE_PINS.values():
#       GPIO.setup(pin, GPIO.OUT)


def publish_status(client, payload: dict) -> None:
    client.publish(STATUS_TOPIC, json.dumps(payload), qos=1, retain=True)


def handle_command(client, message: dict) -> None:
    cmd = message.get("cmd")

    if cmd == "ping":
        publish_status(client, {"pong": True})

    elif cmd == "select_stage":
        stage = message.get("stage")
        print(f"[museum] exhibit selected: stage {stage} "
              f"({message.get('title', '?')})")
        # TODO(hardware): light up the exhibit, e.g.
        #   pin = STAGE_PINS.get(stage)
        #   if pin: GPIO.output(pin, GPIO.HIGH)
        publish_status(client, {"stage": stage})

    elif cmd in ("play", "pause"):
        playing = cmd == "play"
        print(f"[museum] playback -> {'play' if playing else 'pause'}")
        # TODO(hardware): start/stop the amplifier or local audio here.
        publish_status(client, {"playing": playing})

    else:
        print(f"[museum] unknown command: {cmd}")


# --- MQTT callbacks (compatible with paho-mqtt v1 and v2) -----------------
def on_connect(client, userdata, flags, reason_code=0, properties=None):
    print(f"[museum] connected to broker ({reason_code})")
    # Retained so an app that connects later still learns the device id.
    client.publish(
        ANNOUNCE_TOPIC, json.dumps({"device": DEVICE_ID}), qos=1, retain=True
    )
    client.subscribe(COMMAND_TOPIC, qos=1)
    print(f"[museum] subscribed to {COMMAND_TOPIC}")


def on_message(client, userdata, msg):
    try:
        message = json.loads(msg.payload.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        print(f"[museum] ignoring bad payload on {msg.topic}")
        return
    if isinstance(message, dict):
        handle_command(client, message)


def make_client():
    # paho-mqtt v2 requires an explicit callback API version; v1 doesn't have it.
    try:
        return mqtt.Client(mqtt.CallbackAPIVersion.VERSION2)
    except AttributeError:
        return mqtt.Client()


def main() -> None:
    client = make_client()
    client.on_connect = on_connect
    client.on_message = on_message
    # If this process dies, tell apps the device went away.
    client.will_set(
        ANNOUNCE_TOPIC,
        json.dumps({"device": DEVICE_ID, "online": False}),
        qos=1,
        retain=True,
    )

    print(f"[museum] connecting to broker at {BROKER}:{PORT}…")
    client.connect(BROKER, PORT, keepalive=30)
    client.loop_forever()  # auto-reconnects to the local broker


if __name__ == "__main__":
    main()
