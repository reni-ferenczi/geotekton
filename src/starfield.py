import random
from pathlib import Path

from PIL import Image, ImageDraw

PROJECT_DIR = Path(__file__).parent.parent.resolve()
ASSETS_DIR = PROJECT_DIR / "Assets"
TEXTURES_DIR = ASSETS_DIR / "Textures"


def create_starfield(width=8192, height=4096, num_stars=250000):
    # Create a solid black canvas
    img = Image.new("RGB", (width, height), color=(0, 0, 0))
    draw = ImageDraw.Draw(img)

    for _ in range(num_stars):
        # Random position
        x = random.randint(0, width)
        y = random.randint(0, height)

        # Randomize star size (mostly 1px, some up to 3px for depth)
        star_size = random.choices([1, 2, 3], weights=[85, 12, 3])[0]

        # Randomize brightness (mostly bright white, some slight blue/yellow tints)
        brightness = random.randint(1, 85 * star_size)
        color_tint = random.choice([
            (brightness, brightness, brightness),  # Pure White
            (brightness - 20, brightness - 10, brightness),  # Slight Blue
            (brightness, brightness, brightness - 20),  # Slight Yellow
        ])

        if star_size == 1:
            draw.point((x, y), fill=color_tint)
        else:
            # Draw a small disc for larger "closer" stars
            r = star_size - 1
            draw.ellipse([x - r, y - r, x + r, y + r], fill=color_tint)

    # Save as high-quality PNG
    output_filename = TEXTURES_DIR / "Starfield.png"
    img.save(output_filename, "PNG")
    print(f"Success! Image saved as {output_filename}")


if __name__ == "__main__":
    create_starfield()
