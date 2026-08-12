# Seestar Viewer — visualiseur Apple TV, iPad et iPhone pour Seestar S30

**Date :** 2026-08-12
**Statut :** design validé, plan d'implémentation en attente de la session nocturne (§8)

## 1. Intention

Afficher l'image que le Seestar S30 est en train de construire, en plein écran et
pendant toute une session d'observation.

**Apple TV** est l'écran principal : **contemplatif**, on le lance, on le laisse
tourner des heures, on y jette un œil de temps en temps. **iPad et iPhone** sont les
écrans des autres spectateurs, pour que chacun suive la session sur son appareil
pendant que l'app officielle reste sur le téléphone qui pilote.

Le critère de réussite n'est pas la richesse fonctionnelle, c'est la **durabilité** :
une session de six heures sans intervention, sans écran noir, sans plantage.

### Ce que ce n'est pas

- Un contrôleur : l'app n'envoie aucune commande au télescope (voir §2).
- Un navigateur de galerie : les images passées ne sont pas au programme.
- Un remplaçant de l'app officielle, qui reste le pilote de la session.

## 2. Contrainte fondatrice : l'app est spectatrice

Mesuré sur le matériel le 2026-08-12, firmware exigeant l'authentification :

- Le port de contrôle **4700** verrouille l'intégralité du JSON-RPC derrière un
  challenge-response RSA. Les commandes non signées sont **ignorées en silence** —
  pas d'erreur, pas de code de refus. Seul `get_verify_str` répond.
- L'authentification est liée à **la connexion TCP**, pas à l'appareil : l'app
  officielle authentifiée n'ouvre rien pour les autres sockets. Vérifié en gardant
  un socket indépendant ouvert pendant que l'app officielle était connectée.
- Un socket qui envoie des commandes sans succès finit **coupé par le scope**
  (`Connection reset by peer`).
- Le flux d'événements du 4700 arrive en revanche **sans aucune authentification**.
- Le port d'imagerie **4800 n'est pas authentifié du tout** : `begin_streaming`
  est accepté et les trames arrivent.

**Conséquence de design :** l'app se connecte au 4700 en **lecture stricte** — elle
n'envoie jamais rien sur ce port, pas même un test de connexion — et pilote le 4800
uniquement par `begin_streaming`. C'est l'app officielle qui lance et arrête les vues.

## 3. Protocole, tel que mesuré

### Port 4700 — événements (lecture seule)

Lignes JSON terminées par `\r\n`. Événements observés et utiles :

| Événement | Champs exploités |
|---|---|
| `View` | `mode` (`scenery`, `star`…), `state`, `exp_ms` |
| `ContinuousExposure` | `state` (`working`), `fps` |
| `ScopeTrack` | `state`, `tracking`, `error` |
| `PiStatus` | `battery_capacity`, `temp`, `battery_temp` |

Le champ `View.mode` est le signal d'aiguillage : `star` signifie que le canal
d'imagerie va produire des trames ; `scenery` signifie qu'il restera muet.

### Port 4800 — imagerie

Commande d'amorçage, une seule fois par connexion :

```json
{"id": 21, "method": "begin_streaming"}
```

