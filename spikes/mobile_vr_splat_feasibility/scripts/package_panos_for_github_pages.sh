#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

cd "$ROOT"

python3 - "$ROOT" <<'PY'
from __future__ import annotations

import datetime as dt
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from PIL import Image


root = Path(sys.argv[1]).resolve()
pano_root = root / "assets/machu_picchu_panoramas/360cities_machu_picchu"
original_dir = pano_root / "original"
cleaned_source = pano_root / "cleaned/360cities_machu_picchu_people_removed_equirect.jpg"
provenance_md = pano_root / "PROVENANCE.md"
source_metadata_json = pano_root / "provenance/source_metadata.json"
cleaned_provenance_json = pano_root / "cleaned/360cities_machu_picchu_people_removed_equirect_provenance.json"
spike_dir = root / "spikes/mobile_vr_splat_feasibility"
license_label = "licensed research asset; production usage depends on 360Cities license terms."
image_exts = {".jpg", ".jpeg", ".png", ".webp", ".tif", ".tiff"}


def rel(path: Path, base: Path = root) -> str:
    try:
        return str(path.resolve().relative_to(base.resolve()))
    except Exception:
        return str(path)


def rel_from(path: Path, base: Path) -> str:
    try:
        return str(path.resolve().relative_to(base.resolve()))
    except Exception:
        return str(path)


def load_json(path: Path) -> dict:
    if not path.is_file():
        return {}
    try:
        return json.loads(path.read_text())
    except Exception:
        return {}


def image_dimensions(path: Path) -> tuple[int, int]:
    with Image.open(path) as img:
        return img.size


def is_valid_equirect(path: Path) -> tuple[bool, int, int]:
    try:
        width, height = image_dimensions(path)
    except Exception:
        return False, 0, 0
    if height <= 0:
        return False, width, height
    ratio = width / height
    return abs(ratio - 2.0) < 0.01, width, height


def detect_site_dir() -> tuple[Path, str]:
    env = os.environ.get("GHP_VIEWER_DIR")
    if env:
        path = Path(env).expanduser()
        if not path.is_absolute():
            path = root / path
        path.mkdir(parents=True, exist_ok=True)
        return path.resolve(), "GHP_VIEWER_DIR"
    for name in ("docs", "public", "site", "gh-pages"):
        candidate = root / name
        if candidate.is_dir():
            return candidate.resolve(), f"existing ./{name}"
    fallback = root / "docs"
    fallback.mkdir(parents=True, exist_ok=True)
    return fallback.resolve(), "created ./docs"


def find_original_source() -> Path:
    candidates: list[tuple[int, int, Path]] = []
    if not original_dir.is_dir():
        raise SystemExit(f"[panos] missing original pano directory: {rel(original_dir)}")
    for path in original_dir.rglob("*"):
        if not path.is_file() or path.suffix.lower() not in image_exts:
            continue
        ok, width, height = is_valid_equirect(path)
        if ok:
            candidates.append((width * height, width, path))
    if not candidates:
        raise SystemExit(f"[panos] no valid 2:1 image found under {rel(original_dir)}")
    return sorted(candidates, reverse=True)[0][2]


def save_jpg(src: Path, dest: Path, width: int, height: int, quality: int = 88) -> tuple[int, int, int]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    with Image.open(src) as img:
        img = img.convert("RGB")
        if img.size != (width, height):
            img = img.resize((width, height), Image.Resampling.LANCZOS)
        img.save(dest, "JPEG", quality=quality, optimize=True, progressive=True)
    return width, height, dest.stat().st_size


def copy_fullres(src: Path, dest: Path) -> tuple[int, int, int]:
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dest)
    width, height = image_dimensions(dest)
    return width, height, dest.stat().st_size


def git_text(*args: str) -> str:
    try:
        return subprocess.check_output(["git", "-C", str(root), *args], text=True, stderr=subprocess.DEVNULL).strip()
    except Exception:
        return ""


def github_blob_url(repo_rel_path: str) -> str:
    remote = git_text("config", "--get", "remote.origin.url")
    branch = git_text("branch", "--show-current") or "main"
    repo_url = ""
    if remote.startswith("git@github.com:"):
        repo_url = "https://github.com/" + remote.split(":", 1)[1]
    elif remote.startswith("https://github.com/"):
        repo_url = remote
    if repo_url.endswith(".git"):
        repo_url = repo_url[:-4]
    if not repo_url:
        return repo_rel_path
    return f"{repo_url}/blob/{branch}/{repo_rel_path}"


