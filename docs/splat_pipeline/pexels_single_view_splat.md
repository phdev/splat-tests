# Pexels Single-View Gaussian Splat Prototype

## Goal

Build an end-to-end prototype pipeline that creates a Gaussian splat scenic environment from a Pexels Machu Picchu video for a solitary Supernatural-style player viewpoint.

This is an R&D prototype. Do not optimize for Quest, splat count, runtime performance, compression, or Unity integration yet. The only goal is to produce the best visual-quality splat we can from publicly available Pexels video and load it in the existing PlayCanvas/SuperSplat viewer.

Target viewer:

https://phdev.github.io/machu-picchu-splat/?scene=close

Assume the current repo is the viewer repo unless inspection proves otherwise. Inspect the repo structure first and preserve the existing scene/query-parameter convention. Do not rewrite the viewer unless absolutely necessary.

## Context

Pexels license appears broad enough for R&D use, but this pipeline is unusual because it derives a 3D environment from video. Preserve source metadata and flag this as legal-review-needed before any Supernatural commercial use.

The final splat should be usable as a scenic vista from a single bounded player viewpoint, not as a full explorable environment.

Prefer Nerfstudio/splatfacto if available because it supports processing video/custom data through FFmpeg/COLMAP and training Gaussian splats from SfM initialization. If Nerfstudio is not viable, use another installable 3D Gaussian Splatting pipeline and document the choice.

## Inputs

Support both modes:

1. If `PEXELS_VIDEO_URL` is set, download/use that Pexels video.
2. If `INPUT_VIDEO` is set, use that local MP4/MOV file.
3. If neither is set, fail with a clear error telling me exactly how to set one.

Do not scrape YouTube or use non-Pexels sources.

## Target viewpoint

Build for a solitary player headbox, not a free-roam reconstruction.

Default `close` viewpoint:

- Player origin: chosen from a strong registered camera near the hero vista.
- Headbox: ±0.35m horizontal, ±0.25m vertical, ±0.30m forward/back in reconstructed units after scale normalization.
- View cone: forward scenic cone, approximately 160–180° horizontal.
- Judge quality from this headbox, not arbitrary orbit views.

If metric scale cannot be recovered, normalize the reconstruction so the chosen headbox offsets are reasonable relative to the camera path and document the arbitrary scale.

## Implementation tasks

### 1. Repo inspection

Inspect the current repo and identify:

- where scene manifests live
- where splat assets live
- how `?scene=close` maps to assets
- whether the viewer expects `.ply`, `.compressed.ply`, `.splat`, `.sog`, or another format
- how to run the viewer locally
- how to validate that the close scene loads

Write findings to:

`docs/splat_pipeline/repo_inspection.md`

### 2. Source acquisition

Create:

`scripts/acquire_pexels_video.py`

It should:

- accept `--url` or `--input-video`
- save source video under `data/sources/pexels_machu_picchu/source.mp4`
- compute SHA256
- write `data/sources/pexels_machu_picchu/source_manifest.json`
- include source URL, photographer/creator if discoverable, Pexels video ID if discoverable, download timestamp, license URL, local path, SHA256, and notes

Do not require attribution, but preserve attribution if available.

### 3. Frame extraction and filtering

Create:

`scripts/extract_training_frames.py`

It should:

- use FFmpeg/OpenCV
- extract frames from the source video
- default to 2 fps, configurable
- reject blurry frames using a Laplacian variance threshold
- reject near-duplicate frames using perceptual hash or SSIM
- save selected frames to `data/processed/close/images`
- save rejected-frame logs to `data/processed/close/frame_filter_report.json`
- produce a contact sheet at `data/processed/close/frame_contact_sheet.jpg`

Initial targets:

- 300–1,200 candidate frames
- 200–800 selected frames
- if fewer than 150 selected frames survive, fail with a clear explanation

### 4. Camera solve / SfM

Create:

`scripts/run_colmap_or_nerfstudio_process.py`

Use the best available path.

Preferred Nerfstudio video path:

```bash
ns-process-data video --data data/sources/pexels_machu_picchu/source.mp4 --output-dir data/processed/close_ns
```

Preferred Nerfstudio images path:

```bash
ns-process-data images --data data/processed/close/images --output-dir data/processed/close_ns
```

If Nerfstudio is unavailable, fall back to direct COLMAP.

Save a report:

`data/processed/close/pose_report.json`

Required metrics:

- total selected frames
- registered frames
- registration ratio
- sparse point count
- median/mean reprojection error if available
- notes about failures/cuts/poor parallax

Hard stop conditions:

- registered frames < 150
- registration ratio < 0.50
- sparse reconstruction obviously empty or broken

Preferred target:

- registered frames >= 250
- registration ratio >= 0.70
- median reprojection error <= 2.0 px if reported

### 5. Train splat

Create:

`scripts/train_splat.sh`

Use Nerfstudio splatfacto if available:

```bash
ns-train splatfacto --data data/processed/close_ns
```

Use sane defaults. Do not optimize splat count, compression, or runtime performance yet.

Train until a usable checkpoint/export exists. Prefer a full-quality export.

Export to one or more of:

- `exports/close/close.ply`
- `exports/close/close.compressed.ply`
- `exports/close/close.splat`

Before inventing commands, run the actual CLI help for the installed tools and record exact commands used in:

`docs/splat_pipeline/commands_used.md`

### 6. Viewpoint and validation renders

Create:

`scripts/render_validation_views.py`

Generate validation renders from:

- the selected hero camera
- left/right head lean
- up/down head movement
- forward/back movement
- small yaw sweep around the hero view
- one source-frame matched view if possible

Output:

- `eval/close/headbox_renders/*.png`
- `eval/close/contact_sheet.png`
- `eval/close/viewpoint_manifest.json`

The contact sheet should make it easy to visually judge floaters, holes, smear, bad parallax, and scenic composition.

### 7. Publish into viewer

Update the existing viewer repo so the close scene uses the new splat output.

Requirements:

- `?scene=close` loads the generated splat locally
- no unrelated viewer redesign
- preserve existing controls and scene naming
- store generated/public assets in the repo’s existing convention
- document any required deployment step

If the generated file is too large for GitHub Pages, document the exact problem and provide a fallback local viewer path.

### 8. Validation script

Create:

`scripts/validate_close_splat.sh`

It should check:

- source manifest exists
- extracted frames exist
- pose report exists and passes hard thresholds
- trained splat export exists and is non-empty
- validation contact sheet exists
- viewer scene manifest points to the generated close splat
- local viewer can be started or static files can be served
- final report exists

Write final report:

`docs/splat_pipeline/final_report.md`

## Done when

The task is complete only when:

1. A trained splat exists at `exports/close/`.
2. The `close` scene in the PlayCanvas viewer points to the generated splat.
3. `scripts/validate_close_splat.sh` passes.
4. `docs/splat_pipeline/final_report.md` includes:
   - source video URL/path
   - license/source metadata
   - frame extraction counts
   - COLMAP/Nerfstudio registration metrics
   - training command used
   - exported splat path and file size
   - validation render contact sheet path
   - known visual issues
   - next recommended capture/training improvements

## Verifiable metrics

### Source

- `source_manifest.json` exists
- SHA256 recorded
- Pexels URL or local source path recorded
- license URL recorded

### Frames

- >=150 selected sharp/non-duplicate frames
- preferred: 200–800 selected frames
- contact sheet generated

### SfM

- >=150 registered frames
- registration ratio >=50%
- preferred: >=250 registered frames and >=70% registration
- sparse point cloud non-empty
- reprojection error reported if available
- preferred median reprojection error <=2.0 px if reported

### Training

- splat export exists
- export is non-empty
- training command recorded
- final checkpoint/export path recorded

### Viewpoint QA

- hero render exists
- 6 headbox-offset renders exist
- yaw-sweep renders exist
- validation contact sheet exists

### Viewer

- `?scene=close` points to generated splat
- local/static viewer can load scene
- validation script passes

## Non-goals

Do not:

- optimize for Quest
- reduce splat count
- build Unity integration
- implement collision
- add gameplay
- use YouTube
- use non-Pexels media
- rewrite the viewer UI
- claim commercial clearance beyond “Pexels source metadata preserved; legal review required”
