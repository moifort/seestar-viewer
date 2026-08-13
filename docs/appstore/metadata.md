# Fiche App Store — Seestar Companion

> **À relire avant saisie.** Rien n'a encore été enregistré dans App Store Connect.
> Les compteurs entre parenthèses indiquent la limite imposée par Apple.

## Paramètres généraux

| Champ | Valeur proposée |
|---|---|
| Nom | Seestar Companion (17 / 30) |
| Identifiant | `fr.thibaut.SeestarCompanion` |
| Plateformes | iOS, iPadOS, tvOS — une seule fiche |
| Langue principale | Anglais (États-Unis) |
| Langues supplémentaires | Français |
| Catégorie principale | Photo et vidéo |
| Catégorie secondaire | Éducation |
| Classification d'âge | 4+ |
| Prix | Gratuit |
| URL d'assistance | https://github.com/moifort/seestar-viewer |
| URL de confidentialité | https://moifort.github.io/seestar-viewer/privacy/ |
| Collecte de données | Aucune |

**Point d'attention pour la revue.** La mention de non-affiliation figure dès la
deuxième ligne de la description, dans les deux langues. C'est le premier
élément que regardera le vérificateur, la marque Seestar appartenant à ZWO.

---

## Anglais (États-Unis)

### Subtitle (25 / 30)

```
Watch your telescope live
```

### Promotional text (129 / 170)

```
Use your Apple TV, iPad and iPhone as companions to your Seestar telescope,
to share what it sees with your family and your guests.
```

### Keywords (90 / 100)

```
astronomy,telescope,astrophotography,stargazing,nebula,live view,smart telescope,sky,stars
```

### Description

```
Seestar Companion turns your Apple TV, iPad and iPhone into extra screens,
so you can share what your telescope sees.

This is an independent, unofficial app. It is not made by, endorsed by or
affiliated with ZWO, the maker of the Seestar.

Connect to your telescope with the official Seestar app, then open Seestar
Companion: it automatically shows what the telescope sees.

Please note: this only works if the telescope and your other devices are
connected to the same Wi-Fi network.
```

### What's New (version 1.0)

```
First release.
```

---

## Français

### Sous-titre (25 / 30)

```
Votre télescope en direct
```

### Texte promotionnel (157 / 170)

```
Utilisez votre Apple TV, votre iPad et votre iPhone comme compagnons de votre
télescope Seestar, pour partager ce qu'il voit avec votre famille ou vos invités.
```

### Mots-clés (86 / 100)

```
astronomie,télescope,astrophotographie,ciel,étoiles,nébuleuse,direct,observation,nuit
```

### Description

```
Seestar Companion transforme votre Apple TV, votre iPad et votre iPhone en
écrans supplémentaires, afin de partager ce que voit votre télescope.

Application indépendante et non officielle. Elle n'est ni éditée, ni
approuvée, ni affiliée par ZWO, le fabricant du Seestar.

Connectez-vous à votre télescope avec l'application officielle Seestar, puis
lancez Seestar Companion : elle affiche automatiquement ce que voit le
télescope.

Attention : cela ne fonctionne que si le télescope et les autres appareils
sont connectés au même réseau Wi-Fi.
```

### Nouveautés (version 1.0)

```
Première version.
```

---

## Captures d'écran

| Appareil | Taille exigée | État |
|---|---|---|
| Apple TV | 3840×2160 | l'éclipse partielle capturée sur le matériel |
| iPhone 6,9" | 1320×2868 | `screenshots/iphone-69-{en,fr}.png` |
| iPad 13" | 2064×2752 | `screenshots/ipad-13-{en,fr}.png` |

Les captures iPhone et iPad sont prises face au faux télescope, par
`Tools/make_screenshots.sh`. Les trois trames enregistrées étant brûlées —
médiane égale au maximum, l'auto-stretch n'a plus qu'un gradient de bruit à
étirer — le faux télescope rejoue l'éclipse du 12 août via `--image`, qui
remosaïque l'image en Bayer. L'aller-retour est exact au bit près : le fond
est assez uniforme pour que le MAD soit nul et que l'étirement laisse l'image
intacte. Ce qu'affiche la capture est donc bien le rendu de l'app sur une
image venue du télescope.

La télémétrie indique 102 % de batterie sur deux des quatre captures. C'est la
valeur que le S30 émet lui-même en charge, reprise telle quelle du flux
d'événements enregistré ; l'overlay s'effaçant après quelques secondes, on ne
choisit pas l'instant de la capture.
