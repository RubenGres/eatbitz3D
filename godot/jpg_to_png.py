#!/usr/bin/env python3
"""
Process images in-place:
  - Convert all formats → PNG
  - Resize images to fit within a max side length (aspect ratio preserved)
Usage:
  python process_images_to_png.py /path/to/images --max-side 1920
  python process_images_to_png.py /path/to/images --max-side 1024 --recursive
"""
import argparse
import sys
from pathlib import Path
from PIL import Image

SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tiff", ".tif"}


def process_image(path: Path, max_side: int | None) -> None:
    try:
        img = Image.open(path)
    except Exception as e:
        print(f"  [skip] Cannot open {path}: {e}")
        return

    changed = False
    out_path = path

    # --- Resize ---
    if max_side and max(img.size) > max_side:
        img.thumbnail((max_side, max_side), Image.LANCZOS)
        changed = True
        print(f"  resized → {img.size}")

    # --- Convert to PNG ---
    if path.suffix.lower() != ".png":
        out_path = path.with_suffix(".png")

        # Preserve RGBA if source has transparency, otherwise use RGBA to be safe
        if img.mode == "P":
            img = img.convert("RGBA")
        elif img.mode not in ("RGBA", "RGB", "LA", "L"):
            img = img.convert("RGBA")

        img.save(out_path, "PNG", optimize=True)
        path.unlink()  # remove original
        print(f"  →png     {path.name} → {out_path.name}")
        return

    # --- Already PNG: save in-place if resized ---
    if changed:
        img.save(out_path, "PNG", optimize=True)
        print(f"  saved    {out_path.name}")
    else:
        print(f"  ok       {path.name} (no changes)")


def collect_images(root: Path, recursive: bool) -> list[Path]:
    pattern = "**/*" if recursive else "*"
    return sorted(
        p for p in root.glob(pattern)
        if p.is_file() and p.suffix.lower() in SUPPORTED_EXTS
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="Convert all images to PNG in-place.")
    parser.add_argument("directory", type=Path, help="Directory containing images")
    parser.add_argument(
        "--max-side", type=int, default=None, metavar="PX",
        help="Maximum side length in pixels (aspect ratio preserved)"
    )
    parser.add_argument(
        "--recursive", "-r", action="store_true",
        help="Process subdirectories recursively"
    )
    args = parser.parse_args()

    if not args.directory.is_dir():
        sys.exit(f"Error: '{args.directory}' is not a directory.")

    images = collect_images(args.directory, args.recursive)
    if not images:
        print("No supported images found.")
        return

    print(f"Found {len(images)} image(s) in '{args.directory}'\n")
    for img_path in images:
        print(f"→ {img_path.relative_to(args.directory)}")
        process_image(img_path, args.max_side)

    print("\nDone.")


if __name__ == "__main__":
    main()