def report_links() -> list[dict]:
    reports = [
        "spikes/mobile_vr_splat_feasibility/PANO_PEOPLE_CLEANUP_TEST.md",
        "spikes/mobile_vr_splat_feasibility/SPAG4D_FULLRES_SHARP360_TEST.md",
        "spikes/mobile_vr_splat_feasibility/SPAG4D_CLEANED_FULLRES_SHARP360_TEST.md",
    ]
    links = []
    for item in reports:
        if (root / item).is_file():
            links.append({"label": Path(item).name, "path": item, "url": github_blob_url(item)})
    return links


def path_info(path: Path, panos_dir: Path, width: int, height: int, size: int) -> dict:
    return {
        "path": rel_from(path, panos_dir),
        "repo_path": rel(path),
        "width": width,
        "height": height,
        "size_bytes": size,
    }


def add_variant(
    variants: list[dict],
    *,
    variant_id: str,
    label: str,
    source_type: str,
    source_path: Path,
    panos_dir: Path,
    assets_dir: Path,
    basename: str,
    include_fullres: bool,
    fullres_dest: str,
) -> dict:
    source_width, source_height = image_dimensions(source_path)
    preview_4096 = assets_dir / f"{basename}_4096x2048.jpg"
    preview_2048 = assets_dir / f"{basename}_2048x1024.jpg"
    thumb = assets_dir / f"{basename}_thumbnail.jpg"
    p4096 = path_info(preview_4096, panos_dir, *save_jpg(source_path, preview_4096, 4096, 2048, 88))
    p2048 = path_info(preview_2048, panos_dir, *save_jpg(source_path, preview_2048, 2048, 1024, 86))
    pthumb = path_info(thumb, panos_dir, *save_jpg(source_path, thumb, 512, 256, 82))
    fullres = None
    if include_fullres:
        fullres_path = assets_dir / fullres_dest
        fullres = path_info(fullres_path, panos_dir, *copy_fullres(source_path, fullres_path))
    variant = {
        "id": variant_id,
        "label": label,
        "source_type": source_type,
        "source_path": rel(source_path),
        "source_dimensions": {"width": source_width, "height": source_height},
        "preview_4096": p4096,
        "preview_2048": p2048,
        "thumbnail": pthumb,
        "fullres": fullres,
    }
    variants.append(variant)
    return variant


def copy_primary_aliases(primary_variant: dict, panos_dir: Path, assets_dir: Path) -> dict:
    aliases = {
        "preview_4096": assets_dir / "machu_picchu_pano_4096x2048.jpg",
        "preview_2048": assets_dir / "machu_picchu_pano_2048x1024.jpg",
        "thumbnail": assets_dir / "thumbnail.jpg",
    }
    out = {}
    for key, dest in aliases.items():
        src = panos_dir / primary_variant[key]["path"]
        shutil.copy2(src, dest)
        out[key] = path_info(dest, panos_dir, primary_variant[key]["width"], primary_variant[key]["height"], dest.stat().st_size)
    return out


def cleanup_stale_fullres(assets_dir: Path) -> None:
    for path in assets_dir.glob("*fullres*.jpg"):
        path.unlink()
    for path in assets_dir.glob("*fullres*.jpeg"):
        path.unlink()


def provenance_notes() -> dict:
    metadata = load_json(source_metadata_json)
    cleaned_metadata = load_json(cleaned_provenance_json)
    note_lines = []
    if provenance_md.is_file():
        for line in provenance_md.read_text().splitlines():
            if line.startswith("**Asset label:**") or line.startswith("**Research label:**"):
                note_lines.append(line.replace("**", ""))
            elif line.startswith("- Source URL:") or line.startswith("- Photographer:") or line.startswith("- Detected copyright/license text:") or line.startswith("- User-provided license note:"):
                note_lines.append(line[2:])
    return {
        "source_url": metadata.get("krpano_metadata", {}).get("preview") and "https://www.360cities.net/image/machu-picchu" or "https://www.360cities.net/image/machu-picchu",
        "scrape_date_utc": metadata.get("scrape_date_utc"),
        "page_title": metadata.get("page_title"),
        "photographer": metadata.get("photographer") or metadata.get("krpano_metadata", {}).get("author_name"),
        "listed_resolution_or_type": metadata.get("listed_resolution_or_type"),
        "copyright_or_license_text": metadata.get("copyright_or_license_text"),
        "user_license_note": metadata.get("user_license_note"),
        "cleaned_note": cleaned_metadata.get("note"),
        "provenance_docs": [
            rel(path)
            for path in [provenance_md, pano_root / "SCRAPE_REPORT.md", pano_root / "RECONSTRUCTION_VALIDATION.md", cleaned_provenance_json]
            if path.is_file()
        ],
        "notes": [line for line in note_lines if line],
    }


