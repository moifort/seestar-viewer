#!/usr/bin/env python3
"""Capture des trames brutes du Seestar pour servir de jeux d'essai.

Usage:
    python3 capture_frames.py [ip] [duree_secondes]

Ecrit dans ./fixtures/ :
  - frame_<id>_<n>_<w>x<h>.bin  : payload brut de chaque trame
  - frames.json                  : metadonnees de chaque trame capturee
  - events.jsonl                 : flux d'evenements du port 4700 (lecture seule)

Le port 4800 refuse de streamer tant que le scope n'est pas en exposition
continue : lance une vue dans l'app officielle (le mode Paysage suffit).
Le script reessaie tout seul jusqu'a ce que les trames arrivent.
"""

import json
import os
import socket
import struct
import sys
import threading
import time

HOST = sys.argv[1] if len(sys.argv) > 1 else "seestar.local"
DURATION = float(sys.argv[2]) if len(sys.argv) > 2 else 180.0
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures")

HEADER_SIZE = 80
HEADER_FMT = ">HHHIHHBBHH"  # 20 premiers octets utiles
stop = threading.Event()


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def collect_events():
    """Enregistre le flux d'evenements du port 4700, sans jamais rien envoyer."""
    path = os.path.join(OUT, "events.jsonl")
    count = 0
    # Le scope ferme parfois le socket : on se reconnecte tant que la capture dure.
    with open(path, "w") as fh:
        while not stop.is_set():
            try:
                s = socket.create_connection((HOST, 4700), timeout=5)
            except OSError as exc:
                log(f"evenements : reconnexion dans 3s ({exc})")
                stop.wait(3)
                continue
            s.settimeout(2)
            buf = ""
            while not stop.is_set():
                try:
                    chunk = s.recv(8192)
                except socket.timeout:
                    continue
                except OSError:
                    break
                if not chunk:
                    break
                buf += chunk.decode(errors="replace")
                while "\r\n" in buf:
                    line, buf = buf.split("\r\n", 1)
                    if line.strip():
                        fh.write(line + "\n")
                        fh.flush()
                        count += 1
            s.close()
    log(f"evenements : {count} messages enregistres")


def recv_exact(sock, n):
    try:
        data = sock.recv(n, socket.MSG_WAITALL)
    except socket.timeout:
        return None
    except OSError:
        return None
    return data if data and len(data) == n else None


def capture_frames():
    meta = []
    counters = {}
    last_request = 0.0

    sock = socket.create_connection((HOST, 4800), timeout=5)
    sock.settimeout(3)
    log("connecte au port 4800")

    deadline = time.time() + DURATION
    while time.time() < deadline and not stop.is_set():
        # (Re)demande le flux tant qu'aucune trame d'image n'est arrivee.
        # Espace large : le scope repond "done" et streame ensuite de lui-meme,
        # insister ne sert a rien et pollue le log.
        if not meta and time.time() - last_request > 30:
            sock.sendall(b'{"id": 21, "method": "begin_streaming"}\r\n')
            last_request = time.time()

        header = recv_exact(sock, HEADER_SIZE)
        if header is None:
            continue

        size, frame_id, width, height = (
            lambda a: (a[3], a[7], a[8], a[9])
        )(struct.unpack(HEADER_FMT, header[:20]))

        if size <= 0:
            continue

        payload = recv_exact(sock, size)
        if payload is None:
            log(f"payload incomplet (attendu {size} octets)")
            continue

        # Le scope repond en texte clair quand il refuse (ex: mauvais mode).
        if size < 200 and payload[:1] not in (b"P", b"\x00") and b"\x00" not in payload[:20]:
            try:
                log(f"message du scope : {payload.decode()}")
                continue
            except UnicodeDecodeError:
                pass

        n = counters.get(frame_id, 0)
        counters[frame_id] = n + 1
        name = f"frame_{frame_id}_{n:03d}_{width}x{height}.bin"
        with open(os.path.join(OUT, name), "wb") as fh:
            fh.write(payload)

        entry = {
            "file": name,
            "frame_id": frame_id,
            "width": width,
            "height": height,
            "bytes": len(payload),
            "header_hex": header[:20].hex(),
            "magic": payload[:4].hex(),
            "is_zip": payload[:2] == b"PK",
        }
        if width and height:
            entry["bytes_per_pixel"] = len(payload) / (width * height)
        meta.append(entry)
        log(
            f"TRAME id={frame_id} {width}x{height} {len(payload)} octets"
            f"{' [ZIP]' if entry['is_zip'] else ''} -> {name}"
        )

        if counters.get(21, 0) >= 3 and counters.get(23, 0) >= 2:
            log("assez de trames des deux types, arret")
            break

    sock.close()
    with open(os.path.join(OUT, "frames.json"), "w") as fh:
        json.dump(meta, fh, indent=2)
    return meta, counters


def main():
    os.makedirs(OUT, exist_ok=True)
    log(f"cible {HOST}, duree max {DURATION:.0f}s")
    log("=> lance une vue dans l'app Seestar officielle (mode Paysage suffit)")

    events = threading.Thread(target=collect_events, daemon=True)
    events.start()

    try:
        meta, counters = capture_frames()
    except OSError as exc:
        log(f"echec : {exc}")
        stop.set()
        return 1
    finally:
        stop.set()
    events.join(timeout=3)

    if not meta:
        log("aucune trame capturee : le scope n'etait pas en exposition continue")
        return 1
    log(f"termine : {len(meta)} trames, types {dict(counters)} -> {OUT}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
