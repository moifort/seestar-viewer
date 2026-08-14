#!/usr/bin/env python3
"""Peint la nebuleuse d'Orion pour le fond d'ecran tvOS.

    python3 Tools/make_nebula.py [Tools/nebula-source.png]

Rien n'est photographie. Le nuage est un bruit fractal, deforme par un autre
bruit pour lui donner ses filaments, decoupe en lobes pour lui donner la forme
de M42 : le coeur du Trapeze, l'aile qui s'ouvre vers la droite, la Bouche du
Poisson qui l'entaille par le haut, M43 en boule detachee, et l'Homme qui court
en tache bleue a l'ecart. La couleur suit la physique de loin : l'hydrogene rose
domine la peripherie, l'oxygene turquoise le voisinage des etoiles chaudes, et
le coeur sature vers le blanc parce qu'il est simplement trop lumineux.

Le format est celui de la plus large des deux images d'etagere (2320x720), en
triple resolution : les autres tailles s'y recadrent sans jamais manquer de
pixels.
"""

import sys

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter, map_coordinates

WIDTH, HEIGHT = 3480, 1080
SEED = 20240814

# Le bruit est toujours tire sur cette grille, puis reechantillonne vers la
# taille demandee. Sans cela, changer de resolution changerait le tirage, donc
# le dessin des nuages : la meme graine ne donnerait plus la meme nebuleuse.
REFERENCE = (540, 1740)

# Couleurs lineaires, avant courbe de rendu.
HYDROGEN = np.array([1.00, 0.24, 0.42])   # Ha, le rose des bords
OXYGEN = np.array([0.34, 0.88, 0.82])     # OIII, le turquoise du coeur
FURNACE = np.array([1.00, 0.86, 0.68])    # la lueur blanche du Trapeze
REFLECTION = np.array([0.38, 0.50, 1.00])  # la poussiere bleue qui reflechit


def fractal_noise(rng, beta):
    """Bruit en 1/f^beta : des nuages a toutes les echelles a la fois.

    On tire du bruit blanc, on l'attenue dans le domaine de Fourier selon la
    frequence, et on revient. Plus beta est grand, plus les grandes structures
    l'emportent sur le grain.
    """
    spectrum = np.fft.rfft2(rng.normal(size=REFERENCE))
    ky = np.fft.fftfreq(REFERENCE[0])[:, None]
    kx = np.fft.rfftfreq(REFERENCE[1])[None, :]
    k = np.hypot(kx, ky)
    k[0, 0] = 1.0
    field = np.fft.irfft2(spectrum * k ** (-beta), s=REFERENCE)
    # On cale sur les percentiles plutot que sur les extremes : une seule valeur
    # aberrante suffirait sinon a ecraser tout le reste du champ.
    low, high = np.percentile(field, (2, 98))
    field = np.clip((field - low) / max(high - low, 1e-9), 0, 1)
    return resample(field)


def resample(field):
    """Etire un champ de la grille de reference vers la taille de sortie."""
    if field.shape == (HEIGHT, WIDTH):
        return field
    rows = np.linspace(0, field.shape[0] - 1, HEIGHT)
    columns = np.linspace(0, field.shape[1] - 1, WIDTH)
    grid = np.meshgrid(rows, columns, indexing="ij")
    return map_coordinates(field, grid, order=3, mode="nearest")


def coordinates():
    """Repere centre sur l'image, une unite = la demi-hauteur."""
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH].astype(np.float32)
    half = HEIGHT / 2
    return (x - WIDTH / 2) / half, (y - half) / half


def lobe(x, y, center, size, angle=0.0, power=2.0):
    """Une tache elliptique orientee, a bords doux."""
    radians = np.deg2rad(angle)
    cos, sin = np.cos(radians), np.sin(radians)
    dx, dy = x - center[0], y - center[1]
    u = (dx * cos + dy * sin) / size[0]
    v = (-dx * sin + dy * cos) / size[1]
    return np.exp(-(np.abs(u) ** power + np.abs(v) ** power))


def warp(field, rng, amount):
    """Deforme un champ par un autre bruit : les nuages y gagnent leurs volutes."""
    shift_x = (fractal_noise(rng, 3.2) - 0.5) * amount
    shift_y = (fractal_noise(rng, 3.2) - 0.5) * amount
    y, x = np.mgrid[0:HEIGHT, 0:WIDTH]
    return map_coordinates(field, [y + shift_y, x + shift_x], order=1, mode="reflect")