def write_panos_page(path: Path) -> None:
    path.write_text(
        """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" href="data:,">
  <title>Panos</title>
  <style>
    :root {
      color-scheme: light;
      --ink: #171717;
      --muted: #5f6368;
      --line: #d8d7cf;
      --panel: #ffffff;
      --paper: #f5f2ea;
      --accent: #245a67;
      --accent-strong: #123d47;
      --warn-bg: #fff7d6;
      --warn-line: #dac46f;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      background: var(--paper);
      color: var(--ink);
      font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
      line-height: 1.45;
    }
    a { color: var(--accent-strong); }
    .topbar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      gap: 16px;
      padding: 12px clamp(16px, 4vw, 42px);
      border-bottom: 1px solid var(--line);
      background: rgba(255, 255, 255, 0.92);
      position: sticky;
      top: 0;
      z-index: 20;
      backdrop-filter: blur(8px);
    }
    .brand { font-weight: 800; letter-spacing: 0; }
    .topnav { display: flex; flex-wrap: wrap; gap: 10px; align-items: center; }
    .topnav a {
      text-decoration: none;
      font-weight: 700;
      color: var(--ink);
      padding: 6px 8px;
      border-radius: 6px;
    }
    .topnav a[aria-current="page"] { background: var(--accent); color: #fff; }
    main { width: min(1240px, calc(100% - 32px)); margin: 24px auto 42px; }
    h1 { font-size: clamp(30px, 5vw, 48px); line-height: 1.05; margin: 0 0 8px; letter-spacing: 0; }
    h2 { font-size: 18px; margin: 0 0 10px; letter-spacing: 0; }
    p { margin: 0 0 10px; }
    .lede { color: var(--muted); max-width: 860px; }
    .toolbar {
      margin: 20px 0 12px;
      display: flex;
      flex-wrap: wrap;
      gap: 10px;
      align-items: center;
    }
    .group { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; }
    button {
      min-height: 36px;
      border: 1px solid #b9c7ca;
      background: #fff;
      color: var(--ink);
      border-radius: 6px;
      padding: 7px 10px;
      font: inherit;
      font-weight: 700;
      cursor: pointer;
    }
    button:hover { border-color: var(--accent); }
    button.active, button.primary {
      background: var(--accent);
      border-color: var(--accent);
      color: #fff;
    }
    .meta-line {
      margin-left: auto;
      color: var(--muted);
      font-size: 13px;
      min-width: min(100%, 230px);
      text-align: right;
    }
    .viewer {
      width: 100%;
      height: clamp(360px, 68vh, 760px);
      overflow: hidden;
      position: relative;
      background: #202322;
      border: 1px solid #242827;
      border-radius: 8px;
      touch-action: none;
      user-select: none;
    }
    .viewer img {
      display: block;
      position: absolute;
      top: 0;
      left: 0;
      max-width: none;
      transform-origin: 0 0;
      will-change: transform;
      -webkit-user-drag: none;
      user-select: none;
    }
    .status {
      position: absolute;
      left: 12px;
      bottom: 12px;
      padding: 6px 8px;
      border-radius: 6px;
      background: rgba(0, 0, 0, 0.68);
      color: #fff;
      font-size: 12px;
    }
    .content-grid {
      display: grid;
      grid-template-columns: minmax(0, 1.1fr) minmax(280px, 0.9fr);
      gap: 18px;
      margin-top: 18px;
      align-items: start;
    }
    section {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 8px;
      padding: 16px;
    }
    .license {
      background: var(--warn-bg);
      border-color: var(--warn-line);
    }
    dl {
      display: grid;
      grid-template-columns: 150px minmax(0, 1fr);
      gap: 6px 12px;
      margin: 0;
      font-size: 13px;
    }
    dt { color: var(--muted); }
    dd { margin: 0; overflow-wrap: anywhere; }
    ul { margin: 0; padding-left: 18px; }
    li { margin: 4px 0; }
    .links {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(210px, 1fr));
      gap: 8px;
    }
    .links a {
      display: block;
      border: 1px solid var(--line);
      border-radius: 6px;
      padding: 8px;
      text-decoration: none;
      background: #fbfbf8;
      overflow-wrap: anywhere;
    }
    .error {
      padding: 16px;
      border: 1px solid #b44;
      background: #fff1f1;
      border-radius: 8px;
      margin-top: 18px;
    }
    @media (max-width: 760px) {
      .topbar { align-items: flex-start; flex-direction: column; }
      .meta-line { margin-left: 0; text-align: left; }
      .content-grid { grid-template-columns: 1fr; }
      dl { grid-template-columns: 1fr; }
      .viewer { height: 54vh; min-height: 320px; }
    }
  </style>
</head>
<body>
  <header class="topbar">
    <div class="brand">Machu Picchu Review</div>
    <nav class="topnav" aria-label="Site navigation">
      <a href="../">Home</a>
      <a href="./" aria-current="page">Panos</a>
    </nav>
  </header>
  <main>
    <h1>Panos</h1>
    <p class="lede">Machu Picchu 360Cities equirectangular panorama review assets for 2D inspection and manual masking.</p>

    <div class="toolbar" aria-label="Pano controls">
      <div id="variant-buttons" class="group"></div>
      <div class="group">
        <button id="zoom-out" type="button">Zoom out</button>
        <button id="zoom-in" class="primary" type="button">Zoom in</button>
        <button id="fit-width" type="button">Fit to width</button>
        <button id="reset-view" type="button">Reset</button>
      </div>
      <div id="dimensions" class="meta-line"></div>
    </div>

    <div id="viewer" class="viewer" aria-label="2D panorama pan and zoom viewer">
      <img id="pano" alt="Selected Machu Picchu equirectangular panorama">
      <div id="view-status" class="status"></div>
    </div>

    <div id="load-error" class="error" hidden></div>

    <div class="content-grid">
      <section class="license">
        <h2>License And Provenance</h2>
        <p><strong id="license-label">licensed research asset; production usage depends on 360Cities license terms.</strong></p>
        <dl id="provenance"></dl>
      </section>

      <section>
        <h2>Packaged Pano Links</h2>
        <div id="asset-links" class="links"></div>
      </section>

      <section>
        <h2>Related Reports</h2>
        <ul id="report-links"></ul>
      </section>

      <section>
        <h2>Package Details</h2>
        <dl id="package-details"></dl>
      </section>
    </div>
  </main>

  <script>
    const viewer = document.getElementById('viewer');
    const img = document.getElementById('pano');
    const statusEl = document.getElementById('view-status');
    const dimensionsEl = document.getElementById('dimensions');
    const buttonsEl = document.getElementById('variant-buttons');
    const assetLinksEl = document.getElementById('asset-links');
    const reportLinksEl = document.getElementById('report-links');
    const provenanceEl = document.getElementById('provenance');
    const packageDetailsEl = document.getElementById('package-details');
    const errorEl = document.getElementById('load-error');

    let manifest = null;
    let options = [];
    let selected = null;
    let state = { scale: 1, x: 0, y: 0, minScale: 0.05 };
    let dragging = null;

    const fmtBytes = (value) => {
      if (!Number.isFinite(value)) return '';
      if (value > 1024 * 1024) return `${(value / 1024 / 1024).toFixed(1)} MB`;
      if (value > 1024) return `${(value / 1024).toFixed(1)} KB`;
      return `${value} bytes`;
    };

    const addPair = (parent, key, value) => {
      if (value === undefined || value === null || value === '') return;
      const dt = document.createElement('dt');
      dt.textContent = key;
      const dd = document.createElement('dd');
      if (typeof value === 'object' && value.href) {
        const a = document.createElement('a');
        a.href = value.href;
        a.textContent = value.text || value.href;
        dd.appendChild(a);
      } else {
        dd.textContent = String(value);
      }
      parent.append(dt, dd);
    };

    const applyTransform = () => {
      img.style.transform = `translate(${state.x}px, ${state.y}px) scale(${state.scale})`;
      if (selected) {
        statusEl.textContent = `${selected.label} | ${(state.scale * 100).toFixed(1)}%`;
      }
    };

    const fitToWidth = () => {
      if (!img.naturalWidth) return;
      const rect = viewer.getBoundingClientRect();
      state.scale = rect.width / img.naturalWidth;
      state.minScale = Math.max(state.scale * 0.25, 0.01);
      state.x = 0;
      state.y = Math.min(0, (rect.height - img.naturalHeight * state.scale) / 2);
      applyTransform();
    };

    const resetView = () => fitToWidth();

    const zoomAt = (factor, cx, cy) => {
      if (!img.naturalWidth) return;
      const oldScale = state.scale;
      const nextScale = Math.min(Math.max(oldScale * factor, state.minScale), 12);
      const ix = (cx - state.x) / oldScale;
      const iy = (cy - state.y) / oldScale;
      state.scale = nextScale;
      state.x = cx - ix * nextScale;
      state.y = cy - iy * nextScale;
      applyTransform();
    };

    const setSelected = (option) => {
      selected = option;
      for (const button of buttonsEl.querySelectorAll('button')) {
        button.classList.toggle('active', button.dataset.optionId === option.id);
      }
      dimensionsEl.textContent = `${option.width} x ${option.height}px`;
      img.onload = () => {
        dimensionsEl.textContent = `${img.naturalWidth} x ${img.naturalHeight}px`;
        fitToWidth();
      };
      img.src = option.src;
    };

    const buildOptions = () => {
      options = [];
      for (const variant of manifest.variants || []) {
        options.push({
          id: variant.id,
          label: variant.label,
          src: variant.preview_4096.path,
          width: variant.preview_4096.width,
          height: variant.preview_4096.height,
          size: variant.preview_4096.size_bytes,
        });
        if (variant.fullres) {
          options.push({
            id: `${variant.id}-fullres`,
            label: `${variant.label} Full-res`,
            src: variant.fullres.path,
            width: variant.fullres.width,
            height: variant.fullres.height,
            size: variant.fullres.size_bytes,
          });
        }
      }
      buttonsEl.replaceChildren();
      for (const option of options) {
        const button = document.createElement('button');
        button.type = 'button';
        button.dataset.optionId = option.id;
        button.textContent = option.label;
        button.addEventListener('click', () => setSelected(option));
        buttonsEl.appendChild(button);
      }
    };

    const renderLinks = () => {
      assetLinksEl.replaceChildren();
      for (const variant of manifest.variants || []) {
        const links = [
          ['4096 preview', variant.preview_4096],
          ['2048 preview', variant.preview_2048],
          ['Thumbnail', variant.thumbnail],
        ];
        if (variant.fullres) links.push(['Full-res', variant.fullres]);
        for (const [label, item] of links) {
          const a = document.createElement('a');
          a.href = item.path;
          a.textContent = `${variant.label}: ${label} (${item.width} x ${item.height}, ${fmtBytes(item.size_bytes)})`;
          assetLinksEl.appendChild(a);
        }
      }
    };

    const renderReports = () => {
      reportLinksEl.replaceChildren();
      for (const report of manifest.related_reports || []) {
        const li = document.createElement('li');
        const a = document.createElement('a');
        a.href = report.url || report.path;
        a.textContent = report.label;
        li.appendChild(a);
        reportLinksEl.appendChild(li);
      }
      if (!reportLinksEl.childElementCount) {
        const li = document.createElement('li');
        li.textContent = 'No related reports were present when packaged.';
        reportLinksEl.appendChild(li);
      }
    };

    const renderProvenance = () => {
      document.getElementById('license-label').textContent = manifest.license_label || '';
      provenanceEl.replaceChildren();
      const p = manifest.provenance || {};
      addPair(provenanceEl, 'Source', { href: p.source_url, text: p.source_url });
      addPair(provenanceEl, 'Photographer', p.photographer);
      addPair(provenanceEl, 'Page title', p.page_title);
      addPair(provenanceEl, 'Scrape date UTC', p.scrape_date_utc);
      addPair(provenanceEl, 'Listed resolution', p.listed_resolution_or_type);
      addPair(provenanceEl, 'License text', p.copyright_or_license_text);
      addPair(provenanceEl, 'License note', p.user_license_note);
      addPair(provenanceEl, 'Cleanup note', p.cleaned_note);
    };

    const renderPackageDetails = () => {
      packageDetailsEl.replaceChildren();
      addPair(packageDetailsEl, 'Generated', manifest.generated_at_utc);
      addPair(packageDetailsEl, 'Site dir', manifest.site_dir);
      addPair(packageDetailsEl, 'Detected by', manifest.site_dir_detection);
      addPair(packageDetailsEl, 'Primary source', manifest.primary_source_type);
      addPair(packageDetailsEl, 'Full-res included', manifest.fullres_included ? 'yes' : 'no');
      for (const variant of manifest.variants || []) {
        addPair(packageDetailsEl, `${variant.label} source`, variant.source_path);
      }
    };

    viewer.addEventListener('wheel', (event) => {
      event.preventDefault();
      const rect = viewer.getBoundingClientRect();
      const factor = event.deltaY < 0 ? 1.16 : 1 / 1.16;
      zoomAt(factor, event.clientX - rect.left, event.clientY - rect.top);
    }, { passive: false });

    viewer.addEventListener('pointerdown', (event) => {
      viewer.setPointerCapture(event.pointerId);
      dragging = { id: event.pointerId, x: event.clientX, y: event.clientY, startX: state.x, startY: state.y };
    });

    viewer.addEventListener('pointermove', (event) => {
      if (!dragging || dragging.id !== event.pointerId) return;
      state.x = dragging.startX + event.clientX - dragging.x;
      state.y = dragging.startY + event.clientY - dragging.y;
      applyTransform();
    });

    viewer.addEventListener('pointerup', () => { dragging = null; });
    viewer.addEventListener('pointercancel', () => { dragging = null; });
    window.addEventListener('resize', () => fitToWidth());
    document.getElementById('zoom-in').addEventListener('click', () => zoomAt(1.2, viewer.clientWidth / 2, viewer.clientHeight / 2));
    document.getElementById('zoom-out').addEventListener('click', () => zoomAt(1 / 1.2, viewer.clientWidth / 2, viewer.clientHeight / 2));
    document.getElementById('fit-width').addEventListener('click', fitToWidth);
    document.getElementById('reset-view').addEventListener('click', resetView);

    fetch('panos.json')
      .then((response) => {
        if (!response.ok) throw new Error(`panos.json ${response.status}`);
        return response.json();
      })
      .then((data) => {
        manifest = data;
        buildOptions();
        renderLinks();
        renderReports();
        renderProvenance();
        renderPackageDetails();
        if (options.length) setSelected(options[0]);
      })
      .catch((error) => {
        errorEl.hidden = false;
        errorEl.textContent = `Unable to load pano manifest: ${error.message}`;
      });
  </script>
</body>
</html>
""",
        encoding="utf-8",
    )


