#!/usr/bin/env python3
"""Offline TCP server for the Museum Flutter app.

Runs on a Raspberry Pi that has joined the PHONE'S mobile hotspot (see
join_hotspot.sh) — no router and no internet. The phone shares its hotspot and
runs the Museum app; the app scans the hotspot subnet, finds this server by its
handshake, and opens a TCP socket to it.

Protocol: newline-delimited JSON, both directions.

  pi  -> app: {"type": "welcome", "device": "museum-pi"}   <- handshake the app looks for
  app -> pi : {"cmd": "select_stage", "stage": 1, "title": "Ancient Civilizations"}
  app -> pi : {"cmd": "play"} / {"cmd": "pause"} / {"cmd": "ping"}
  pi  -> app: {"type": "ack", "cmd": "select_stage", "stage": 1}
  pi  -> app: {"type": "status", "playing": true}

Wire real hardware where the `# TODO(hardware)` markers are (GPIO for lights,
relays, an amplifier, etc.). Standard library only — nothing to pip install.

IMPORTANT: the `device` value below must stay "museum-pi" — that is exactly the
handshake the app scans for (PiConnection.deviceId).
"""

import json
import socket
import threading

HOST = "0.0.0.0"   # listen on every interface (incl. the hotspot link)
PORT = 1883
DEVICE_ID = "museum-pi"

# --- Optional GPIO wiring -------------------------------------------------
# Uncomment on a real Pi to drive exhibit hardware.
#
#   import RPi.GPIO as GPIO
#   GPIO.setmode(GPIO.BCM)
#   STAGE_PINS = {1: 17, 2: 27, 3: 22}  # exhibit -> GPIO pin
#   for pin in STAGE_PINS.values():
#       GPIO.setup(pin, GPIO.OUT)


def handle_command(message: dict) -> dict:
    """Act on one command from the app and return a reply to send back."""
    cmd = message.get("cmd")

    if cmd == "ping":
        return {"type": "pong"}

    if cmd == "select_stage":
        stage = message.get("stage")
        print(f"[museum] exhibit selected: stage {stage} "
              f"({message.get('title', '?')})")
        # TODO(hardware): light up the exhibit, e.g.
        #   pin = STAGE_PINS.get(stage)
        #   if pin: GPIO.output(pin, GPIO.HIGH)
        return {"type": "ack", "cmd": cmd, "stage": stage}

    if cmd in ("play", "pause"):
        playing = cmd == "play"
        print(f"[museum] playback -> {'play' if playing else 'pause'}")
        # TODO(hardware): start/stop the amplifier or local audio here.
        return {"type": "status", "playing": playing}

    return {"type": "error", "reason": f"unknown command: {cmd}"}


def send_json(conn: socket.socket, payload: dict) -> None:
    conn.sendall((json.dumps(payload) + "\n").encode("utf-8"))


def serve_client(conn: socket.socket, addr) -> None:
    print(f"[museum] app connected from {addr[0]}:{addr[1]}")
    try:
        # Handshake FIRST so the app's discovery scan recognises us.
        send_json(conn, {"type": "welcome", "device": DEVICE_ID})
        buffer = ""
        while True:
            chunk = conn.recv(4096)
            if not chunk:
                break  # client closed the socket
            buffer += chunk.decode("utf-8", errors="ignore")
            # A message ends at each newline; keep any partial tail buffered.
            while "\n" in buffer:
                line, buffer = buffer.split("\n", 1)
                line = line.strip()
                if not line:
                    continue
                try:
                    message = json.loads(line)
                except json.JSONDecodeError:
                    send_json(conn, {"type": "error", "reason": "bad json"})
                    continue
                send_json(conn, handle_command(message))
    except ConnectionError:
        pass
    finally:
        conn.close()
        print(f"[museum] app disconnected: {addr[0]}:{addr[1]}")


def main() -> None:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as server:
        server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        server.bind((HOST, PORT))
        server.listen(5)
        print(f"[museum] listening on {HOST}:{PORT} — waiting for the app…")
        try:
            while True:
                conn, addr = server.accept()
                # One thread per app so several tablets can connect at once.
                threading.Thread(
                    target=serve_client, args=(conn, addr), daemon=True
                ).start()
        except KeyboardInterrupt:
            print("\n[museum] shutting down.")


if __name__ == "__main__":
    main()
