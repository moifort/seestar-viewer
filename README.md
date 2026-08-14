# Seestar Companion

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
| `swift run seestar-probe <hote> <secondes>` | Vérification de bout en bout de SeestarKit sur sockets réels |

## Tests

```bash
swift test
```

Aucun test n'ouvre de socket : les analyseurs sont alimentés par les trames
réelles capturées dans `fixtures/`. Le test de parité vérifie que le décodage
Swift produit les mêmes pixels que l'oracle Python `decode_frame.py`.

## Publication

Un tag publie les deux plateformes ensemble, puisqu'une seule fiche App Store
les porte :

```bash
git tag v1.0 && git push --tags
```

`.github/workflows/release.yml` lance la suite de tests, régénère le projet avec
XcodeGen — `Seestar.xcodeproj` est gitignoré —, archive iOS puis tvOS, et envoie
les deux binaires à App Store Connect. La version affichée vient du tag, le
numéro de build du nombre de commits : il croît sans jamais reculer et ne
demande aucun état.

Trois secrets sont nécessaires, tous issus d'une clé API App Store Connect de
rôle App Manager :

| Secret | Contenu |
|---|---|
| `ASC_KEY_ID` | l'identifiant de la clé, dix caractères |
| `ASC_ISSUER_ID` | l'identifiant d'émetteur, un UUID |
| `ASC_KEY_P8` | le contenu du fichier `.p8`, tel quel |

La signature reste automatique : `-allowProvisioningUpdates` laisse Xcode créer
certificat et profil via cette même clé, ce qui évite de stocker un `.p12`. Si
l'endpoint de provisionnement se met à répondre 401, il faudra basculer sur une
signature manuelle avec certificat importé.

`workflow_dispatch` permet un essai à blanc : `skip_upload` archive et exporte
sans rien envoyer, et le `.ipa` reste récupérable en artefact.

## Protocole, tel que mesuré

| Port | Rôle | Authentification |
|---|---|---|
| 4700 | Événements (lecture seule) | aucune |
| 4700 | Commandes JSON-RPC | **exigée**, par connexion TCP |
| 4800 | Trames d'image | aucune |
| 4554 | RTSP H.264 | ouvert en mode paysage uniquement |
