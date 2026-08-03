from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / "Marketing" / "Steam" / "CircularStudios"
FONT_PATH = ROOT / "Assets" / "Capital Bold - Normal.ttf"

INK = (7, 10, 15, 255)
INK_2 = (10, 16, 23, 255)
ICE = (223, 247, 255, 255)
CYAN = (79, 195, 220, 255)
CYAN_SHADOW = (23, 103, 128, 255)
GOLD = (240, 209, 125, 255)
MUTED = (104, 125, 139, 255)


def nearest(image: Image.Image, size: tuple[int, int]) -> Image.Image:
    return image.resize(size, Image.Resampling.NEAREST)


def make_pixel_mark(base_size: int = 46, background: tuple[int, int, int, int] | None = None) -> Image.Image:
    image = Image.new("RGBA", (base_size, base_size), background or (0, 0, 0, 0))
    pixels = image.load()
    center = (base_size - 1) * 0.5
    scale = base_size / 32.0
    outer_radius = 11.5 * scale
    inner_radius = 7.4 * scale
    for y in range(base_size):
        for x in range(base_size):
            distance = math.dist((x, y), (center, center))
            if abs(distance - outer_radius) <= 1.45 * scale:
                pixels[x, y] = ICE
            elif abs(distance - inner_radius) <= 0.82 * scale:
                pixels[x, y] = CYAN
            elif distance <= 1.85 * scale:
                pixels[x, y] = GOLD
    return image


def centered_text(draw: ImageDraw.ImageDraw, text: str, font: ImageFont.FreeTypeFont, y: int, fill, shadow=None) -> None:
    bounds = draw.textbbox((0, 0), text, font=font, stroke_width=0)
    width = bounds[2] - bounds[0]
    x = (draw._image.size[0] - width) // 2
    if shadow:
        draw.text((x, y + 3), text, font=font, fill=shadow)
    draw.text((x, y), text, font=font, fill=fill)


def make_wordmark_master() -> Image.Image:
    base = Image.new("RGBA", (512, 128), (0, 0, 0, 0))
    draw = ImageDraw.Draw(base)
    font = ImageFont.truetype(str(FONT_PATH), 37)
    centered_text(draw, "CIRCULAR STUDIOS", font, 42, ICE, CYAN_SHADOW)
    return nearest(base, (2048, 512))


def make_logo(size: int, transparent: bool = False) -> Image.Image:
    base_size = 46
    base = Image.new("RGBA", (base_size, base_size), (0, 0, 0, 0) if transparent else INK)
    mark = make_pixel_mark(base_size)
    base.alpha_composite(mark)
    return nearest(base, (size, size))


def draw_faint_ring(draw: ImageDraw.ImageDraw, center: tuple[int, int], radius: int, color, width: int = 2) -> None:
    cx, cy = center
    for offset in range(width):
        draw.ellipse((cx - radius - offset, cy - radius - offset, cx + radius + offset, cy + radius + offset), outline=color)


def make_header() -> Image.Image:
    # Build at half resolution and upscale with nearest-neighbor for crisp pixels.
    width, height = 750, 110
    image = Image.new("RGBA", (width, height), INK)
    draw = ImageDraw.Draw(image)

    for y in range(0, height, 18):
        for x in range(0, width, 18):
            if (x // 18 + y // 18) % 2 == 0:
                draw.rectangle((x, y, x + 17, y + 17), fill=(10, 16, 23, 90))

    draw_faint_ring(draw, (105, 55), 43, (37, 108, 128, 70), 2)
    draw_faint_ring(draw, (105, 55), 29, (79, 195, 220, 42), 1)
    draw_faint_ring(draw, (646, 55), 50, (37, 108, 128, 58), 2)
    draw_faint_ring(draw, (646, 55), 34, (240, 209, 125, 28), 1)

    rng = random.Random(0xC1AC01A)
    particle_colors = [(79, 195, 220, 90), (223, 247, 255, 70), (240, 209, 125, 90), (104, 125, 139, 70)]
    for _ in range(42):
        x = rng.randrange(24, width - 24)
        y = rng.randrange(8, height - 8)
        radius = rng.choice((1, 1, 1, 2))
        draw.rectangle((x, y, x + radius, y + radius), fill=rng.choice(particle_colors))

    # The page supplies the company name itself; this subtle center motif avoids
    # duplicating that text behind Steam's header UI.
    center_mark = nearest(make_pixel_mark(32), (64, 64))
    center_mark.putalpha(38)
    image.alpha_composite(center_mark, ((width - 64) // 2, (height - 64) // 2))
    return nearest(image, (1500, 220))


def make_brand_preview() -> Image.Image:
    width, height = 1500, 844
    image = Image.new("RGBA", (width, height), INK)
    draw = ImageDraw.Draw(image)
    for y in range(0, height, 64):
        for x in range(0, width, 64):
            if (x // 64 + y // 64) % 2 == 0:
                draw.rectangle((x, y, x + 63, y + 63), fill=INK_2)
    mark = make_logo(220, transparent=True)
    image.alpha_composite(mark, ((width - 220) // 2, 205))
    font = ImageFont.truetype(str(FONT_PATH), 82)
    centered_text(draw, "CIRCULAR STUDIOS", font, 450, ICE, CYAN_SHADOW)
    small_font = ImageFont.truetype(str(FONT_PATH), 26)
    centered_text(draw, "INDEPENDENT GAMES", small_font, 565, MUTED)
    return image


def save_jpeg(image: Image.Image, path: Path) -> None:
    flattened = Image.new("RGB", image.size, INK[:3])
    if image.mode == "RGBA":
        flattened.paste(image.convert("RGB"), mask=image.getchannel("A"))
    else:
        flattened.paste(image.convert("RGB"))
    flattened.save(path, "JPEG", quality=95, subsampling=0, optimize=True)


def main() -> None:
    OUTPUT.mkdir(parents=True, exist_ok=True)

    mark_master = make_logo(2048, transparent=True)
    mark_master.save(OUTPUT / "circular_studios_mark_master_2048.png", optimize=True)
    make_wordmark_master().save(OUTPUT / "circular_studios_wordmark_master_2048x512.png", optimize=True)

    creator_logo = make_logo(184)
    creator_logo.save(OUTPUT / "steam_creator_logo_184x184.png", optimize=True)
    save_jpeg(creator_logo, OUTPUT / "steam_community_avatar_184x184.jpg")

    header = make_header()
    header.save(OUTPUT / "steam_creator_header_1500x220.png", optimize=True)
    save_jpeg(header, OUTPUT / "steam_creator_header_1500x220.jpg")

    # Reusable high-resolution community/social avatar.
    make_logo(512).save(OUTPUT / "circular_studios_avatar_512x512.png", optimize=True)
    make_brand_preview().save(OUTPUT / "circular_studios_brand_preview_1500x844.png", optimize=True)

    for path in sorted(OUTPUT.glob("*")):
        if path.is_file():
            print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