def ensure_main_index(site_dir: Path) -> dict:
    index = site_dir / "index.html"
    if not index.is_file():
        index.write_text(
            """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" href="data:,">
  <title>Machu Picchu Review</title>
  <style>
    body { margin: 0; background: #f5f2ea; color: #171717; font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; line-height: 1.45; }
    header { border-bottom: 1px solid #d8d7cf; background: #fff; padding: 14px clamp(16px, 4vw, 42px); display: flex; justify-content: space-between; gap: 16px; flex-wrap: wrap; align-items: center; }
    .brand { font-weight: 800; }
    nav { display: flex; flex-wrap: wrap; gap: 10px; }
    nav a { color: #171717; text-decoration: none; font-weight: 700; padding: 6px 8px; border-radius: 6px; }
    nav a[aria-current="page"] { background: #245a67; color: #fff; }
    main { width: min(920px, calc(100% - 32px)); margin: 34px auto; }
    h1 { font-size: clamp(30px, 5vw, 48px); line-height: 1.05; margin: 0 0 10px; letter-spacing: 0; }
    .links { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 12px; margin-top: 22px; }
    .links a { background: #fff; border: 1px solid #d8d7cf; border-radius: 8px; padding: 14px; color: #123d47; font-weight: 800; text-decoration: none; }
  </style>
</head>
<body>
  <header>
    <div class="brand">Machu Picchu Review</div>
    <nav aria-label="Site navigation">
      <a href="./" aria-current="page">Home</a>
      <a href="./panos/">Panos</a>
    </nav>
  </header>
  <main>
    <h1>Machu Picchu Review</h1>
    <p>Static review pages for Machu Picchu splat and panorama research assets.</p>
    <div class="links">
      <a href="./panos/">Panos</a>
    </div>
  </main>
</body>
</html>
""",
            encoding="utf-8",
        )
        return {"status": "created_main_index", "path": rel(index)}

    text = index.read_text(encoding="utf-8", errors="replace")
    if re.search(r">\s*Panos\s*<", text, flags=re.I) or "href=\"./panos/\"" in text or "href=\"panos/\"" in text:
        return {"status": "panos_link_already_present", "path": rel(index)}

    link = '      <a href="./panos/">Panos</a>\n'
    if re.search(r"</nav>", text, flags=re.I):
        text = re.sub(r"</nav>", link + "    </nav>", text, count=1, flags=re.I)
        index.write_text(text, encoding="utf-8")
        return {"status": "added_to_existing_nav", "path": rel(index)}
    if re.search(r"<body[^>]*>", text, flags=re.I):
        nav = '\n    <nav aria-label="Site navigation"><a href="./panos/">Panos</a></nav>\n'
        text = re.sub(r"(<body[^>]*>)", r"\1" + nav, text, count=1, flags=re.I)
        index.write_text(text, encoding="utf-8")
        return {"status": "added_body_nav", "path": rel(index)}
    text += '\n<nav aria-label="Site navigation"><a href="./panos/">Panos</a></nav>\n'
    index.write_text(text, encoding="utf-8")
    return {"status": "appended_nav", "path": rel(index)}


