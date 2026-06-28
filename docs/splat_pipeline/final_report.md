# Pexels Close Splat Final Report

Date: 2026-06-28

## Source video

- Source page: https://www.pexels.com/video/stairs-pyramid-finding-temple-19407367/
- Resolved MP4: https://videos.pexels.com/video-files/19407367/uhd_60fps.mp4
- Local source path: `data/sources/pexels_machu_picchu/source.mp4`
- Title: Breathtaking Machu Picchu Ruins at Dawn
- Creator: Florian Delee
- SHA256: `187a75371ee29c41809bf9377f39296b416d2e21c70831d2107e356738e8a6b7`

## License and source metadata

- License URL: https://www.pexels.com/license/
- Source metadata is preserved in `data/sources/pexels_machu_picchu/source_manifest.json`.
- `legal_review_needed` is set to `true`; this is suitable for R&D review, not cleared commercial Supernatural use.

## Frame extraction

- Command: `python3 scripts/extract_training_frames.py --fps 20 --blur-threshold 20 --duplicate-hash-threshold -1 --min-selected 150`
- Candidate frames: 378
- Selected frames: 378
- Rejected frames: 0
- Contact sheet: `data/processed/close/frame_contact_sheet.jpg`

## COLMAP/Nerfstudio registration

- Local Nerfstudio CLIs were not installed, so the pipeline used Runpod plus Inria 3DGS/COLMAP.
- Best COLMAP model: 208 registered frames from 378 selected frames.
- Registration ratio: 0.5502645502645502
- Sparse point count: 8,335
- Median reprojection error: 0.854655726785134 px
- Mean reprojection error: 0.9121284840119691 px
- Hard stop passed: true
- Preferred target passed: false, because registration ratio stayed below 0.70 and registered frames stayed below 250.

## Training command

The successful run used the 20 fps frame set, sequential matching, and a manual continuation from the best 208-frame sparse model:

```bash
DS=close ITERS=30000 NT=16 MATCHER=sequential SEQ_OVERLAP=10 \
  TORCH_CUDA_ARCH_LIST=8.9 \
  setsid bash /workspace/pod_full.sh >/workspace/run_20fps_overlap10.log 2>&1 </dev/null &
```

Training was then completed from `distorted/sparse/0`:

```bash
python3 /workspace/gs/train.py -s /workspace/close -m /workspace/close/output \
  --iterations 30000 --test_iterations 30000 --save_iterations 30000
```

Training completed at iteration 30000 with a saved Gaussian PLY.

## Exported splat

- Trained PLY: `exports/close/close.ply`
- PLY size: 133,884,331 bytes
- PLY splat count: 539,850
- Viewer SOG: `site/close.sog`
- SOG size: 9.0 MB
- Conversion command: `npx -y @playcanvas/splat-transform exports/close/close.ply -N site/close.sog -w`
- Viewer settings: `site/close.json`
- `?scene=close` maps to `close.sog` and `close.json` in `site/index.html`.

## Validation render

- Command: `python3 scripts/render_validation_views.py`
- Method: trained-PLY rendering with `@playcanvas/splat-transform`
- Validation renders: `eval/close/headbox_renders/*.png`
- Validation render contact sheet: `eval/close/contact_sheet.png`
- View manifest: `eval/close/viewpoint_manifest.json`

## Known visual issues

- The wall and nearby terraces are recognizable, but large gray voids remain where the single video lacks coverage.
- Sky and cloud areas smear into translucent bands and floaters.
- Some foreground/background geometry is incomplete or unstable under yaw and headbox offsets.
- The result is usable as an R&D scenic splat prototype, not as a production-quality explorable environment.

## Next recommended capture/training improvements

- Use a longer Pexels clip or real capture with slower camera motion, stronger parallax, and less sky-dominant framing.
- Capture or select multiple passes from the same viewpoint arc to fill the gray voids and reduce floaters.
- Run denser COLMAP matching or use a capture with cleaner adjacent-frame overlap to push registration above the preferred 250-frame, 0.70-ratio target.
- Add mask-based sky handling before training to reduce cloud smear.
- Consider cleanup/filtering passes after training once the visual target and acceptable loss of detail are defined.