def nebula_density(rng):
    """L'epaisseur du gaz en chaque point, entre 0 et 1 environ."""
    x, y = coordinates()

    # La silhouette de M42 : un coeur, une aile qui s'ouvre, un halo tres large.
    shape = (
        1.00 * lobe(x, y, (-0.15, 0.02), (0.34, 0.30), 0, 2.0)
        + 0.72 * lobe(x, y, (0.16, 0.10), (0.82, 0.40), -12, 1.6)
        + 0.55 * lobe(x, y, (-0.55, 0.16), (0.55, 0.34), 24, 1.6)
        + 0.16 * lobe(x, y, (0.02, 0.02), (1.25, 0.62), -8, 1.4)
        + 0.42 * lobe(x, y, (-0.62, -0.42), (0.20, 0.18), 0, 2.4)   # M43
    )

    # Le nuage lui-meme, deforme puis pose sur la silhouette. Deux echelles de
    # bruit : les grandes masses, et les filaments qui les strient.
    cloud = warp(0.65 * fractal_noise(rng, 2.1) + 0.35 * fractal_noise(rng, 1.5),
                 rng, 0.09 * HEIGHT)
    # Le contraste fait tout : sans lui, un bruit centre ne donne que de la
    # brume uniforme. On etire la plage utile et on ecrase le bas.
    cloud = np.clip((cloud - 0.34) / 0.42, 0, 1) ** 1.9
    density = shape * (0.06 + 1.35 * cloud)

    # Les bandes de poussiere, qui eteignent le gaz au lieu de s'y ajouter.
    dust = warp(fractal_noise(rng, 2.3), rng, 0.05 * HEIGHT)
    density *= 1.0 - 0.92 * np.clip((dust - 0.44) * 4.0, 0, 1)

    # La Bouche du Poisson : l'entaille sombre qui descend vers le Trapeze.
    mouth = lobe(x, y, (-0.34, -0.30), (0.30, 0.26), -35, 1.8)
    density *= 1.0 - 0.80 * mouth
    return np.clip(density, 0, None)


def paint(density, rng):
    """Donne sa couleur au gaz, selon la distance aux etoiles qui l'excitent."""
    x, y = coordinates()

    # Pres du Trapeze le gaz est ionise plus profondement : l'oxygene y prend le
    # dessus sur l'hydrogene. On interpole entre les deux teintes.
    heat = np.exp(-((x + 0.15) ** 2 + (y - 0.02) ** 2) / (2 * 0.26 ** 2))
    tint = HYDROGEN * (1 - heat)[..., None] + OXYGEN * heat[..., None]
    image = tint * (density * (0.55 + 1.35 * heat))[..., None]

    # L'Homme qui court : une nebuleuse par reflexion, donc bleue, et fendue par
    # la bande de poussiere qui lui donne son nom.
    runner = lobe(x, y, (1.24, -0.16), (0.24, 0.26), 10, 1.4)
    cloud = np.clip((warp(fractal_noise(rng, 2.0), rng, 0.06 * HEIGHT) - 0.36) / 0.40, 0, 1)
    runner *= cloud ** 1.5
    runner *= 1.0 - 0.85 * lobe(x, y, (1.26, -0.10), (0.030, 0.22), 8, 1.6)
    image += REFLECTION * (0.55 * runner)[..., None]

    # La fournaise centrale, qui deborde de son propre gaz. Elle doit rester
    # etroite : large, elle avale la nebuleuse et n'en laisse qu'une boule.
    glow = np.exp(-((x + 0.15) ** 2 + (y - 0.02) ** 2) / (2 * 0.065 ** 2))
    image += FURNACE * (0.55 * glow)[..., None]
    return image


def star_color(rng):
    """Du bleu-blanc au jaune-orange, avec une majorite de blancs."""
    t = rng.beta(2.0, 2.0) * 2 - 1
    return np.array([1.0 + 0.22 * t, 1.0 - 0.02 * abs(t), 1.0 - 0.30 * t])