def write_docs(manifest: dict, nav_note: dict) -> None:
    doc = spike_dir / "GITHUB_PAGES_PANOS.md"
    preview_lines = [
        f"- Primary 4096 preview: `{manifest['site_dir']}/panos/{manifest['primary_aliases']['preview_4096']['path']}`",
        f"- Primary 2048 preview: `{manifest['site_dir']}/panos/{manifest['primary_aliases']['preview_2048']['path']}`",
        f"- Primary thumbnail: `{manifest['site_dir']}/panos/{manifest['primary_aliases']['thumbnail']['path']}`",
    ]
    for variant in manifest["variants"]:
        preview_lines.extend(
            [
                f"- {variant['label']} 4096 preview: `{manifest['site_dir']}/panos/{variant['preview_4096']['path']}`",
                f"- {variant['label']} 2048 preview: `{manifest['site_dir']}/panos/{variant['preview_2048']['path']}`",
                f"- {variant['label']} thumbnail: `{manifest['site_dir']}/panos/{variant['thumbnail']['path']}`",
            ]
        )
        if variant.get("fullres"):
            preview_lines.append(f"- {variant['label']} full-res: `{manifest['site_dir']}/panos/{variant['fullres']['path']}`")
    reports = "\n".join(f"- [{item['label']}]({item['url']})" for item in manifest["related_reports"]) or "- None present when packaged."
    doc.write_text(
        "# GitHub Pages Panos\n\n"
        f"{license_label}\n\n"
        "## Status\n\n"
        "- Status: `packaged`\n"
        f"- Generated: `{manifest['generated_at_utc']}`\n"
        f"- Site dir: `{manifest['site_dir']}` ({manifest['site_dir_detection']})\n"
        f"- Panos page: `{manifest['site_dir']}/panos/index.html`\n"
        f"- Pano manifest: `{manifest['site_dir']}/panos/panos.json`\n"
        f"- Full-res included: `{str(manifest['fullres_included']).lower()}`\n"
        f"- Main-nav handling: `{nav_note['status']}` in `{nav_note['path']}`\n\n"
        "## Source Pano Selected\n\n"
        f"- Primary source type: `{manifest['primary_source_type']}`\n"
        f"- Primary source path: `{manifest['primary_source_path']}`\n"
        f"- Original source path: `{manifest['original_source_path']}`\n"
        f"- Cleaned source path: `{manifest.get('cleaned_source_path') or 'not present'}`\n"
        f"- Source URL: `{manifest['provenance'].get('source_url')}`\n"
        f"- Photographer: `{manifest['provenance'].get('photographer')}`\n"
        f"- License note: `{manifest['provenance'].get('copyright_or_license_text')}`\n\n"
        "## Generated Preview Paths\n\n"
        + "\n".join(preview_lines)
        + "\n\n"
        "The un-gated package uses web-safe derivatives. Full-resolution copies are only written when `GHP_INCLUDE_FULLRES_PANO=1`.\n\n"
        "## Related Reports\n\n"
        f"{reports}\n\n"
        "## Run\n\n"
        "```bash\n"
        "bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh\n"
        "```\n\n"
        "Optional overrides:\n\n"
        "```bash\n"
        "GHP_VIEWER_DIR=docs bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh\n"
        "GHP_INCLUDE_FULLRES_PANO=1 bash spikes/mobile_vr_splat_feasibility/scripts/package_panos_for_github_pages.sh\n"
        "```\n\n"
        "## Deploy\n\n"
        "Deployment is gated. Do not push unless `GH_PAGES_DEPLOY=1` is intentionally set.\n\n"
        "```bash\n"
        "GH_PAGES_DEPLOY=1 GHP_VIEWER_DIR=docs bash spikes/mobile_vr_splat_feasibility/scripts/deploy_viewer_assets.sh\n"
        "```\n\n"
        "If `docs/` is the detected Pages directory in the deployment environment, this equivalent form can be used:\n\n"
        "```bash\n"
        "GH_PAGES_DEPLOY=1 bash spikes/mobile_vr_splat_feasibility/scripts/deploy_viewer_assets.sh\n"
        "```\n",
        encoding="utf-8",
    )


