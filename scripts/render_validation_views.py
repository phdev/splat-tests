#!/usr/bin/env python3
"""Create close-scene validation view artifacts and a contact sheet."""

from __future__ import annotations

import argparse
import json
import math
import shutil
import struct
import subprocess
import tempfile
from pathlib import Path
from typing import Iterable


PLY_TYPES = {
    "char": ("b", 1),
    "uchar": ("B", 1),
    "int8": ("b", 1),
    "uint8": ("B", 1),
    "short": ("h", 2),
    "ushort": ("H", 2),
    "int16": ("h", 2),
    "uint16": ("H", 2),
    "int": ("i", 4),
    "uint": ("I", 4),
    "int32": ("i", 4),
    "uint32": ("I", 4),
    "float": ("f", 4),
    "float32": ("f", 4),
    "double": ("d", 8),
    "float64": ("d", 8),
}


def require_pillow():
    try:
        from PIL import Image, ImageDraw
    except Exception as exc:
        raise SystemExit(
            "Missing Pillow. Install with:\n  python3 -m pip install --user pillow\n"
            f"Original import error: {exc}"
        )
    return Image, ImageDraw


def vec_add(a: Iterable[float], b: Iterable[float]) -> list[float]:
    return [x + y for x, y in zip(a, b)]


def vec_sub(a: Iterable[float], b: Iterable[float]) -> list[float]:
    return [x - y for x, y in zip(a, b)]


def vec_mul(a: Iterable[float], scale: float) -> list[float]:
    return [x * scale for x in a]


def vec_dot(a: Iterable[float], b: Iterable[float]) -> float:
    return sum(x * y for x, y in zip(a, b))


def vec_cross(a: list[float], b: list[float]) -> list[float]:
    return [
        a[1] * b[2] - a[2] * b[1],
        a[2] * b[0] - a[0] * b[2],
        a[0] * b[1] - a[1] * b[0],
    ]


def vec_len(a: Iterable[float]) -> float:
    return math.sqrt(sum(x * x for x in a))


def vec_norm(a: list[float], fallback: list[float]) -> list[float]:
    length = vec_len(a)
    return vec_mul(a, 1.0 / length) if length > 1e-8 else fallback[:]


def rotate_about_axis(v: list[float], axis: list[float], degrees: float) -> list[float]:
    theta = math.radians(degrees)
    c = math.cos(theta)
    s = math.sin(theta)
    axis = vec_norm(axis, [0.0, 1.0, 0.0])
    return vec_add(
        vec_add(vec_mul(v, c), vec_mul(vec_cross(axis, v), s)),
        vec_mul(axis, vec_dot(axis, v) * (1.0 - c)),
    )


def fmt_vec(v: Iterable[float]) -> str:
    return ",".join(f"{x:.6g}" for x in v)


def ply_bounds(path: Path) -> tuple[list[float], list[float], int]:
    with path.open("rb") as fh:
        header_lines = []
        while True:
            line = fh.readline()
            if not line:
                raise RuntimeError(f"{path} has no PLY end_header")
            header_lines.append(line.decode("ascii", errors="replace").strip())
            if header_lines[-1] == "end_header":
                break

        fmt = next((line.split()[1] for line in header_lines if line.startswith("format ")), None)
        if fmt not in {"ascii", "binary_little_endian", "binary_big_endian"}:
            raise RuntimeError(f"Unsupported PLY format in {path}: {fmt}")

        vertex_count = 0
        properties: list[tuple[str, str]] = []
        in_vertex = False
        for line in header_lines:
            parts = line.split()
            if len(parts) >= 3 and parts[0] == "element":
                in_vertex = parts[1] == "vertex"
                if in_vertex:
                    vertex_count = int(parts[2])
                continue
            if in_vertex and len(parts) >= 3 and parts[0] == "property" and parts[1] != "list":
                properties.append((parts[2], parts[1]))

        if vertex_count <= 0:
            raise RuntimeError(f"No vertex element found in {path}")
        prop_names = [name for name, _typ in properties]
        xyz_idx = [prop_names.index(name) for name in ("x", "y", "z")]
        mins = [float("inf"), float("inf"), float("inf")]
        maxs = [float("-inf"), float("-inf"), float("-inf")]

        if fmt == "ascii":
            for _ in range(vertex_count):
                values = fh.readline().decode("ascii", errors="replace").split()
                xyz = [float(values[i]) for i in xyz_idx]
                for i, value in enumerate(xyz):
                    mins[i] = min(mins[i], value)
                    maxs[i] = max(maxs[i], value)
        else:
            endian = "<" if fmt == "binary_little_endian" else ">"
            row_fmt = endian + "".join(PLY_TYPES[typ][0] for _name, typ in properties)
            row_size = struct.calcsize(row_fmt)
            for _ in range(vertex_count):
                row = fh.read(row_size)
                if len(row) != row_size:
                    raise RuntimeError(f"Unexpected EOF reading vertices from {path}")
                values = struct.unpack(row_fmt, row)
                xyz = [float(values[i]) for i in xyz_idx]
                for i, value in enumerate(xyz):
                    mins[i] = min(mins[i], value)
                    maxs[i] = max(maxs[i], value)
        return mins, maxs, vertex_count


