# Machu Picchu splat — build log

## Source
- YouTube `_hbRXmSzK38` — "Machu Picchu Drone (Without Tourists)" (filmed during the
  2020 closure → empty citadel, no moving people = ideal SfM). 1080p max.
- License posture: **private/research use only** (YouTube footage), not redistributable.
- Frames: `ffmpeg -ss 14 -vf fps=1.2` → **169 frames @ 1920×1080**, `data/machu/input/`.
- Why this clip: candidates were screened with ffmpeg cut-detection + contact sheets.
  The 4K "by drone" montage (`oZ90M55mDac`) had soft cuts mid-"continuous" segments;
  "Without Tourists" has a coherent empty-citadel tour and no people.

## Reconstruction (Runpod, RTX 4090, 62GB container)
Local COLMAP matcher SIGTRAPs on this Mac, so SfM+train run on a pod.

**Gotchas hit (folded into `scripts/pod_machu.sh`):**
1. Default COLMAP CPU SIFT uses all 128 threads → **OOM-killed (137)** past the 62GB
   container limit after 2 images. Inria `convert.py` then masked it (exit 35072 mod
   256 = 0) and train.py died "Could not recognize scene type". Fix: **cap threads**
   (`--SiftExtraction.num_threads 16`), which works (feature extraction of all 169
   completed, ~1 min).
2. Pod COLMAP is **3.7, CUDA-less** → GPU SIFT core-dumps; CPU only.
3. Must `pip install "numpy<2"` (torch 2.1 ABI) — stock `pod_run_3dgs.sh` omits it.
4. macOS tar `._*` AppleDouble files → cleaned before COLMAP.

Pipeline: feature_extractor (OPENCV, single camera, nt=16) → exhaustive_matcher (nt=16,
needed because the clip is edited) → mapper (largest sub-model) → image_undistorter →
Inria `train.py` 30k iters → `point_cloud.ply`.

## Status
- IN PROGRESS — COLMAP matching/mapping → 30k train on pod `ap9rv0vvv2u0sd`.
- TODO: pull PLY → inspect bounds → (gentle despike if needed) → SOG → PlayCanvas
  viewer → GitHub Pages → delete pod.
