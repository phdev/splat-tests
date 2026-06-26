# splat-tests

Turn real-world locations into 3D Gaussian splats viewable in a **PlayCanvas SOG
viewer** in the browser.

First target: **Machu Picchu** (a clean-room recreation of the real place from
public drone footage — *not* any proprietary VR asset).

## Pipeline

```
source video (yt-dlp)
  → frames (ffmpeg)
    → COLMAP SfM + Inria 3D Gaussian Splatting   [Runpod GPU pod]
      → clean floaters (despike_ply.py)
        → SOG (@playcanvas/splat-transform)
          → PlayCanvas SuperSplat viewer → GitHub Pages
```

Local COLMAP can't run here (the brew COLMAP 4.0.4 matcher SIGABRTs on this
M1 Max), so structure-from-motion + training run on a Runpod CUDA pod via
`scripts/pod_run_3dgs.sh`. Everything after the trained `.ply` (clean → SOG →
viewer) is local and free.

## Scripts

| script | what it does |
|---|---|
| `scripts/pod_run_3dgs.sh` | pod-side: COLMAP (`convert.py`) → Inria 3DGS train → render |
| `scripts/runpod_pod.py` | Runpod pod lifecycle (`create`/`wait`/`status`/`delete`) |
| `scripts/run_colmap_local.sh` | local COLMAP driver (kept for reference; matcher crashes here) |
| `scripts/despike_ply.py` | strip floater families from a trained `.ply` |
| `scripts/set_viewer_camera.py` | fit the SuperSplat viewer camera to cleaned content |
| `scripts/make_sog_viewer.sh` | `.ply` → SOG → self-contained PlayCanvas viewer site |
| `scripts/orbit_poses.py` | write orbit pose JSONs for full-orbit QA |

## Layout

- `data/` — source video, frames, COLMAP output, trained `.ply` (gitignored)
- `site/` — the deployable PlayCanvas SOG viewer
- `docs/` — per-scene build notes
- `scripts/` — pipeline tooling

See `CLAUDE.md` for the detailed recipe, gotchas, and per-scene status.
