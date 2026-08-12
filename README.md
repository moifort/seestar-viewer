# Seestar Viewer

Visualiseur Apple TV, iPad et iPhone pour le télescope ZWO Seestar S30.
Affiche en plein écran l'image en cours d'empilement, sur le réseau local.

L'app est **spectatrice** : elle n'envoie aucune commande au télescope, qui
reste piloté par l'application officielle. Le firmware verrouille les commandes
derrière une authentification RSA liée à la connexion TCP — voir la spec.

## État

`SeestarKit`, le cœur, est implémenté et testé : découpage des deux flux,
décodage des trames, étirement d'histogramme, transport, arbitrage.
Les applications restent à écrire.

## Documents

- Design : `docs/superpowers/specs/2026-08-12-seestar-tvos-viewer-design.md`
- Plan du cœur : `docs/superpowers/plans/2026-08-12-seestarkit-core.md`

## Outils

| Commande | Rôle |
|---|---|
| `python3 probe.py` | Diagnostic : découverte, état, authentification |
| `python3 capture_frames.py <ip>` | Capture de trames vers `fixtures/` |
| `python3 decode_frame.py <trame> --patterns` | Décodage de référence |
| `python3 night_session.py <ip>` | Lève les hypothèses restantes |
| `python3 Tools/fake_seestar.py` | Faux télescope pour développer sans matériel |

## Tests

```bash
swift test
```

Aucun test n'ouvre de socket : les analyseurs sont alimentés par les trames
réelles capturées dans `fixtures/`. Le test de parité vérifie que le décodage
Swift produit les mêmes pixels que l'oracle Python `decode_frame.py`.

## Protocole, tel que mesuré

| Port | Rôle | Authentification |
|---|---|---|
| 4700 | Événements (lecture seule) | aucune |
| 4700 | Commandes JSON-RPC | **exigée**, par connexion TCP |
| 4800 | Trames d'image | aucune |
| 4554 | RTSP H.264 | ouvert en mode paysage uniquement |
