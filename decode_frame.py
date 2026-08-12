#!/usr/bin/env python3
"""Implementation de reference du decodage d'une trame Seestar.

Reproduit en Python l'algorithme prevu pour l'app tvOS, afin de servir
d'oracle aux tests Swift :
    buffer 16 bits -> binning 2x2 du Bayer -> etirement auto -> RGB 8 bits

Usage:
    python3 decode_frame.py fixtures/frame_21_000_1080x1920.bin [--patterns]
"""

import sys

import numpy as np
from PIL import Image

# Position des composantes dans chaque bloc 2x2, par motif de Bayer.
# Indices : (ligne, colonne) dans le bloc.
PATTERNS = {
    "GRBG": {"R": (0, 1), "G": [(0, 0), (1, 1)], "B": (1, 0)},
    "RGGB": {"R": (0, 0), "G": [(0, 1), (1, 0)], "B": (1, 1)},
    "BGGR": {"R": (1, 1), "G": [(0, 1), (1, 0)], "B": (0, 0)},
    "GBRG": {"R": (1, 0), "G": [(0, 0), (1, 1)], "B": (0, 1)},
}


def load_raw(path, width, height):
    """Lit le buffer brut et le presente en matrice (hauteur, largeur)."""
    data = np.fromfile(path, dtype="<u2")
    expected = width * height
    if data.size != expected:
        raise ValueError(
            f"{data.size} echantillons lus, {expected} attendus "
            f"pour {width}x{height} en 16 bits"
        )
    return data.reshape(height, width)


def bin2x2(raw, pattern="GRBG"):
    """Reduit la mosaique de Bayer en RGB demi-resolution, sans dematricage.

    Chaque bloc 2x2 devient un pixel : pas d'interpolation, donc aucun
    artefact, et le bruit baisse. On perd la moitie de la resolution, ce qui
    est sans consequence pour un affichage televiseur.
    """
    pos = PATTERNS[pattern]
    blocks = raw[: raw.shape[0] // 2 * 2, : raw.shape[1] // 2 * 2]
    quadrant = lambda r, c: blocks[r::2, c::2].astype(np.float32)

    r = quadrant(*pos["R"])
    b = quadrant(*pos["B"])
    g = (quadrant(*pos["G"][0]) + quadrant(*pos["G"][1])) / 2.0
    return np.stack([r, g, b], axis=-1) / 65535.0


def mtf(x, m):
    """Fonction de transfert de tons (midtone transfer function)."""
    denom = (2.0 * m - 1.0) * x - m
    out = np.divide((m - 1.0) * x, denom, out=np.zeros_like(x), where=denom != 0)
    return np.clip(out, 0.0, 1.0)


def autostretch(rgb, target_bg=0.25, shadow_clip=-2.8):
    """Etirement automatique facon Siril/PixInsight, canal par canal.

    Une image astro lineaire est quasiment noire : sans cette etape, l'ecran
    reste vide. Le traitement par canal corrige au passage la dominante
    de couleur.
    """
    out = np.empty_like(rgb)
    for c in range(3):
        chan = rgb[..., c]
        sample = chan[::4, ::4]  # sous-echantillonnage : stats ~16x plus rapides
        median = float(np.median(sample))
        mad = float(np.median(np.abs(sample - median))) * 1.4826
        if mad <= 0:
            out[..., c] = chan
            continue
        c0 = float(np.clip(median + shadow_clip * mad, 0.0, 1.0))
        span = max(1.0 - c0, 1e-6)
        midtone = mtf(np.array((median - c0) / span, dtype=np.float32), target_bg)
        normalized = np.clip((chan - c0) / span, 0.0, 1.0)
        out[..., c] = mtf(normalized, float(np.clip(midtone, 1e-4, 1 - 1e-4)))
    return out


def to_image(rgb):
    return Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), mode="RGB")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    path = sys.argv[1]
    width, height = 1080, 1920
    raw = load_raw(path, width, height)

    print(f"brut       : {raw.shape[1]}x{raw.shape[0]}, 16 bits")
    print(f"valeurs    : min={raw.min()} max={raw.max()} median={int(np.median(raw))}")
    print(f"saturation : {100.0 * np.mean(raw >= 65535):.2f}% de pixels satures")

    if "--patterns" in sys.argv:
        # Comparatif des 4 motifs de Bayer, pour verifier lequel donne
        # des couleurs justes.
        tiles = []
        for name in PATTERNS:
            img = to_image(autostretch(bin2x2(raw, name)))
            img.thumbnail((320, 320))
            tiles.append((name, img))
        w, h = tiles[0][1].size
        sheet = Image.new("RGB", (w * 4, h))
        for i, (name, img) in enumerate(tiles):
            sheet.paste(img, (i * w, 0))
        sheet.save("fixtures/bayer_patterns.png")
        print("comparatif des motifs -> fixtures/bayer_patterns.png (ordre : "
              + ", ".join(PATTERNS) + ")")

    rgb = autostretch(bin2x2(raw, "GRBG"))
    out = to_image(rgb)
    out.save("fixtures/decoded.png")
    print(f"decode     : {out.size[0]}x{out.size[1]} -> fixtures/decoded.png")
    return 0


if __name__ == "__main__":
    sys.exit(main())
