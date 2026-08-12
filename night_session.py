#!/usr/bin/env python3
"""Leve les trois hypotheses ouvertes du design, en une seule session nocturne.

A lancer pendant que le Seestar empile reellement sur une cible.

    python3 night_session.py [ip]

Phase 1 - Diffusion multi-clients : trois clients simultanes sur le port 4800.
          Repond a la question qui engage l'architecture (§8, hypothese 3).
Phase 2 - Capture : trames d'empilement (id=23) et de preview (id=21) non saturees,
          pour valider le format ZIP et le motif de Bayer (§8, hypotheses 1 et 2).

Ecrit dans ./fixtures_night/ et affiche un verdict lisible a la fin.
"""

import json
import os
import socket
import struct
import sys
import threading
import time
import zipfile
from io import BytesIO

HOST = sys.argv[1] if len(sys.argv) > 1 else "192.168.1.170"
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures_night")

HEADER_SIZE = 80
HEADER_FMT = ">HHHIHHBBHH"
FANOUT_CLIENTS = 3
FANOUT_SECONDS = 30
CAPTURE_SECONDS = 900  # 15 min : le temps que quelques subs s'empilent
WANTED = {21: 3, 23: 3}


def log(msg):
    print(f"[{time.strftime('%H:%M:%S')}] {msg}", flush=True)


def recv_exact(sock, n):
    try:
        data = sock.recv(n, socket.MSG_WAITALL)
    except (socket.timeout, OSError):
        return None
    return data if data and len(data) == n else None


def read_frame(sock):
    """Retourne (frame_id, width, height, payload) ou None."""
    header = recv_exact(sock, HEADER_SIZE)
    if header is None:
        return None
    fields = struct.unpack(HEADER_FMT, header[:20])
    size, frame_id, width, height = fields[3], fields[7], fields[8], fields[9]
    if size <= 0:
        return None
    payload = recv_exact(sock, size)
    if payload is None:
        return None
    return frame_id, width, height, payload


def is_text(payload):
    return len(payload) < 200 and b"\x00" not in payload[:20]


# --------------------------------------------------------------------------
# Phase 1 : diffusion multi-clients
# --------------------------------------------------------------------------

def fanout_test():
    log(f"PHASE 1 : {FANOUT_CLIENTS} clients simultanes pendant {FANOUT_SECONDS}s")
    counts = {}

    def client(idx):
        tally = {"frames": 0, "notes": set()}
        counts[idx] = tally
        try:
            sock = socket.create_connection((HOST, 4800), timeout=5)
        except OSError as exc:
            tally["notes"].add(f"connexion refusee: {exc}")
            return
        sock.settimeout(5)
        sock.sendall(b'{"id": 21, "method": "begin_streaming"}\r\n')
        end = time.time() + FANOUT_SECONDS
        while time.time() < end:
            frame = read_frame(sock)
            if frame is None:
                continue
            _, _, _, payload = frame
            if is_text(payload):
                tally["notes"].add(payload.decode(errors="replace"))
            else:
                tally["frames"] += 1
        sock.close()

    threads = [threading.Thread(target=client, args=(i,)) for i in range(FANOUT_CLIENTS)]
    for t in threads:
        t.start()
    for t in threads:
        t.join()

    served = 0
    for i in sorted(counts):
        tally = counts[i]
        notes = ", ".join(sorted(tally["notes"])) or "-"
        log(f"  client {i + 1} : {tally['frames']} trames | {notes}")
        if tally["frames"] > 0:
            served += 1

    if served == FANOUT_CLIENTS:
        verdict = "DIFFUSION A TOUS : architecture directe confirmee"
    elif served == 0:
        verdict = "AUCUN client servi : le scope n'empilait pas ? relancer"
    else:
        verdict = f"DIFFUSION EXCLUSIVE ({served}/{FANOUT_CLIENTS}) : un relais sera necessaire"
    log(f"  => {verdict}")
    return {"served": served, "clients": FANOUT_CLIENTS, "verdict": verdict}


# --------------------------------------------------------------------------
# Phase 2 : capture des trames
# --------------------------------------------------------------------------

