#!/usr/bin/env python3
"""Fabrique les catalogues d'icones iOS et tvOS a partir d'une seule image source.

    python3 Tools/make_icons.py Tools/icon-source.png [Tools/nebula-source.png]

iOS se contente d'un carre de 1024. tvOS est plus exigeant : il veut du 5:3,
decompose en couches superposees pour l'effet de parallaxe, plus une banniere
d'accueil. On separe donc le croissant du ciel par un masque de luminance :
le ciel devient le plan arriere, le croissant le plan avant, et le systeme
les fait glisser l'un sur l'autre quand l'icone prend le focus.
"""

import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageEnhance, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
INFO = {"author": "xcode", "version": 1}


def write_json(path, payload):
    with open(path, "w") as fh:
        json.dump(payload, fh, indent=2)


def fresh(path):
    shutil.rmtree(path, ignore_errors=True)
    os.makedirs(path, exist_ok=True)
    return path


def split_layers(source: Image.Image, floor: float = 0.05):
    """Separe le sujet du ciel, par ecart au fond estime.

    Un simple seuil de luminance ne marche que pour un sujet nettement plus
    clair que le fond. Il echoue sur du verre pale pose sur un degrade a peine
    plus sombre. On estime donc le fond par un flou tres large, puis on garde
    ce qui s'en ecarte : la methode tient quel que soit le contraste.
    """
    rgb = np.asarray(source.convert("RGB")).astype(np.float32)
    radius = max(source.size) // 8
    background = np.asarray(
        source.convert("RGB").filter(ImageFilter.GaussianBlur(radius))
    ).astype(np.float32)

    def normalise(values):
        return np.clip(values / max(np.percentile(values, 99.5), 1e-6), 0, 1)

    # Deux lectures possibles du sujet, selon l'image.
    by_contrast = normalise(np.abs(rgb - background).sum(axis=2))
    # Un ciel est bleu, un appareil gris ou noir est neutre : l'ecart de teinte
    # separe ce que la luminosite seule ne distingue pas.
    blueness = rgb[:, :, 2] - (rgb[:, :, 0] + rgb[:, :, 1]) / 2
    by_hue = normalise(np.abs(blueness - np.median(blueness)))

    # On retient celle qui detache une part plausible de l'image : un masque
    # quasi vide ou quasi plein signale que le critere ne s'applique pas ici.
    #
    # Le plancher doit rester bas. Une constellation n'occupe que 1,25 % de
    # l'icone : avec un plancher a 6 %, le contraste etait ecarte alors qu'il
    # isolait exactement les etoiles, et la teinte prenait le relais en
    # selectionnant le degrade du ciel. Le plan avant devenait une plaque
    # semi-transparente, que tvOS ombrait pendant le parallaxe.
    def plausible(mask):
        return 0.005 <= (mask > 0.5).mean() <= 0.65

    alpha = by_contrast if plausible(by_contrast) else (
        by_hue if plausible(by_hue) else np.maximum(by_contrast, by_hue))
    # Adoucit les bords sans ronger le sujet.
    alpha = np.asarray(
        Image.fromarray((alpha * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(3))
    ).astype(np.float32) / 255

    # Un voile de quelques pourcents subsiste sur toute la zone du sujet.
    # Invisible a l'oeil, il suffit a faire porter une ombre carree par tvOS
    # pendant le parallaxe : l'ombre vient de l'alpha, pas de la couleur. On
    # soustrait donc ce plancher, en reetalant ce qui reste pour ne pas
    # eteindre les halos. Sur un fond d'ecran, ou le sujet est pose sur un ciel
    # d'une autre teinte que le sien, le meme voile dessine un carre : il y faut
    # un plancher plus haut.
    alpha = np.clip((alpha - floor) / (1 - floor), 0, 1)

    front = np.dstack([rgb, alpha * 255]).astype(np.uint8)
    sky = source.convert("RGB").filter(ImageFilter.GaussianBlur(radius))
    return Image.fromarray(front, "RGBA"), sky


def sky_canvas(sky: Image.Image, width: int, height: int) -> Image.Image:
    """Etire le ciel au format demande, en gardant son centre."""
    ratio = max(width / sky.width, height / sky.height)
    resized = sky.resize((int(sky.width * ratio) + 1, int(sky.height * ratio) + 1),
                         Image.LANCZOS)
    left = (resized.width - width) // 2
    top = (resized.height - height) // 2
    return resized.crop((left, top, left + width, top + height))


def compose(front: Image.Image, sky: Image.Image, width: int, height: int,
            subject_ratio: float) -> Image.Image:
    """Pose le croissant, centre, sur un ciel au bon format."""
    canvas = sky_canvas(sky, width, height).convert("RGBA")
    target = int(min(width, height) * subject_ratio)
    scaled = front.resize((target, target), Image.LANCZOS)
    canvas.alpha_composite(scaled, ((width - target) // 2, (height - target) // 2))
    return canvas.convert("RGB")


def imageset(path, image, idiom="tv", scale="1x"):
    fresh(path)
    image.save(os.path.join(path, "image.png"))
    write_json(os.path.join(path, "Contents.json"), {
        "images": [{"filename": "image.png", "idiom": idiom, "scale": scale}],
        "info": INFO,
    })


def imagestack(path, layers):
    """Une pile de couches : la premiere est au premier plan."""
    fresh(path)
    names = []
    for name, image in layers:
        layer_dir = fresh(os.path.join(path, f"{name}.imagestacklayer"))
        write_json(os.path.join(layer_dir, "Contents.json"), {"info": INFO})
        imageset(os.path.join(layer_dir, "Content.imageset"), image)
        names.append({"filename": f"{name}.imagestacklayer"})
    write_json(os.path.join(path, "Contents.json"), {"layers": names, "info": INFO})


def build_ios(front, sky, source):
    catalog = fresh(os.path.join(ROOT, "Apps/SeestarViewer/Assets.xcassets"))
    write_json(os.path.join(catalog, "Contents.json"), {"info": INFO})
    icon = fresh(os.path.join(catalog, "AppIcon.appiconset"))
    source.convert("RGB").resize((1024, 1024), Image.LANCZOS).save(
        os.path.join(icon, "icon-1024.png"))
    write_json(os.path.join(icon, "Contents.json"), {
        "images": [{"filename": "icon-1024.png", "idiom": "universal",
                    "platform": "ios", "size": "1024x1024"}],
        "info": INFO,
    })
    print("iOS  : AppIcon 1024x1024")


def banner_canvas(source: Image.Image, width: int, height: int) -> Image.Image:
    """Ajuste l'image d'accueil aux formats de l'etagere du haut.

    Une image deja large est un fond d'ecran : elle se recadre, sans plus. Une
    image carree, elle, doit etre etendue, et la coller telle quelle laisserait
    voir son carre puisque son ciel n'a pas la teinte du fond. On la detoure
    alors comme pour l'icone, et on l'expose sur son propre ciel etire.
    """
    if source.width / source.height >= 2:
        return sky_canvas(source, width, height)

    front, sky = split_layers(source, floor=0.12)

    # Le ciel etire sert de decor : assombri, il laisse le sujet ressortir et
    # garde le fond assez sombre pour le texte que tvOS pose par-dessus.
    canvas = ImageEnhance.Brightness(sky_canvas(sky, width, height)).enhance(0.62)
    canvas = canvas.convert("RGBA")

    # Le sujet deborde legerement en hauteur : ses pointes sont diagonales, donc
    # loin des bords, et le cadre parait mieux rempli.
    target = int(height * 1.05)
    canvas.alpha_composite(front.resize((target, target), Image.LANCZOS),
                           ((width - target) // 2, (height - target) // 2))
    return canvas.convert("RGB")


def build_tvos(front, sky, banner=None):
    catalog = fresh(os.path.join(ROOT, "Apps/SeestarTV/Assets.xcassets"))
    write_json(os.path.join(catalog, "Contents.json"), {"info": INFO})
    brand = fresh(os.path.join(catalog, "App Icon & Top Shelf Image.brandassets"))

    # Les deux tailles d'icone, chacune en deux plans.
    for name, (w, h) in {"App Icon": (400, 240),
                         "App Icon - App Store": (1280, 768)}.items():
        back = sky_canvas(sky, w, h).convert("RGB")
        # Le plan avant garde sa transparence : c'est elle qui laisse voir le
        # ciel glisser dessous pendant le parallaxe.
        transparent = Image.new("RGBA", (w, h), (0, 0, 0, 0))
        target = int(min(w, h) * 0.78)
        transparent.alpha_composite(front.resize((target, target), Image.LANCZOS),
                                    ((w - target) // 2, (h - target) // 2))
        imagestack(os.path.join(brand, f"{name}.imagestack"),
                   [("Front", transparent), ("Back", back)])
        print(f"tvOS : {name} {w}x{h}, 2 couches")

    for name, (w, h) in {"Top Shelf Image": (1920, 720),
                         "Top Shelf Image Wide": (2320, 720)}.items():
        if banner is not None:
            image = banner_canvas(banner, w, h)
        else:
            image = compose(front, sky, w, h, 0.55)
        imageset(os.path.join(brand, f"{name}.imageset"), image)
        print(f"tvOS : {name} {w}x{h}")

    write_json(os.path.join(brand, "Contents.json"), {
        "assets": [
            {"filename": "App Icon - App Store.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "1280x768"},
            {"filename": "App Icon.imagestack", "idiom": "tv",
             "role": "primary-app-icon", "size": "400x240"},
            {"filename": "Top Shelf Image Wide.imageset", "idiom": "tv",
             "role": "top-shelf-image-wide", "size": "2320x720"},
            {"filename": "Top Shelf Image.imageset", "idiom": "tv",
             "role": "top-shelf-image", "size": "1920x720"},
        ],
        "info": INFO,
    })


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    source = Image.open(sys.argv[1]).convert("RGB")
    banner = Image.open(sys.argv[2]).convert("RGB") if len(sys.argv) > 2 else None
    front, sky = split_layers(source)
    build_ios(front, sky, source)
    build_tvos(front, sky, banner)
    print("\nCatalogues ecrits dans Apps/SeestarViewer et Apps/SeestarTV.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
