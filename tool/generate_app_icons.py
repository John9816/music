#!/usr/bin/env python3
"""Generate every platform app icon from the shared branding image."""

from pathlib import Path
import sys

from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/branding/app_icon.png"
RESAMPLE = Image.Resampling.LANCZOS


def resized(source: Image.Image, size: int, *, rgb: bool = False) -> Image.Image:
    image = source.resize((size, size), RESAMPLE)
    return image.convert("RGB" if rgb else "RGBA")


def save_png(source: Image.Image, size: int, path: Path, *, rgb: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    resized(source, size, rgb=rgb).save(path, format="PNG", optimize=True)


def main() -> None:
    if not SOURCE.is_file():
        raise SystemExit(f"Missing source icon: {SOURCE}")

    source = Image.open(SOURCE).convert("RGBA")
    if source.width != source.height:
        raise SystemExit("The source icon must be square")

    android_sizes = {
        "mipmap-mdpi": 48,
        "mipmap-hdpi": 72,
        "mipmap-xhdpi": 96,
        "mipmap-xxhdpi": 144,
        "mipmap-xxxhdpi": 192,
    }
    for density, size in android_sizes.items():
        directory = ROOT / "android/app/src/main/res" / density
        save_png(source, size, directory / "ic_launcher.png")
        save_png(source, size, directory / "ic_launcher_round.png")

    ios_directory = ROOT / "ios/Runner/Assets.xcassets/AppIcon.appiconset"
    ios_sizes = {
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
    for filename, size in ios_sizes.items():
        save_png(source, size, ios_directory / filename, rgb=True)

    macos_directory = ROOT / "macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        save_png(source, size, macos_directory / f"app_icon_{size}.png")

    windows_icon = ROOT / "windows/runner/resources/app_icon.ico"
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
    source.save(
        windows_icon,
        format="ICO",
        sizes=[(size, size) for size in (16, 24, 32, 48, 64, 128, 256)],
    )

    print("Generated Android, iOS, macOS, and Windows app icons.")


if __name__ == "__main__":
    try:
        main()
    except Exception as error:
        print(f"Icon generation failed: {error}", file=sys.stderr)
        raise