def settings_camera(settings_path: Path, mins: list[float], maxs: list[float]) -> tuple[list[float], list[float], float]:
    center = [(lo + hi) / 2.0 for lo, hi in zip(mins, maxs)]
    radius = max(vec_len(vec_sub(maxs, mins)) / 2.0, 1.0)
    fallback = ([center[0] + radius * 0.85, center[1] + radius * 0.45, center[2] - radius * 1.15], center, 70.0)
    if not settings_path.is_file():
        return fallback
    try:
        settings = json.loads(settings_path.read_text())
        initial = settings["cameras"][0]["initial"]
        position = [float(v) for v in initial["position"]]
        target = [float(v) for v in initial["target"]]
        fov = float(initial.get("fov", 70))
    except Exception:
        return fallback
    if vec_len(vec_sub(position, target)) < 1e-6:
        return fallback
    return position, target, fov


def validation_views(position: list[float], target: list[float], fov: float, radius: float) -> dict[str, dict]:
    forward = vec_norm(vec_sub(target, position), [0.0, 0.0, 1.0])
    right = vec_norm(vec_cross(forward, [0.0, 1.0, 0.0]), [1.0, 0.0, 0.0])
    up = vec_norm(vec_cross(right, forward), [0.0, 1.0, 0.0])
    scale = max(radius * 0.035, 0.05)
    views = {
        "hero": (position, target),
        "left": (vec_add(position, vec_mul(right, -0.35 * scale)), vec_add(target, vec_mul(right, -0.35 * scale))),
        "right": (vec_add(position, vec_mul(right, 0.35 * scale)), vec_add(target, vec_mul(right, 0.35 * scale))),
        "up": (vec_add(position, vec_mul(up, 0.25 * scale)), vec_add(target, vec_mul(up, 0.25 * scale))),
        "down": (vec_add(position, vec_mul(up, -0.25 * scale)), vec_add(target, vec_mul(up, -0.25 * scale))),
        "forward": (vec_add(position, vec_mul(forward, 0.30 * scale)), vec_add(target, vec_mul(forward, 0.30 * scale))),
        "back": (vec_add(position, vec_mul(forward, -0.30 * scale)), vec_add(target, vec_mul(forward, -0.30 * scale))),
        "source_match": (position, target),
    }
    distance = vec_len(vec_sub(target, position))
    for i, degrees in enumerate([-30, -15, 0, 15, 30], start=1):
        direction = rotate_about_axis(forward, up, degrees)
        views[f"yaw_{i:02d}"] = (position, vec_add(position, vec_mul(direction, distance)))
    return {label: {"camera": cam, "look_at": look, "fov": fov} for label, (cam, look) in views.items()}


def render_splat_views(splat: Path, settings: Path, output_dir: Path, Image, ImageDraw) -> tuple[list[Path], dict]:
    if not splat.is_file():
        raise RuntimeError(f"missing splat export: {splat}")
    if not shutil.which("npx"):
        raise RuntimeError("npx is not available for @playcanvas/splat-transform rendering")

    mins, maxs, vertex_count = ply_bounds(splat)
    center = [(lo + hi) / 2.0 for lo, hi in zip(mins, maxs)]
    radius = max(vec_len(vec_sub(maxs, mins)) / 2.0, 1.0)
    position, target, fov = settings_camera(settings, mins, maxs)
    views = validation_views(position, target, fov, radius)
    written: list[Path] = []

    with tempfile.TemporaryDirectory(prefix="close_splat_render_") as td:
        tmp = Path(td)
        for label, view in views.items():
            webp = tmp / f"{label}.webp"
            cmd = [
                "npx",
                "-y",
                "@playcanvas/splat-transform",
                str(splat),
                str(webp),
                "-w",
                "--camera",
                fmt_vec(view["camera"]),
                "--look-at",
                fmt_vec(view["look_at"]),
                "--fov",
                f"{view['fov']:.6g}",
                "--resolution",
                "1280x720",
                "--background",
                "0.4,0.4,0.4,1",
            ]
            subprocess.run(cmd, check=True)
            dst = output_dir / f"{label}.png"
            im = Image.open(webp).convert("RGB")
            draw = ImageDraw.Draw(im)
            draw.rectangle((0, 0, min(im.width, 760), 48), fill=(0, 0, 0))
            draw.text((14, 14), f"{label} | trained PLY render", fill=(255, 255, 255))
            dst.parent.mkdir(parents=True, exist_ok=True)
            im.save(dst)
            written.append(dst)

    metadata = {
        "method": "splat-transform render from trained PLY",
        "splat": str(splat),
        "vertex_count": vertex_count,
        "bounds": {"min": mins, "max": maxs, "center": center, "radius": radius},
        "views": views,
    }
    return written, metadata