def add_star(image, cx, cy, brightness, color, sigma, spikes=0.0):
    """Pose une etoile : un noyau gaussien, et pour les plus vives, des aigrettes."""
    length = 0.022 * HEIGHT * spikes
    reach = int(np.ceil(sigma * 4 + 3 * length))
    x0, x1 = max(0, int(cx) - reach), min(WIDTH, int(cx) + reach + 1)
    y0, y1 = max(0, int(cy) - reach), min(HEIGHT, int(cy) + reach + 1)
    if x0 >= x1 or y0 >= y1:
        return
    yy, xx = np.mgrid[y0:y1, x0:x1]
    dx, dy = xx - cx, yy - cy
    profile = np.exp(-(dx ** 2 + dy ** 2) / (2 * sigma ** 2))
    if spikes > 0:
        for angle in (45, 135):
            radians = np.deg2rad(angle)
            u = dx * np.cos(radians) + dy * np.sin(radians)
            v = -dx * np.sin(radians) + dy * np.cos(radians)
            profile += 0.35 * spikes * np.exp(-np.abs(u) / length) * \
                np.exp(-(v ** 2) / (2 * (sigma * 0.45) ** 2))
    image[y0:y1, x0:x1] += color * (brightness * profile)[..., None]


def add_stars(image, rng, density):
    """Le champ d'etoiles, plus dense au centre ou l'amas est ne."""
    x, y = coordinates()
    cluster = np.exp(-((x + 0.15) ** 2 + (y - 0.02) ** 2) / (2 * 0.55 ** 2))

    unit = HEIGHT / 1080  # les tailles sont reglees pour 1080 de haut
    for _ in range(2600):
        cx, cy = rng.uniform(0, WIDTH), rng.uniform(0, HEIGHT)
        # Un tirage de plus au centre : l'amas y concentre ses membres.
        if rng.random() > 0.30 + 0.70 * cluster[int(cy), int(cx)]:
            continue
        # Loi de puissance : beaucoup de faibles, tres peu de vives.
        brightness = 10 ** rng.uniform(-2.0, -0.15)
        add_star(image, cx, cy, brightness, star_color(rng),
                 unit * (0.9 + 2.6 * brightness),
                 spikes=max(0.0, brightness - 0.35))

    # Le Trapeze : quatre etoiles serrees, celles qui allument toute la nebuleuse.
    cx, cy = WIDTH / 2 - 0.15 * HEIGHT / 2, HEIGHT / 2 + 0.02 * HEIGHT / 2
    for dx, dy, brightness in ((-13, -8, 0.9), (8, -12, 0.6),
                               (15, 9, 0.75), (-7, 14, 0.5)):
        add_star(image, cx + dx * unit, cy + dy * unit, brightness,
                 np.array([1.0, 0.97, 0.90]), 2.2 * unit, spikes=0.9 * brightness)


def render():
    rng = np.random.default_rng(SEED)
    density = nebula_density(rng)
    image = paint(density, rng)
    add_stars(image, rng, density)

    # Le halo diffus des optiques. Il ne doit partir que des zones deja vives :
    # applique a toute l'image, il noie la structure sous une brume uniforme.
    unit = HEIGHT / 1080
    bright = np.clip(image - 0.55, 0, None)
    image += 0.45 * gaussian_filter(bright, (14 * unit, 14 * unit, 0))
    image += 0.30 * gaussian_filter(bright, (55 * unit, 55 * unit, 0))

    # Les bords s'eteignent : le fond doit rester sombre sous le titre tvOS.
    x, y = coordinates()
    image *= (1 - 0.30 * np.clip((np.abs(x) / 1.6) ** 2, 0, 1))[..., None]

    # Courbe de rendu : la lumiere s'accumule sans jamais depasser le blanc, ce
    # qui sature le coeur de lui-meme, puis passage en sRGB.
    image = 1 - np.exp(-image * 1.35)
    image = np.clip(image, 0, 1) ** (1 / 2.2)

    # Un ciel jamais tout a fait noir, legerement bleute.
    image = image + np.array([0.008, 0.011, 0.024]) * (1 - image)
    return Image.fromarray((np.clip(image, 0, 1) * 255).astype(np.uint8), "RGB")


def main():
    path = sys.argv[1] if len(sys.argv) > 1 else "Tools/nebula-source.png"
    render().save(path)
    print(f"Nebuleuse ecrite dans {path} ({WIDTH}x{HEIGHT})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
