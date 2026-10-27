import os
import sys
from PIL import Image, ImageDraw

def generate_icons(master_path):
    if not os.path.exists(master_path):
        print(f"Master file not found at: {master_path}")
        return False

    img = Image.open(master_path).convert("RGBA")

    # 1. Android standard & round launcher mipmaps
    sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }

    # Android adaptive foreground sizes (108dp base)
    adaptive_sizes = {
        "mipmap-mdpi": 108,
        "mipmap-hdpi": 162,
        "mipmap-xhdpi": 216,
        "mipmap-xxhdpi": 324,
        "mipmap-xxxhdpi": 432,
    }

    base_res = "android/app/src/main/res"

    for folder, size in sizes.items():
        out_dir = os.path.join(base_res, folder)
        os.makedirs(out_dir, exist_ok=True)

        # Standard launcher icon
        resized = img.resize((size, size), Image.Resampling.LANCZOS)
        out_path = os.path.join(out_dir, "ic_launcher.png")
        resized.save(out_path, "PNG")

        # Circular icon for devices using round icons (ic_launcher_round.png)
        mask = Image.new("L", (size, size), 0)
        draw = ImageDraw.Draw(mask)
        draw.ellipse((0, 0, size, size), fill=255)

        round_img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        round_img.paste(resized, (0, 0), mask=mask)
        round_path = os.path.join(out_dir, "ic_launcher_round.png")
        round_img.save(round_path, "PNG")

        # Adaptive foreground icon
        fg_size = adaptive_sizes.get(folder, 108)
        fg_resized = img.resize((fg_size, fg_size), Image.Resampling.LANCZOS)
        fg_path = os.path.join(out_dir, "ic_launcher_foreground.png")
        fg_resized.save(fg_path, "PNG")
        print(f"Generated Android {folder}: ic_launcher ({size}x{size}), foreground ({fg_size}x{fg_size})")

    # 2. iOS AppIcon set
    ios_icons = {
        "Icon-App-20x20@1x.png": 20,
        "Icon-App-20x20@2x.png": 40,
        "Icon-App-20x20@3x.png": 60,
        "Icon-App-29x29@1x.png": 29,
        "Icon-App-29x29@2x.png": 58,
        "Icon-App-29x29@3x.png": 87,
        "Icon-App-40x40@1x.png": 40,
        "Icon-App-40x40@2x.png": 80,
        "Icon-App-40x40@3x.png": 120,
        "Icon-App-60x60@2x.png": 120,
        "Icon-App-60x60@3x.png": 180,
        "Icon-App-76x76@1x.png": 76,
        "Icon-App-76x76@2x.png": 152,
        "Icon-App-83.5x83.5@2x.png": 167,
        "Icon-App-1024x1024@1x.png": 1024,
    }

    ios_dir = "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    if os.path.exists(ios_dir):
        # iOS App Icons must be RGB (no alpha transparency)
        ios_img = img.convert("RGB")
        for filename, px in ios_icons.items():
            resized_ios = ios_img.resize((px, px), Image.Resampling.LANCZOS)
            out_ios_path = os.path.join(ios_dir, filename)
            resized_ios.save(out_ios_path, "PNG")
            print(f"Generated iOS {filename} ({px}x{px})")

    # 3. Branding assets
    os.makedirs("assets/branding", exist_ok=True)
    play_icon = img.resize((512, 512), Image.Resampling.LANCZOS)
    play_icon.save("assets/branding/playstore_icon_512.png", "PNG")
    img.save("assets/branding/app_icon_1024.png", "PNG")
    print("Saved master branding assets in assets/branding/")
    return True

if __name__ == "__main__":
    if len(sys.argv) > 1:
        generate_icons(sys.argv[1])
    else:
        print("Usage: python3 scripts/generate_app_icons.py <path_to_1024_icon>")