def choose_source_frames(images: list[Path]) -> dict[str, Path]:
    if not images:
        raise SystemExit("No source frames available for validation")
    n = len(images)
    picks = {
        "hero": images[n // 2],
        "left": images[max(0, n // 2 - max(1, n // 18))],
        "right": images[min(n - 1, n // 2 + max(1, n // 18))],
        "up": images[max(0, n // 2 - max(1, n // 30))],
        "down": images[min(n - 1, n // 2 + max(1, n // 30))],
        "forward": images[min(n - 1, n // 2 + max(1, n // 12))],
        "back": images[max(0, n // 2 - max(1, n // 12))],
        "source_match": images[n // 2],
    }
    for i, frac in enumerate([0.35, 0.42, 0.50, 0.58, 0.65], start=1):
        picks[f"yaw_{i:02d}"] = images[min(n - 1, max(0, int(n * frac)))]
    return picks


def annotate(src: Path, dst: Path, label: str, Image, ImageDraw) -> None:
    im = Image.open(src).convert("RGB")
    draw = ImageDraw.Draw(im)
    draw.rectangle((0, 0, min(im.width, 760), 48), fill=(0, 0, 0))
    draw.text((14, 14), f"{label} | proxy validation frame: {src.name}", fill=(255, 255, 255))
    dst.parent.mkdir(parents=True, exist_ok=True)
    im.save(dst, quality=92)


def sheet(paths: list[Path], output: Path, Image, ImageDraw) -> None:
    thumbs = []
    for path in paths:
        im = Image.open(path).convert("RGB")
        im.thumbnail((320, 180))
        canvas = Image.new("RGB", (320, 210), "white")
        canvas.paste(im, ((320 - im.width) // 2, 0))
        ImageDraw.Draw(canvas).text((8, 188), path.name, fill=(0, 0, 0))
        thumbs.append(canvas)
    cols = 3
    rows = math.ceil(len(thumbs) / cols)
    out = Image.new("RGB", (cols * 320, rows * 210), "white")
    for i, thumb in enumerate(thumbs):
        out.paste(thumb, ((i % cols) * 320, (i // cols) * 210))
    output.parent.mkdir(parents=True, exist_ok=True)
    out.save(output, quality=92)


def main() -> None:
    Image, ImageDraw = require_pillow()
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, default=Path("data/processed/close/images"))
    parser.add_argument("--splat", type=Path, default=Path("exports/close/close.ply"))
    parser.add_argument("--output-dir", type=Path, default=Path("eval/close"))
    parser.add_argument("--settings", type=Path, default=Path("site/close.json"))
    parser.add_argument("--proxy-only", action="store_true")
    args = parser.parse_args()

    images = sorted(args.images.glob("*.jpg"))
    out_frames = args.output_dir / "headbox_renders"
    if out_frames.exists():
        shutil.rmtree(out_frames)
    out_frames.mkdir(parents=True)

    written = []
    render_metadata = None
    render_error = None
    if not args.proxy_only:
        try:
            written, render_metadata = render_splat_views(args.splat, args.settings, out_frames, Image, ImageDraw)
        except Exception as exc:
            render_error = str(exc)

    if not written:
        picks = choose_source_frames(images)
        for label, src in picks.items():
            dst = out_frames / f"{label}.png"
            annotate(src, dst, label, Image, ImageDraw)
            written.append(dst)
        render_metadata = {
            "method": "source-frame proxy validation for single-view scenic headbox",
            "proxy_source_frames": {label: str(src) for label, src in picks.items()},
            "render_error": render_error,
        }

    contact = args.output_dir / "contact_sheet.png"
    sheet(written, contact, Image, ImageDraw)
    manifest = {
        "method": render_metadata["method"],
        "note": (
            "Preferred output is rendered from the trained PLY with @playcanvas/splat-transform. "
            "If renderer setup fails, this script falls back to annotated source-frame proxy images and records the error."
        ),
        "render_metadata": render_metadata,
        "headbox": {
            "horizontal_m": 0.35,
            "vertical_m": 0.25,
            "forward_back_m": 0.30,
            "metric_scale": "arbitrary_if_metric_scale_unavailable",
        },
        "views": {path.stem: str(path) for path in written},
        "contact_sheet": str(contact),
        "viewer_settings": str(args.settings),
    }
    (args.output_dir / "viewpoint_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
