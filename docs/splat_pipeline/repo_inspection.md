# Repo Inspection: Pexels Single-View Splat

Date: 2026-06-28

## Findings

- Current repo: `/Users/peterhowell/splat-tests`, remote `https://github.com/phdev/splat-tests.git`.
- Deploy repo: `/Users/peterhowell/mp-deploy`, remote `https://github.com/phdev/machu-picchu-splat`.
- Viewer entrypoint: `site/index.html`.
- Scene manifest: inline `SCENES` array in `site/index.html`.
- Splat assets: `site/*.sog`.
- Scene settings: `site/*.json`.
- `?scene=close` maps to:
  - `site/close.sog`
  - `site/close.json`
  - label `Close-up`
- The deploy repo mirrors those files at repo root:
  - `/Users/peterhowell/mp-deploy/close.sog`
  - `/Users/peterhowell/mp-deploy/close.json`
  - `/Users/peterhowell/mp-deploy/index.html`
- The viewer expects PlayCanvas SuperSplat `.sog` assets. Source/training exports can be `.ply`, but publish requires conversion to `.sog` with `npx -y @playcanvas/splat-transform`.
- Local static serving works from `site/`, for example:
  - `python3 -m http.server 8000 --directory site`
  - Open `http://127.0.0.1:8000/?scene=close`
- WebGPU rendering needs a real headed browser/GPU. Headless Chromium can load files and HTTP routes, but has historically rendered blank for this viewer.

## Existing Assets

- Existing `site/close.sog` and `data/close/close_30000.ply` are older non-Pexels assets.
- The Pexels prototype must replace the `close` scene assets only after a Pexels-sourced training run succeeds.

## Local Tooling

- `ffmpeg` and `ffprobe` are available under `/opt/homebrew/bin`.
- `yt-dlp` is installed but Pexels page extraction is blocked by Cloudflare in this environment.
- Direct Pexels download redirects at `https://www.pexels.com/download/video/<id>/` are usable and resolve to `videos.pexels.com` MP4 files.
- Local Nerfstudio CLIs (`ns-process-data`, `ns-train`, `ns-export`) are not installed.
- Local COLMAP is installed, but repo notes say matching crashes on this Mac. The reliable training path is Runpod plus Inria 3DGS via the existing `scripts/runpod_pod.py` and `scripts/pod_full.sh`.

## Validation Approach

- `scripts/validate_close_splat.sh` should verify provenance, frame extraction, pose metrics, export existence, viewer mapping, local static serving, and final report.
- Browser visual QA should be done with a headed browser after SOG conversion because the viewer relies on WebGPU.