def saturation(payload, width, height):
    """Part des echantillons 16 bits au maximum, pour ecarter les images brulees."""
    if not width or not height or len(payload) != width * height * 2:
        return None
    import array

    samples = array.array("H")
    samples.frombytes(payload)
    if sys.byteorder == "big":
        samples.byteswap()
    step = max(1, len(samples) // 20000)
    subset = samples[::step]
    peak = max(subset)
    return sum(1 for v in subset if v >= peak) / len(subset)


def inspect_zip(payload):
    """Decrit une trame d'empilement supposee zippee."""
    if payload[:2] != b"PK":
        return {"is_zip": False, "magic": payload[:4].hex()}
    try:
        with zipfile.ZipFile(BytesIO(payload)) as zf:
            infos = zf.infolist()
            return {
                "is_zip": True,
                "entries": [
                    {
                        "name": i.filename,
                        "size": i.file_size,
                        "compressed": i.compress_size,
                        "method": "stocke" if i.compress_type == 0 else "compresse",
                    }
                    for i in infos
                ],
            }
    except zipfile.BadZipFile as exc:
        return {"is_zip": True, "erreur": str(exc)}


def capture():
    log(f"PHASE 2 : capture (max {CAPTURE_SECONDS // 60} min)")
    meta = []
    kept = {21: 0, 23: 0}
    best_preview = None  # (saturation, payload, width, height)

    sock = socket.create_connection((HOST, 4800), timeout=5)
    sock.settimeout(10)
    sock.sendall(b'{"id": 21, "method": "begin_streaming"}\r\n')

    end = time.time() + CAPTURE_SECONDS
    while time.time() < end and any(kept[k] < WANTED[k] for k in WANTED):
        frame = read_frame(sock)
        if frame is None:
            continue
        frame_id, width, height, payload = frame

        if is_text(payload):
            log(f"  message du scope : {payload.decode(errors='replace')}")
            continue

        entry = {
            "frame_id": frame_id,
            "width": width,
            "height": height,
            "bytes": len(payload),
        }
        if width and height:
            entry["bytes_per_pixel"] = len(payload) / (width * height)

        if frame_id == 23:
            entry["zip"] = inspect_zip(payload)
            name = f"stack_{kept[23]:02d}_{width}x{height}.bin"
            with open(os.path.join(OUT, name), "wb") as fh:
                fh.write(payload)
            entry["file"] = name
            kept[23] += 1
            meta.append(entry)
            log(f"  EMPILEMENT {width}x{height} {len(payload)} o -> {name} | {entry['zip']}")

        elif frame_id == 21:
            sat = saturation(payload, width, height)
            entry["saturation"] = sat
            # On conserve les moins saturees : ce sont les seules qui portent
            # une information de couleur exploitable pour valider le Bayer.
            if sat is not None and (best_preview is None or sat < best_preview[0]):
                best_preview = (sat, payload, width, height)
            if kept[21] < WANTED[21] and sat is not None and sat < 0.05:
                name = f"preview_{kept[21]:02d}_{width}x{height}.bin"
                with open(os.path.join(OUT, name), "wb") as fh:
                    fh.write(payload)
                entry["file"] = name
                kept[21] += 1
                meta.append(entry)
                log(f"  PREVIEW {width}x{height} saturation {sat:.1%} -> {name}")

    sock.close()

    # Filet de securite : si aucune preview sous le seuil, on garde la meilleure.
    if kept[21] == 0 and best_preview is not None:
        sat, payload, width, height = best_preview
        name = f"preview_best_{width}x{height}.bin"
        with open(os.path.join(OUT, name), "wb") as fh:
            fh.write(payload)
        meta.append({"frame_id": 21, "file": name, "saturation": sat,
                     "width": width, "height": height, "bytes": len(payload)})
        log(f"  aucune preview sous 5% de saturation ; gardé la meilleure ({sat:.1%})")

    return meta, kept


def collect_events(stop):
    path = os.path.join(OUT, "events.jsonl")
    count = 0
    with open(path, "w") as fh:
        while not stop.is_set():
            try:
                sock = socket.create_connection((HOST, 4700), timeout=5)
            except OSError:
                stop.wait(3)
                continue
            sock.settimeout(2)
            buf = ""
            while not stop.is_set():
                try:
                    chunk = sock.recv(8192)
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
            sock.close()
    log(f"evenements : {count} messages enregistres")


def main():
    os.makedirs(OUT, exist_ok=True)
    log(f"cible {HOST} — lance-moi pendant un empilement en cours")

    stop = threading.Event()
    events = threading.Thread(target=collect_events, args=(stop,), daemon=True)
    events.start()

    report = {"host": HOST, "date": time.strftime("%Y-%m-%d %H:%M:%S")}
    try:
        report["fanout"] = fanout_test()
        meta, kept = capture()
        report["frames"] = meta
        report["kept"] = kept
    finally:
        stop.set()
        events.join(timeout=3)

    with open(os.path.join(OUT, "report.json"), "w") as fh:
        json.dump(report, fh, indent=2, ensure_ascii=False)

    print("\n=== VERDICT ===")
    print(f"1. Diffusion multi-clients : {report['fanout']['verdict']}")
    stacks = [f for f in report.get("frames", []) if f["frame_id"] == 23]
    if stacks:
        z = stacks[0].get("zip", {})
        print(f"2. Trames d'empilement     : {len(stacks)} capturees, ZIP={z.get('is_zip')}")
        for e in z.get("entries", []):
            print(f"   entree '{e['name']}' : {e['size']} o, {e['method']}")
    else:
        print("2. Trames d'empilement     : AUCUNE — le scope empilait-il vraiment ?")
    previews = [f for f in report.get("frames", []) if f["frame_id"] == 21]
    if previews:
        print(f"3. Preview pour le Bayer   : {len(previews)} capturees, "
              f"saturation min {min(p['saturation'] for p in previews):.1%}")
        print("   verifier le motif : python3 decode_frame.py "
              f"fixtures_night/{previews[0]['file']} --patterns")
    else:
        print("3. Preview pour le Bayer   : AUCUNE exploitable")
    print(f"\nDetail complet -> {os.path.join(OUT, 'report.json')}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
