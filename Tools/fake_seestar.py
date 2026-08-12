#!/usr/bin/env python3
"""Faux Seestar : rejoue une session enregistree sur les ports 4700 et 4800.

Permet de developper et de tester l'app en plein jour, sans telescope, et de
provoquer a volonte les pannes a gerer.

    python3 Tools/fake_seestar.py [--refuse] [--coupe-apres N]

  --refuse       repond "only available for continuous exposure" au lieu de
                 streamer, pour tester l'ecran d'attente
  --coupe-apres  ferme brutalement le socket apres N trames, pour tester
                 la reconnexion
"""

import argparse
import os
import socket
import struct
import threading
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FRAME = os.path.join(ROOT, "fixtures", "frame_21_000_1080x1920.bin")
EVENTS = os.path.join(ROOT, "fixtures", "events.jsonl")
WIDTH, HEIGHT = 1080, 1920


def make_header(size, frame_id, width, height):
    """Reproduit l'en-tete de 80 octets mesure sur le materiel."""
    head = struct.pack(">HHHIHHBBHH", 0, 0, 0, size, 0, 0, 0, frame_id, width, height)
    return head + b"\x00" * (80 - len(head))


def imaging_client(conn, addr, payload, args):
    print(f"  client imagerie {addr[0]}", flush=True)
    try:
        conn.recv(1024)  # begin_streaming
        if args.refuse:
            msg = b"only available for continuous exposure"
            conn.sendall(make_header(len(msg), 21, 0, 0) + msg)
            time.sleep(60)
            return
        conn.sendall(make_header(4, 21, 0, 0) + b"done")
        sent = 0
        while True:
            conn.sendall(make_header(len(payload), 21, WIDTH, HEIGHT) + payload)
            sent += 1
            if args.coupe_apres and sent >= args.coupe_apres:
                print(f"  coupure volontaire apres {sent} trames", flush=True)
                return
            time.sleep(1.0)
    except OSError:
        pass
    finally:
        conn.close()


def serve_imaging(args):
    payload = open(FRAME, "rb").read()
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 4800))
    srv.listen(5)
    print("faux Seestar : imagerie sur 4800", flush=True)

    while True:
        conn, addr = srv.accept()
        threading.Thread(target=imaging_client, args=(conn, addr, payload, args),
                         daemon=True).start()


def events_client(conn, addr, lines):
    print(f"  client evenements {addr[0]}", flush=True)
    try:
        while True:
            for line in lines:
                conn.sendall(line.encode() + b"\r\n")
                time.sleep(2)
    except OSError:
        pass
    finally:
        conn.close()


def serve_events():
    lines = [l.strip() for l in open(EVENTS) if l.strip()]
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind(("0.0.0.0", 4700))
    srv.listen(5)
    print("faux Seestar : evenements sur 4700", flush=True)

    while True:
        conn, addr = srv.accept()
        threading.Thread(target=events_client, args=(conn, addr, lines),
                         daemon=True).start()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--refuse", action="store_true")
    parser.add_argument("--coupe-apres", type=int, default=0)
    args = parser.parse_args()

    threading.Thread(target=serve_events, daemon=True).start()
    serve_imaging(args)


if __name__ == "__main__":
    main()
