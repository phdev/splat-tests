#!/usr/bin/env python3
"""Extract sharp, non-duplicate training frames from a source video."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def require_imports():
    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore
        from PIL import Image, ImageDraw  # type: ignore
    except Exception as exc:
        raise SystemExit(
            "Missing Python image dependencies. Install with:\n"
            "  python3 -m pip install --user numpy pillow opencv-python-headless\n"
            f"Original import error: {exc}"
        )
    return cv2, np, Image, ImageDraw


def run(cmd: list[str]) -> None:
    print("+", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def ahash(gray, np) -> int:
    small = cv2_resize(gray, (8, 8))
    avg = float(small.mean())
    bits = small > avg
    out = 0
    for bit in bits.flatten():
        out = (out << 1) | int(bool(bit))
    return out


def cv2_resize(arr, size):
    import cv2  # local import after dependency check

    return cv2.resize(arr, size, interpolation=cv2.INTER_AREA)


def hamming(a: int, b: int) -> int:
    return (a ^ b).bit_count()


def contact_sheet(image_paths: list[Path], output: Path, Image, ImageDraw, max_images: int = 80) -> None:
    if not image_paths:
        return
    sample = image_paths
    if len(sample) > max_images:
        step = len(sample) / max_images
        sample = [image_paths[int(i * step)] for i in range(max_images)]

    thumbs = []
    for path in sample:
        im = Image.open(path).convert("RGB")
        im.thumbnail((240, 135))
        canvas = Image.new("RGB", (240, 160), "white")
        canvas.paste(im, ((240 - im.width) // 2, 0))
        ImageDraw.Draw(canvas).text((6, 140), path.name, fill=(0, 0, 0))
        thumbs.append(canvas)

    cols = 5
    rows = math.ceil(len(thumbs) / cols)
    sheet = Image.new("RGB", (cols * 240, rows * 160), "white")
    for i, thumb in enumerate(thumbs):
        sheet.paste(thumb, ((i % cols) * 240, (i // cols) * 160))
    output.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(output, quality=92)


def main() -> None:
    cv2, np, Image, ImageDraw = require_imports()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=Path("data/sources/pexels_machu_picchu/source.mp4"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/processed/close"))
    parser.add_argument("--fps", type=float, default=2.0)
    parser.add_argument("--max-width", type=int, default=1920)
    parser.add_argument("--blur-threshold", type=float, default=35.0)
    parser.add_argument("--duplicate-hash-threshold", type=int, default=1)
    parser.add_argument("--min-selected", type=int, default=150)
    parser.add_argument("--quality", type=int, default=92)
    args = parser.parse_args()

    if not args.source.is_file():
        raise SystemExit(f"Missing source video: {args.source}")

    out_dir = args.output_dir
    image_dir = out_dir / "images"
    if image_dir.exists():
        shutil.rmtree(image_dir)
    image_dir.mkdir(parents=True)

    with tempfile.TemporaryDirectory(prefix="pexels_frames_") as tmp:
        tmp_dir = Path(tmp)
        vf = f"fps={args.fps}"
        if args.max_width > 0:
            vf += f",scale='min({args.max_width},iw)':-2"
        run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(args.source), "-vf", vf, str(tmp_dir / "candidate_%06d.jpg")])

        selected: list[Path] = []
        rejected = []
        previous_hashes: list[int] = []
        candidates = sorted(tmp_dir.glob("candidate_*.jpg"))
        for idx, path in enumerate(candidates, start=1):
            img = cv2.imread(str(path), cv2.IMREAD_COLOR)
            if img is None:
                rejected.append({"candidate": path.name, "reason": "decode_failed"})
                continue
            gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
            blur = float(cv2.Laplacian(gray, cv2.CV_64F).var())
            if blur < args.blur_threshold:
                rejected.append({"candidate": path.name, "reason": "blurry", "laplacian_variance": blur})
                continue
            phash = ahash(gray, np)
            if previous_hashes and min(hamming(phash, prev) for prev in previous_hashes[-8:]) <= args.duplicate_hash_threshold:
                rejected.append({"candidate": path.name, "reason": "near_duplicate", "laplacian_variance": blur})
                continue
            output = image_dir / f"frame_{len(selected) + 1:06d}.jpg"
            cv2.imwrite(str(output), img, [int(cv2.IMWRITE_JPEG_QUALITY), args.quality])
            previous_hashes.append(phash)
            selected.append(output)

    contact_path = out_dir / "frame_contact_sheet.jpg"
    contact_sheet(selected, contact_path, Image, ImageDraw)
    report = {
        "source": str(args.source),
        "fps": args.fps,
        "candidate_frames": len(candidates),
        "selected_frames": len(selected),
        "rejected_frames": len(rejected),
        "blur_threshold": args.blur_threshold,
        "duplicate_hash_threshold": args.duplicate_hash_threshold,
        "images_dir": str(image_dir),
        "contact_sheet": str(contact_path),
        "rejections": rejected[:2000],
    }
    (out_dir / "frame_filter_report.json").write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in report if k != "rejections"}, indent=2))
    if len(selected) < args.min_selected:
        raise SystemExit(
            f"Only {len(selected)} selected frames survived filtering; need at least {args.min_selected}. "
            "Increase --fps, lower --blur-threshold, or lower duplicate rejection."
        )


if __name__ == "__main__":
    main()