Réponses possibles, encapsulées dans le même cadrage binaire :
`done` (accepté) ou `only available for continuous exposure` (le scope n'est pas
en mode astro — état d'attente, pas une erreur).

Cadrage des trames : **en-tête de 80 octets**, dont les 20 premiers se décodent en
big-endian `>HHHIHHBBHH` → `(_, _, _, size, _, _, code, id, width, height)`,
suivis de `size` octets de payload.

| `id` | Contenu | Format |
|---|---|---|
| 21 | Preview live | buffer brut : `width×height×2` (Bayer) ou `width×height×6` (RGB) |
| 23 | Image empilée | archive ZIP, entrée `raw_data` |

**Mesuré en mode astro :** `id=21`, 1080×1920, 4 147 200 octets, soit exactement
2 octets par pixel — mosaïque de **Bayer 16 bits little-endian**, à ~1 trame/s
(≈ 4 Mo/s à encaisser).

### Port 4554 — RTSP

Ouvert **uniquement** en modes paysage et système solaire. H.264 High profile,
1080×1920, 30 fps. Hors périmètre v1 (voir §9).

## 4. Architecture

Client natif direct : chaque appareil parle au Seestar sans intermédiaire. Aucune
machine tierce à maintenir allumée — décision motivée par l'usage contemplatif, où
chaque maillon supplémentaire est une panne potentielle en pleine nuit.

> Cette architecture suppose que le télescope diffuse ses trames à plusieurs clients
> simultanés. C'est l'hypothèse 3 du §8, non encore validée, et la seule qui puisse
> remettre en cause l'approche. Le §8 décrit le repli.

### Découpage en cibles

Un **package Swift `SeestarKit`** rassemble les cinq unités sans interface, partagé
tel quel par toutes les plateformes. Deux cibles applicatives le consomment :
`SeestarTV` (tvOS) et `SeestarViewer` (iOS universel, iPhone et iPad). Seule la
présentation diffère ; aucune logique réseau ou de décodage n'est dupliquée.

Six unités au total. Règle structurante : **tout ce qui touche au réseau et au
décodage ignore SwiftUI**, et se teste donc sans écran ni télescope.

### `SeestarDiscovery`
Résout `seestar.local` via Bonjour, avec repli sur une adresse IP saisie dans les
réglages. Produit une `NWEndpoint`. Aucun état.

### `EventChannel`
Socket 4700 en lecture stricte. Découpe sur `\r\n`, décode le JSON, publie des
événements typés. **N'écrit jamais sur le socket.**

### `ImageChannel`
Socket 4800. Envoie `begin_streaming` une fois par connexion, puis lit en boucle
en-tête + payload. Publie des `RawFrame(id, width, height, data)` sans les interpréter.
Distingue les payloads texte (réponses du scope) des trames binaires.

### `FrameDecoder`
Fonction pure `RawFrame → CGImage`. Concentre toute la connaissance du format :
dézippage de `raw_data`, choix entre RGB 16 bits (`w×h×6`) et Bayer (`w×h×2`),
binning. C'est **la seule unité à modifier** quand les hypothèses de §8 seront levées.

### `Stretch`
Étirement d'histogramme, isolé délibérément : c'est lui qui décide si l'image est
belle, et celui qu'on voudra régler plus tard.

### `ViewerModel`
Arbitre l'image affichée, tient l'état, pilote les reconnexions. Seul point de
contact avec la couche SwiftUI.

## 5. Flux de données et arbitrage

Les deux canaux sont **indépendants** : si la télémétrie tombe, l'image continue,
et réciproquement. Aucun ne peut faire tomber l'autre.

L'arbitrage se fonde sur **l'arrivée réelle des trames**, pas sur les événements,
qui peuvent arriver en retard :

1. Une trame `id=23` arrive → elle passe à l'écran et devient l'image de référence.
2. Plus de trame `id=23` depuis deux fois l'intervalle observé entre subs → retour
   au live `id=21`.
3. Plus rien du tout → **on conserve la dernière image affichée**, avec une mention
   discrète de l'état. Jamais d'écran noir : c'est la règle d'or.

États : *Recherche → Connecté, en attente d'exposition → Live → Empilement → Connexion perdue*.
Le message `only available for continuous exposure` correspond à l'état « en attente »
et doit produire un écran explicatif calme, pas une alerte.

## 6. Rendu

### Orientation

Le capteur produit du portrait 1080×1920. **Dans le ciel il n'y a pas de haut** :
l'orientation n'a aucune signification physique, on peut donc tourner librement
l'image pour épouser l'écran. C'est une décision de **présentation**, prise par
chaque cible ; le cœur partagé livre l'image dans son orientation native et n'en
sait rien.

- **Apple TV** — rotation de 90°, donnant 1920×1080, soit exactement du 16/9.
  Aucune bande noire, aucun recadrage, aucune perte.
- **iPhone** — aucune rotation : le portrait natif tombe déjà dans le sens de
  l'écran.
- **iPad** — suit l'orientation de l'appareil, avec la même rotation qu'en tvOS
  lorsqu'il est tenu en paysage.

Conséquence : l'empilement, en pleine résolution, tombe pile sur 1920×1080 — exact sur
un téléviseur 1080p, doublement propre sur un 4K. Le live binné (960×540) est agrandi
×2, sans conséquence sur une preview bruitée.

Cette correspondance exacte suppose que les trames d'empilement font bien 1080×1920,
ce qui découle de l'hypothèse 2 du §8 et reste à confirmer. Le rendu ne doit donc pas
coder cette dimension en dur : il s'adapte aux dimensions annoncées dans l'en-tête.

### Décodage

**Empilement (`id=23`)** — dézippage, entrée `raw_data`, RGB 16 bits par canal,
directement consommable par `CGImage`. Chemin prioritaire, pleine résolution.

**Live (`id=21`)** — mosaïque de Bayer, traitée par **binning 2×2** plutôt que par
dématriçage : chaque bloc de 2×2 devient un pixel (R, moyenne des deux G, B). Pas
d'interpolation donc aucun artefact, bruit réduit, code trivial. On perd la moitié de
la résolution, sans importance pour un affichage télévisé.

### Étirement

Méthode classique des logiciels astro, appliquée **canal par canal** (ce qui corrige
au passage la dominante de couleur) :

1. médiane et écart absolu médian sur un sous-échantillon (1 pixel sur 16) ;
2. point noir `c0 = médiane − 2,8 × MAD` ;
3. point médian par fonction de transfert de tons, cible de fond 0,25 ;
4. application via une table de correspondance 16 bits → 8 bits.

Une image astro linéaire affichée telle quelle est **quasiment noire** : cette étape
n'est pas cosmétique, elle est indispensable.

L'implémentation de référence est `decode_frame.py`, validée sur trames réelles.
Elle sert d'**oracle** aux tests Swift.

## 7. Robustesse

Reconnexion **indépendante** par canal, délai exponentiel plafonné à 30 s. La fermeture
de socket par le scope est un comportement normal à absorber silencieusement.

**Mise en veille.** Neutraliser le minuteur d'inactivité pendant l'affichage : sur
Apple TV, faute de quoi l'Aerial recouvre l'image en quelques minutes ; sur iPhone et
iPad, faute de quoi l'écran se verrouille.

**Passage en arrière-plan (iOS uniquement).** Le système suspend les sockets dès que
l'app quitte le premier plan. On ferme proprement les deux canaux à la mise en
arrière-plan et on les rouvre au retour, plutôt que de laisser le système trancher des
connexions à moitié mortes. L'Apple TV n'est pas concernée.

**Rémanence.** Image fixe pendant des heures sur un téléviseur OLED : dérive très lente
de quelques pixels de l'image et de l'incrustation, imperceptible mais suffisante.

**Mémoire.** Une trame pèse ~4 Mo, à ~1/s. On n'en garde jamais plus d'une en vol et
une à l'écran : toute trame arrivant pendant un traitement en cours est **jetée**, pas
mise en file. Une file qui gonfle est un plantage à 3 h du matin.

**Données inattendues.** Toute trame dont la taille ne correspond à aucun format connu
est journalisée puis ignorée. L'app ne meurt jamais sur une donnée surprenante.

**Réseau local.** `NSLocalNetworkUsageDescription` et `NSBonjourServices` sont
obligatoires dans l'`Info.plist` : sans eux, les connexions échouent silencieusement.

## 8. Hypothèses à lever

Trois points n'ont pas pu être validés en plein jour. Les deux premiers sont confinés
au `FrameDecoder` ; le troisième engage l'architecture.

1. **Motif de Bayer GRBG.** Retenu d'après le code de seestar_alp. La trame capturée
   est saturée à 57 %, donc dépourvue d'information de couleur. À confirmer sur une
   trame nocturne ; `decode_frame.py --patterns` produit le comparatif des quatre motifs.
2. **Format des trames d'empilement.** L'encapsulation ZIP et l'entrée `raw_data`
   viennent également du code de seestar_alp, jamais observées ici. Le décodeur gérera
   les deux cas, ZIP compressé et ZIP stocké.

3. **Diffusion à plusieurs clients simultanés.** Le port 4700 accepte des connexions
   multiples et diffuse les événements à toutes — mesuré. Le port 4800 accepte lui
   aussi plusieurs connexions et répond `done` à chacune, mais **rien ne prouve encore
   qu'il envoie les trames à tous** : le test a été mené sur un scope au repos, donc
   non concluant.

   *Repli si la diffusion est exclusive :* un relais léger sur un Mac ou un Raspberry
   Pi prend l'unique flux et le redistribue. Pour que ce repli ne soit pas une
   réécriture, `ImageChannel` est défini derrière une **interface de transport** dont
   la connexion directe n'est qu'une implémentation. Le reste de `SeestarKit` ne voit
   pas la différence. L'Apple TV redeviendrait alors dépendante d'une machine allumée —
   régression assumée, mais seulement si la mesure l'impose.

Une session nocturne de stacking lève les trois d'un coup : voir `night_session.py`.

## 9. Hors périmètre v1

- **RTSP / mode paysage.** Le canal 4800 est muet en mode `scenery` : l'app n'affichera
  rien dans ce mode. Assumé, l'usage visé étant l'astro. L'architecture permet d'ajouter
  un troisième canal sans rien casser.
- **Envoi de commandes.** Nécessiterait `seestar-proxy` et un bootstrap d'authentification
  à chaque session.
- **Galerie des sessions passées.**

## 10. Tests

**Jeux d'essai réels.** Trames capturées le 2026-08-12 dans `fixtures/`, avec le flux
d'événements correspondant. Tout le décodage se teste dessus.

**Fonctions pures.** Découpage d'en-tête (dont en-tête tronqué et taille aberrante),
extraction ZIP, choix du format selon la taille, étirement déterministe sur image
synthétique. Comparaison des sorties avec l'oracle `decode_frame.py`.

**Faux Seestar.** Petit serveur Python rejouant l'enregistrement sur les ports 4700 et
4800. Permet de développer en plein jour sans télescope et de provoquer à volonté les
pannes à gérer : coupure brutale, trame corrompue, réponse `only available for
continuous exposure`.

**Intégration.** Perte de connexion en cours d'affichage, bascule empilement ↔ live,
absence prolongée de trames.

## 11. Outils déjà en place

| Fichier | Rôle |
|---|---|
| `probe.py` | Diagnostic : découverte, état, détection de l'authentification |
| `capture_frames.py` | Capture de trames et d'événements vers `fixtures/` |
| `decode_frame.py` | Implémentation de référence du décodage, oracle des tests |
| `night_session.py` | Lève les trois hypothèses du §8 en une session nocturne |
