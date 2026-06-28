#!/usr/bin/env python3
"""Run or analyze SfM for the Pexels close scene."""

from __future__ import annotations

import argparse
import json
import shutil
import struct
import subprocess
from pathlib import Path


def read_next(fid, n: int, fmt: str):
    data = fid.read(n)
    if len(data) != n:
        raise EOFError(f"Expected {n} bytes, got {len(data)}")
    return struct.unpack(fmt, data)


def count_images(images_bin: Path) -> int:
    with images_bin.open("rb") as fid:
        (num_images,) = read_next(fid, 8, "<Q")
    return int(num_images)


def points_stats(points3d_bin: Path) -> tuple[int, float | None, float | None]:
    errors = []
    with points3d_bin.open("rb") as fid:
        (num_points,) = read_next(fid, 8, "<Q")
        for _ in range(num_points):
            values = read_next(fid, 43, "<QdddBBBd")
            errors.append(float(values[-1]))
            (track_len,) = read_next(fid, 8, "<Q")
            fid.seek(track_len * 8, 1)
    if not errors:
        return int(num_points), None, None
    errors_sorted = sorted(errors)
    mid = len(errors_sorted) // 2
    median = errors_sorted[mid] if len(errors_sorted) % 2 else (errors_sorted[mid - 1] + errors_sorted[mid]) / 2
    mean = sum(errors_sorted) / len(errors_sorted)
    return int(num_points), float(median), float(mean)


def analyze(colmap_dir: Path, selected_frames: int, method: str, notes: str) -> dict:
    sparse = colmap_dir / "sparse/0"
    if not (sparse / "images.bin").is_file():
        raise SystemExit(f"Missing COLMAP images.bin under {sparse}")
    registered = count_images(sparse / "images.bin")
    point_count, median_error, mean_error = points_stats(sparse / "points3D.bin")
    ratio = registered / selected_frames if selected_frames else 0.0
    report = {
        "method": method,
        "colmap_dir": str(colmap_dir),
        "total_selected_frames": selected_frames,
        "registered_frames": registered,
        "registration_ratio": ratio,
        "sparse_point_count": point_count,
        "median_reprojection_error_px": median_error,
        "mean_reprojection_error_px": mean_error,
        "hard_stop_passed": registered >= 150 and ratio >= 0.50 and point_count > 0,
        "preferred_target_passed": registered >= 250 and ratio >= 0.70 and (median_error is None or median_error <= 2.0),
        "notes": notes,
    }
    return report


def run(cmd: list[str], log_path: Path) -> None:
    print("+", " ".join(cmd), flush=True)
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("w") as log:
        subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT, check=True)


def run_local_colmap(images: Path, output: Path, threads: int) -> Path:
    distorted = output / "distorted"
    sparse_root = distorted / "sparse"
    if output.exists():
        shutil.rmtree(output)
    sparse_root.mkdir(parents=True)
    run(
        [
            "colmap",
            "feature_extractor",
            "--database_path",
            str(distorted / "database.db"),
            "--image_path",
            str(images),
            "--ImageReader.single_camera",
            "1",
            "--ImageReader.camera_model",
            "OPENCV",
            "--SiftExtraction.use_gpu",
            "0",
            "--SiftExtraction.num_threads",
            str(threads),
            "--SiftExtraction.max_image_size",
            "1920",
        ],
        output / "feature_extractor.log",
    )
    run(
        [
            "colmap",
            "exhaustive_matcher",
            "--database_path",
            str(distorted / "database.db"),
            "--SiftMatching.use_gpu",
            "0",
            "--SiftMatching.num_threads",
            str(threads),
        ],
        output / "exhaustive_matcher.log",
    )
    run(
        [
            "colmap",
            "mapper",
            "--database_path",
            str(distorted / "database.db"),
            "--image_path",
            str(images),
            "--output_path",
            str(sparse_root),
            "--Mapper.num_threads",
            str(threads),
        ],
        output / "mapper.log",
    )
    best = None
    best_n = -1
    for candidate in sparse_root.iterdir():
        if (candidate / "images.bin").is_file():
            n = count_images(candidate / "images.bin")
            if n > best_n:
                best = candidate
                best_n = n
    if best is None:
        raise SystemExit("COLMAP mapper did not produce a sparse model")
    final_sparse = output / "sparse/0"
    final_sparse.parent.mkdir(parents=True)
    shutil.copytree(best, final_sparse, dirs_exist_ok=True)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, default=Path("data/processed/close/images"))
    parser.add_argument("--output-dir", type=Path, default=Path("data/processed/close_colmap"))
    parser.add_argument("--report", type=Path, default=Path("data/processed/close/pose_report.json"))
    parser.add_argument("--analyze-colmap-dir", type=Path)
    parser.add_argument("--threads", type=int, default=8)
    parser.add_argument("--allow-local-colmap", action="store_true")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    selected_frames = len(list(args.images.glob("*.jpg")))
    if selected_frames <= 0:
        raise SystemExit(f"No selected frames found in {args.images}")

    if args.analyze_colmap_dir:
        report = analyze(args.analyze_colmap_dir, selected_frames, "analyze_existing_colmap", args.notes)
    elif shutil.which("ns-process-data"):
        raise SystemExit("Nerfstudio is installed, but this wrapper has not been wired for local ns-process-data execution yet.")
    elif shutil.which("colmap") and args.allow_local_colmap:
        colmap_dir = run_local_colmap(args.images, args.output_dir, args.threads)
        report = analyze(colmap_dir, selected_frames, "local_colmap", args.notes)
    else:
        raise SystemExit(
            "Nerfstudio is not installed and local COLMAP is disabled by default. "
            "Use scripts/train_splat.sh for the Runpod/Inria 3DGS path, or pass --allow-local-colmap."
        )

    args.report.parent.mkdir(parents=True, exist_ok=True)
    args.report.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    if not report["hard_stop_passed"]:
        raise SystemExit("SfM hard-stop thresholds failed; see pose_report.json")


if __name__ == "__main__":
    main()