def main() -> int:
    site_dir, detection = detect_site_dir()
    panos_dir = site_dir / "panos"
    assets_dir = panos_dir / "assets"
    panos_dir.mkdir(parents=True, exist_ok=True)
    assets_dir.mkdir(parents=True, exist_ok=True)

    include_fullres = os.environ.get("GHP_INCLUDE_FULLRES_PANO") == "1"
    if not include_fullres:
        cleanup_stale_fullres(assets_dir)

    original_source = find_original_source()
    has_cleaned = cleaned_source.is_file() and is_valid_equirect(cleaned_source)[0]
    primary_source = cleaned_source if has_cleaned else original_source
    primary_source_type = "people_removed" if has_cleaned else "original"

    variants: list[dict] = []
    original_variant = add_variant(
        variants,
        variant_id="original",
        label="Original",
        source_type="original",
        source_path=original_source,
        panos_dir=panos_dir,
        assets_dir=assets_dir,
        basename="machu_picchu_pano_original",
        include_fullres=include_fullres,
        fullres_dest="machu_picchu_pano_original_fullres.jpg",
    )
    cleaned_variant = None
    if has_cleaned:
        cleaned_variant = add_variant(
            variants,
            variant_id="people_removed",
            label="People-removed",
            source_type="people_removed",
            source_path=cleaned_source,
            panos_dir=panos_dir,
            assets_dir=assets_dir,
            basename="machu_picchu_pano_people_removed",
            include_fullres=include_fullres,
            fullres_dest="machu_picchu_pano_people_removed_fullres.jpg",
        )
    primary_variant = cleaned_variant if cleaned_variant is not None else original_variant
    primary_aliases = copy_primary_aliases(primary_variant, panos_dir, assets_dir)

    generated_at = dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")
    manifest = {
        "schema": "github_pages_panos_v1",
        "generated_at_utc": generated_at,
        "site_dir": rel(site_dir),
        "site_dir_detection": detection,
        "panos_dir": rel(panos_dir),
        "fullres_included": include_fullres,
        "license_label": license_label,
        "primary_source_type": primary_source_type,
        "primary_source_path": rel(primary_source),
        "original_source_path": rel(original_source),
        "cleaned_source_path": rel(cleaned_source) if has_cleaned else None,
        "primary_aliases": primary_aliases,
        "provenance": provenance_notes(),
        "variants": variants,
        "related_reports": report_links(),
    }

    (panos_dir / "panos.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    write_panos_page(panos_dir / "index.html")
    nav_note = ensure_main_index(site_dir)
    write_docs(manifest, nav_note)

    print(f"[panos] site_dir={rel(site_dir)} ({detection})")
    print(f"[panos] primary={primary_source_type} source={rel(primary_source)}")
    print(f"[panos] wrote {rel(panos_dir / 'index.html')}")
    print(f"[panos] wrote {rel(panos_dir / 'panos.json')}")
    print(f"[panos] fullres_included={include_fullres}")
    return 0


raise SystemExit(main())
PY
