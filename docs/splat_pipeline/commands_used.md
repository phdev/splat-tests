# Commands Used: Pexels Single-View Splat

This file records the exact commands used for the Pexels-to-splat prototype.

## Tool Availability

```bash
which ffmpeg
which ffprobe
which yt-dlp
which colmap
which ns-process-data
which ns-train
which ns-export
which npx
```

Result on 2026-06-28:

- `ffmpeg`: `/opt/homebrew/bin/ffmpeg`
- `ffprobe`: `/opt/homebrew/bin/ffprobe`
- `yt-dlp`: `/Users/peterhowell/.pyenv/shims/yt-dlp`
- `colmap`: `/opt/homebrew/bin/colmap`
- `ns-process-data`: not found
- `ns-train`: not found
- `ns-export`: not found
- `npx`: `/opt/homebrew/bin/npx`

## Planned Source

Pexels video page:

```text
https://www.pexels.com/video/stairs-pyramid-finding-temple-19407367/
```

Direct Pexels download redirect:

```bash
curl -sI -L "https://www.pexels.com/download/video/19407367/"
```

Observed MP4:

```text
https://videos.pexels.com/video-files/19407367/uhd_60fps.mp4
```

Observed media probe:

```bash
ffprobe -v error -show_entries stream=width,height,avg_frame_rate,nb_frames,duration \
  -show_entries format=duration,size -of compact=p=0:nk=1 \
  "https://videos.pexels.com/video-files/19407367/uhd_60fps.mp4"
```

Result:

```text
2560|1440|60000/1001|18.901667|1133
18.965000|21698377
```

## Source Acquisition

```bash
python3 scripts/acquire_pexels_video.py \
  --url 'https://www.pexels.com/video/stairs-pyramid-finding-temple-19407367/' \
  --title 'Breathtaking Machu Picchu Ruins at Dawn' \
  --creator 'Florian Delée' \
  --notes 'Selected for longer landscape 60fps Machu Picchu ruins footage; Pexels source metadata preserved, legal review required before commercial use.'
```

## Frame Extraction

Initial duplicate-filtered extraction was too strict for this short panning clip, so the selected set was regenerated at 12 fps with blur rejection and duplicate rejection disabled:

```bash
python3 scripts/extract_training_frames.py \
  --fps 12 \
  --blur-threshold 20 \
  --duplicate-hash-threshold -1 \
  --min-selected 150
```

## Training / SfM

The local Nerfstudio CLIs were not installed, and local COLMAP is avoided for this repo because previous notes document matcher instability on this Mac. The active training path is Runpod plus the repo's Inria 3DGS helper:

```bash
ITERS=30000 NT=16 MATCHER=sequential SEQ_OVERLAP=10 bash scripts/train_splat.sh
```

That first COLMAP pass registered only 127 of 227 frames, below the hard threshold. Training was stopped before accepting the result, and the same pod was reused manually for denser sequential matching:

```bash
DS=close ITERS=30000 NT=16 MATCHER=sequential SEQ_OVERLAP=30 \
  TORCH_CUDA_ARCH_LIST=8.9 \
  setsid bash /workspace/pod_full.sh >/workspace/run_overlap30.log 2>&1 </dev/null &
```

The denser overlap-30 pass spent mapping time on small candidate submodels instead of growing a usable reconstruction, so the frame set was regenerated more densely and rerun with the cheaper overlap-10 matcher:

```bash
python3 scripts/extract_training_frames.py \
  --fps 20 \
  --blur-threshold 20 \
  --duplicate-hash-threshold -1 \
  --min-selected 150
```

```bash
DS=close ITERS=30000 NT=16 MATCHER=sequential SEQ_OVERLAP=10 \
  TORCH_CUDA_ARCH_LIST=8.9 \
  setsid bash /workspace/pod_full.sh >/workspace/run_20fps_overlap10.log 2>&1 </dev/null &
```

The mapper produced a best submodel with 208 registered images. The pod began mapping additional smaller submodels, so training was continued manually from the best model:

```bash
DS=close ITERS=30000 TORCH_CUDA_ARCH_LIST=8.9 \
  setsid bash /workspace/pod_continue_close_from_model0.sh \
  >/workspace/continue_model0.log 2>&1 </dev/null &
```

The helper stopped the multi-model mapper, undistorted from `distorted/sparse/0`,
then a clean retry completed training after the first launch hit a transient
layout race:

```bash
setsid env TORCH_CUDA_ARCH_LIST=8.9 python3 /workspace/gs/train.py \
  -s /workspace/close -m /workspace/close/output \
  --iterations 30000 --test_iterations 30000 --save_iterations 30000
```

Result:

```text
Training complete. [28/06 19:05:25]
/workspace/close/output/point_cloud/iteration_30000/point_cloud.ply 128M
```

Artifacts were pulled and the pod was deleted:

```bash
scp -P 40148 root@213.192.2.125:/workspace/close/output/point_cloud/iteration_30000/point_cloud.ply \
  exports/close/close.ply
```

```bash
python3 scripts/runpod_pod.py delete 1w3xs9nnpy7f3k
```

Result:

```text
DELETED 1w3xs9nnpy7f3k (status 204)
```

## Viewer Conversion

```bash
npx -y @playcanvas/splat-transform exports/close/close.ply -N site/close.sog -w
```

## Validation Renders

```bash
python3 scripts/render_validation_views.py --splat exports/close/close.ply --settings site/close.json --output-dir eval/close
```

## Validation Gate

```bash
bash scripts/validate_close_splat.sh
```

Result:

```text
PASS validate_close_splat
```

## Deploy Asset Mirror

```bash
cp site/close.sog ~/mp-deploy/close.sog
cp site/close.json ~/mp-deploy/close.json
```
