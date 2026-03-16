#!/usr/bin/env python3
"""
Process images in-place:
  - Convert PNG → JPG
  - Resize images to fit within a max side length (aspect ratio preserved)

Usage:
  python process_images.py /path/to/images --max-side 1920
  python process_images.py /path/to/images --max-side 1024 --quality 85 --recursive
"""

import argparse
import sys
from pathlib import Path
from PIL import Image


SUPPORTED_EXTS = {".png", ".jpg", ".jpeg", ".webp", ".bmp", ".tiff", ".tif"}


def process_image(path: Path, max_side: int | None, quality: int) -> None:
    try:
        img = Image.open(path)
    except Exception as e:
        print(f"  [skip] Cannot open {path}: {e}")
        return

    original_mode = img.mode
    changed = False
    out_path = path

    # --- Resize ---
    if max_side and max(img.size) > max_side:
        img.thumbnail((max_side, max_side), Image.LANCZOS)
        changed = True
        print(f"  resized → {img.size}")

    # --- PNG → JPG conversion ---
    if path.suffix.lower() == ".png":
        out_path = path.with_suffix(".jpg")
        # Flatten transparency onto white background
        if img.mode in ("RGBA", "LA", "P"):
            background = Image.new("RGB", img.size, (255, 255, 255))
            if img.mode == "P":
                img = img.convert("RGBA")
            background.paste(img, mask=img.split()[-1] if img.mode in ("RGBA", "LA") else None)
            img = background
        elif img.mode != "RGB":
            img = img.convert("RGB")
        img.save(out_path, "JPEG", quality=quality, optimize=True)
        path.unlink()  # remove original PNG
        print(f"  png→jpg  {path.name} → {out_path.name}")
        return

    # --- Save in-place for other formats (if resized) ---
    if changed:
        fmt = img.format or "JPEG"
        save_kwargs = {}
        if fmt in ("JPEG", "JPG") or out_path.suffix.lower() in (".jpg", ".jpeg"):
            fmt = "JPEG"
            save_kwargs = {"quality": quality, "optimize": True}
            if img.mode != "RGB":
                img = img.convert("RGB")
        img.save(out_path, fmt, **save_kwargs)
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
    parser = argparse.ArgumentParser(description="Convert and resize images in-place.")
    parser.add_argument("directory", type=Path, help="Directory containing images")
    parser.add_argument(
        "--max-side", type=int, default=None, metavar="PX",
        help="Maximum side length in pixels (aspect ratio preserved)"
    )
    parser.add_argument(
        "--quality", type=int, default=90, metavar="1-95",
        help="JPEG quality (default: 90)"
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
        process_image(img_path, args.max_side, args.quality)

    print("\nDone.")


if __name__ == "__main__":
    main()