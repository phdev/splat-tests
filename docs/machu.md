# Machu Picchu splats — build log

Goal: Gaussian splats of Machu Picchu in a PlayCanvas SOG viewer. Clean-room
recreation from public footage (Supernatural's assets are proprietary, never used).

## What works vs what doesn't (the core lesson)
**Video-orbit drone footage reconstructs; close-range photo sets don't.**
- ✅ Continuous/overlapping aerial drone frames → COLMAP registers a citadel model.
- ❌ CAST/Arkansas Main Temple "metric photos" (154 close-range DSLR, CC-BY-NC):
  COLMAP found ~12k features/image but registered only **35/154** into one model —
  the shots are of disjoint temple faces that don't overlap enough to chain. Not a
  brightness problem (features were plentiful); a coverage/overlap problem. Result
  was an under-constrained floater fragment. Abandoned.
- ❌ Ground-level walking-tour footage: tours dwell in Aguas Calientes town, and the
  citadel itself is always crowded (gimbals banned on-site), so clean POV ruins
  footage is essentially unavailable. A purple-poncho guide / market crowds fill the
  frame → unreconstructable moving objects. Pivoted "ground-level" → low drone pass.

## Scenes (all from public drone footage, private/research use)
| scene | source | frames | notes |
|---|---|---|---|
| **citadel v1** | YT `_hbRXmSzK38` "Without Tourists" (empty 2020 citadel), montage @1.2fps | 169 → 89 reg | LIVE first; floatery (sparse montage) |
| **citadel v2** | same clip, continuous 34–63s orbit @3fps | 87 | denser/cleaner re-train |
| **aerial** | YT `oZ90M55mDac` "by drone" 4K montage @1.3fps | 203 | wider 4K Machu Picchu |
| **close** | `_hbRXmSzK38` low oblique pass 113–138s @3.5fps | 88 | closer view of the ruins |

## Pipeline (per scene)
yt-dlp → ffmpeg frames → **Runpod** COLMAP (capped threads) + Inria 3DGS
(`scripts/pod_full.sh`, fresh pods; `pod_machu.sh` if gs already set up) →
`despike_ply.py` clean → `@playcanvas/splat-transform` SOG → PlayCanvas viewer → Pages.

Three scenes trained in PARALLEL on three pods (Runpod autonomy authorized).

## Gotchas (folded into the scripts)
- Local COLMAP matcher SIGTRAPs (133) on this Mac → all SfM on Runpod.
- 62GB pod container OOM-kills COLMAP's default 128-thread CPU SIFT → cap
  `--SiftExtraction.num_threads 16`. Inria `convert.py` masks COLMAP failure via
  exit-code truncation (35072 mod 256 = 0) → run COLMAP explicitly with checks.
- `pip install "numpy<2"` (torch 2.1 ABI). Pod COLMAP 3.7 is CUDA-less (CPU SIFT only).
- zsh won't word-split an ssh-flags var → inline flags. macOS bash 3.2 has no
  `declare -A`. macOS tar `._*` junk → COPYFILE_DISABLE / find -delete.
- Despike: needles are scale~0.3–1.5, high-aspect → `s_abs 0.35 aspect 3.5` catches
  them; opacity-floor removes milky haze; glint/CC off to spare real terraces.

## Deploy
- Scene 1 v1 LIVE: https://phdev.github.io/machu-picchu-splat/ (repo phdev/machu-picchu-splat).
- Final: one viewer + scene switcher for all good scenes; bump SOG filenames to bust cache.
