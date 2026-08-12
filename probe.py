#!/usr/bin/env python3
"""Diagnostic de connexion au Seestar sur le reseau local.

Usage:
    python3 probe.py            # decouverte automatique
    python3 probe.py 192.168.1.42   # IP explicite

Repond a trois questions avant d'ecrire la moindre ligne de Swift :
  - le Seestar est-il joignable, et a quelle IP ?
  - quel firmware / modele ?
  - l'authentification (firmware 7.18+) est-elle exigee ?
"""

import json
import socket
import sys
import time

CONTROL_PORT = 4700
DISCOVERY_PORT = 4720
TIMEOUT = 5.0


def discover(timeout=3.0):
    """Broadcast scan_iscope en UDP, retourne les IP qui repondent."""
    found = []
    targets = ["255.255.255.255"]
    try:
        local = socket.gethostbyname(socket.gethostname())
        targets.append(local.rsplit(".", 1)[0] + ".255")
    except OSError:
        pass

    s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
    s.settimeout(timeout)
    payload = json.dumps({"id": 1, "method": "scan_iscope"}).encode()
    for dst in targets:
        try:
            s.sendto(payload, (dst, DISCOVERY_PORT))
        except OSError:
            continue

    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            data, addr = s.recvfrom(4096)
        except socket.timeout:
            break
        found.append((addr[0], data.decode(errors="replace").strip()))
    s.close()

    # Repli : mDNS, utilise par le SDK seestarpy.
    if not found:
        try:
            found.append((socket.gethostbyname("seestar.local"), "via mDNS"))
        except OSError:
            pass
    return found


class Control:
    """Client JSON-RPC minimal sur le port 4700 (une requete par ligne)."""

    def __init__(self, host):
        self.sock = socket.create_connection((host, CONTROL_PORT), timeout=TIMEOUT)
        self.sock.settimeout(TIMEOUT)
        self.buffer = ""
        self.next_id = 100

    def call(self, method, params=None):
        self.next_id += 1
        req = {"id": self.next_id, "method": method}
        if params is not None:
            req["params"] = params
        self.sock.sendall((json.dumps(req) + "\r\n").encode())
        return self._await_response(req["id"])

    def _await_response(self, want_id):
        """Le socket melange reponses et evenements : on filtre sur l'id."""
        deadline = time.time() + TIMEOUT
        while time.time() < deadline:
            while "\r\n" in self.buffer:
                line, self.buffer = self.buffer.split("\r\n", 1)
                if not line.strip():
                    continue
                try:
                    msg = json.loads(line)
                except json.JSONDecodeError:
                    continue
                if msg.get("id") == want_id:
                    return msg
            try:
                chunk = self.sock.recv(8192)
            except socket.timeout:
                break
            if not chunk:
                break
            self.buffer += chunk.decode(errors="replace")
        return None

    def close(self):
        self.sock.close()


def main():
    if len(sys.argv) > 1:
        hosts = [(sys.argv[1], "fourni en argument")]
    else:
        print("Recherche du Seestar (broadcast UDP scan_iscope + mDNS)...")
        hosts = discover()
        if not hosts:
            print(
                "Aucun Seestar trouve.\n"
                "  - allume-le et attends la fin du demarrage\n"
                "  - verifie qu'il est en mode station (rattache a ton Wi-Fi),\n"
                "    ou connecte-toi a son Wi-Fi S30_xxxx\n"
                "  - sinon relance avec l'IP en argument : python3 probe.py <ip>"
            )
            return 1

    for host, origin in hosts:
        print(f"\n=== {host} ({origin}) ===")
        try:
            scope = Control(host)
        except OSError as exc:
            print(f"  connexion au port {CONTROL_PORT} impossible : {exc}")
            continue

        print("  test_connection :", scope.call("test_connection"))

        state = scope.call("get_device_state")
        result = (state or {}).get("result", {})
        device = result.get("device", {})
        if device:
            print(f"  modele   : {device.get('name')} ({device.get('product_model')})")
            print(f"  firmware : {device.get('firmware_ver_string')}")
        else:
            print("  get_device_state :", json.dumps(state)[:400])

        verified = scope.call("pi_is_verified")
        print("  pi_is_verified :", verified)
        if verified and verified.get("result") is False:
            print(
                "  --> authentification exigee (firmware 7.18+).\n"
                "      La plupart des commandes echoueront sans cle d'interop\n"
                "      ou sans passer par seestar-proxy."
            )

        scope.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
