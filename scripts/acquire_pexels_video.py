#!/usr/bin/env python3
"""Acquire a Pexels source video and write provenance metadata."""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.parse
import urllib.request
from pathlib import Path


LICENSE_URL = "https://www.pexels.com/license/"
DEFAULT_OUT = Path("data/sources/pexels_machu_picchu")


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def pexels_video_id(url: str) -> str | None:
    match = re.search(r"(?:/video/[^/]*?|\bvideo-files/)(\d+)", url)
    if match:
        return match.group(1)
    match = re.search(r"/download/video/(\d+)/?", url)
    return match.group(1) if match else None


def validate_pexels_url(url: str) -> None:
    host = urllib.parse.urlparse(url).netloc.lower()
    if not (host.endswith("pexels.com") or host.endswith("videos.pexels.com")):
        raise SystemExit(f"Refusing non-Pexels source URL: {url}")


def resolve_download_url(url: str, video_id: str | None) -> str:
    validate_pexels_url(url)
    host = urllib.parse.urlparse(url).netloc.lower()
    if host.endswith("videos.pexels.com"):
        return url
    if video_id is None:
        raise SystemExit(f"Could not infer Pexels video id from URL: {url}")
    return f"https://www.pexels.com/download/video/{video_id}/"


def download(url: str, output: Path) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    output.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(req, timeout=120) as resp:
        resolved = resp.geturl()
        with output.open("wb") as f:
            shutil.copyfileobj(resp, f)
    return resolved


def copy_input_video(path: Path, output: Path) -> None:
    if not path.is_file():
        raise SystemExit(f"Input video does not exist: {path}")
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, output)


def ffprobe(path: Path) -> dict:
    try:
        raw = subprocess.check_output(
            [
                "ffprobe",
                "-v",
                "error",
                "-show_entries",
                "format=duration,size",
                "-show_streams",
                "-of",
                "json",
                str(path),
            ],
            text=True,
        )
        return json.loads(raw)
    except Exception as exc:
        return {"error": str(exc)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--url", default=os.environ.get("PEXELS_VIDEO_URL"))
    parser.add_argument("--input-video", type=Path, default=os.environ.get("INPUT_VIDEO"))
    parser.add_argument("--output-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--title", default="")
    parser.add_argument("--creator", default="")
    parser.add_argument("--notes", default="")
    args = parser.parse_args()

    if args.url and args.input_video:
        raise SystemExit("Set only one of --url/PEXELS_VIDEO_URL or --input-video/INPUT_VIDEO.")
    if not args.url and not args.input_video:
        raise SystemExit(
            "No source video set. Use either:\n"
            "  PEXELS_VIDEO_URL='https://www.pexels.com/video/...-12345/' scripts/acquire_pexels_video.py\n"
            "or:\n"
            "  INPUT_VIDEO='/path/to/local.mp4' scripts/acquire_pexels_video.py"
        )

    out_dir = args.output_dir
    out_video = out_dir / "source.mp4"
    source_url = args.url or ""
    resolved_url = ""
    video_id = pexels_video_id(source_url) if source_url else None

    if args.input_video:
        copy_input_video(Path(args.input_video), out_video)
        source_kind = "local_input_video"
    else:
        source_kind = "pexels_url"
        download_url = resolve_download_url(source_url, video_id)
        resolved_url = download(download_url, out_video)
        video_id = video_id or pexels_video_id(resolved_url)

    manifest = {
        "source_kind": source_kind,
        "source_url": source_url,
        "resolved_download_url": resolved_url,
        "pexels_video_id": video_id,
        "title": args.title,
        "creator": args.creator,
        "license_url": LICENSE_URL,
        "download_timestamp_utc": dt.datetime.now(dt.UTC).isoformat(),
        "local_path": str(out_video),
        "sha256": sha256_file(out_video),
        "ffprobe": ffprobe(out_video),
        "notes": args.notes,
        "legal_review_needed": True,
    }
    (out_dir / "source_manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))


if __name__ == "__main__":
    main()
