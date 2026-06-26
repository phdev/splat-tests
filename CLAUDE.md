# CLAUDE.md — splat-tests

Guide for AI agents working in this repo. Keep it updated when behavior changes
(the user's standing instruction).

## What this is
Turn real-world locations into 3D Gaussian splats viewable in a **PlayCanvas SOG**
viewer in the browser. The pipeline is borrowed wholesale from `~/ue-splat-capture`
(the Electric Dreams splat work) but fed by **real-world drone video** instead of a
synthetic Unreal capture.

**First/active target: Machu Picchu** — a clean-room recreation of the real place
(the user's prompt referenced the Supernatural VR levels; Supernatural's assets are
proprietary and are NOT used or extracted — we independently reconstruct the same
real LOCATION from public footage). Salar de Uyuni was de-scoped (the open mirror
salt flat is the single worst 3DGS subject: featureless + mirror reflections +
near-zero parallax → COLMAP can't register it).

## The pipeline
```
yt-dlp <youtube>            # source video  -> data/<name>.mp4
ffmpeg fps=N                # frames         -> data/<scene>/input/*.jpg
pod_run_3dgs.sh  (Runpod)   # COLMAP SfM + Inria 3DGS -> point_cloud.ply
despike_ply.py              # clean floaters (gentle; over-clean strips geometry)
splat-transform .ply .sog   # SOG compression (~15-20x smaller than PLY)
make_sog_viewer.sh          # SOG -> self-contained PlayCanvas viewer site
GitHub Pages                # deploy site/
```

## Key facts / gotchas
- **Local COLMAP is broken here.** `colmap feature_extractor` works, but
  `colmap exhaustive_matcher` SIGTRAPs (exit 133) instantly on this M1 Max (brew
  COLMAP 4.0.4). So SfM + training run on a **Runpod** pod. COLMAP 4.0.4 flags are
  `--FeatureExtraction.use_gpu` / `--FeatureMatching.use_gpu` (NOT the old
  `--SiftExtraction`/`--SiftMatching`).
- **Runpod path = `scripts/pod_run_3dgs.sh`** (the proven ~$0.20–1, ~15–40 min
  recipe): apt colmap (CPU-only build → `convert.py --no_gpu`), clone Inria
  gaussian-splatting, `convert.py` (COLMAP) → `train.py` → `render.py`. Launch:
  `ITERS=30000 nohup/setsid bash pod_run_3dgs.sh > run.log 2>&1`. Dataset layout the
  pod expects: `/workspace/ed/input/*.jpg`. **ALWAYS `runpod_pod.py delete <id>`
  when done** (paid cloud). Runpod spend is pre-authorized for this repo (run pods
  autonomously, no per-pod confirmation).
- **zsh does NOT word-split a variable holding ssh/scp flags** — inline every flag
  on each `ssh`/`scp` call (a `SSH="ssh -i .. -p .."` var makes ssh ignore `-p` and
  hit port 22 → timeout). Use `-o StrictHostKeyChecking=no -o
  UserKnownHostsFile=/dev/null`.
- **macOS tar adds `._*` AppleDouble + xattr junk** that COLMAP tries to read as
  images → `find . -name '._*' -delete` after extracting on the pod, or pack with
  `COPYFILE_DISABLE=1 tar --no-xattrs`. The "Cannot change ownership" tar warnings
  are harmless (files still extract); ignore them.
- **SOG is local + free** via `npx -y @playcanvas/splat-transform` (v2.7.0): reads
  PLY, writes `.sog`; `-U` emits a self-contained SuperSplat viewer. The SOG viewer
  needs WebGPU + HTTP (not file://) and does NOT render in headless Chromium — QA
  with `/browse --headed` (Metal) or a real device.
- **brush** (`~/brush/target/release/brush`) is the standing LOCAL Metal 3DGS
  trainer, but it needs a COLMAP dataset and local COLMAP is broken — so brush is
  only usable here if poses come from elsewhere. Runpod is the real path for
  real-world video.

## Source footage (provenance matters)
Output redistribution rights are inherited from the inputs. The user chose
**"best quality, private use"** → YouTube drone footage is fair game but the
resulting splat is **personal/research only, not redistributable**. Record the
source URL + license for every scene.

- **Machu Picchu** = YouTube `_hbRXmSzK38` ("Machu Picchu Drone (Without Tourists)",
  filmed during the 2020 closure → an EMPTY citadel, no moving people = ideal SfM).
  1080p max. Frames extracted from 14s onward at 1.2 fps → 169 frames. Because the
  clip is an edited tour (cuts), COLMAP **exhaustive** matching is used (matches all
  pairs regardless of cut order, photo-tourism style) → it keeps the largest
  connected citadel model.

## Per-scene status
- **machu** — IN PROGRESS. 169 frames @1080p on Runpod (RTX 4090); COLMAP +
  Inria 3DGS @ 30k iters. PLY → clean → SOG → deploy pending.

## Floater cleaning + SOG + deploy (from ue-splat-capture)
- `despike_ply.py IN OUT <spike_len> <spike_ratio> <haze_dist> <faint_op>
  <glint_sat> <box x0,y0,z0,x1,y1,z1> <SOR_ratio> <keepCC> <keep_largest> <SOR_k>
  <glint_flag>` — scales are LOG-space, opacity is a LOGIT in the raw ply. Clean
  GENTLY; over-cleaning (aggressive SOR / keep-largest-CC) strips faint real ground.
  For a first pass, SOG the RAW ply, QA, then clean only if floaters are bad.
- `make_sog_viewer.sh <in.ply> <out_site_dir>` → `index.html + index.sog + index.js`
  (PlayCanvas SuperSplat viewer). Serve over HTTP. Bump the SOG filename each deploy
  to bust the Pages/browser cache.
- Deploy `site/` to GitHub Pages; end every deploy message with the live URL.
