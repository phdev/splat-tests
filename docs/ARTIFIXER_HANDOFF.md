# Handoff: finish ArtiFixer gap-fill on the Machu Picchu citadel splat

You are taking over a task mid-flight. A 3-scene Machu Picchu Gaussian-splat viewer
is **already built, live, and complete**. The remaining work is an **optional bonus**:
run NVIDIA **ArtiFixer** (SIGGRAPH 2026) on an H100 to gap-fill/extend the citadel
splat, then add the result as a 4th scene in the viewer. The hard part (building
ArtiFixer's environment) is **already done**.

## Update: 2026-06-26
The H100 pod below was deleted to stop billing:
`python3 ~/splat-tests/scripts/runpod_pod.py delete 5kafrg3yi0euq1` returned
`DELETED 5kafrg3yi0euq1 (status 204)`. Resume this bonus path on a fresh H100 and
rebuild with `~/splat-tests/scripts/install_artifixer.sh`.

## Active restart: 2026-06-26
A fresh H100 pod was launched for the restarted run and has now been deleted:
- Pod id: **`89kxgxx2jc37kn`**
- SSH:
  ```bash
  ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -p 14533 root@216.243.220.222
  ```
- Image: `runpod/pytorch:1.0.7-cu1281-torch291-ubuntu2204`
- Disk/volume: `--disk 150 --vol 180`; root now has 150 GB available.
- Deleted after completion:
  `python3 ~/splat-tests/scripts/runpod_pod.py delete 89kxgxx2jc37kn` returned
  `DELETED 89kxgxx2jc37kn (status 204)`.

Completion notes:
- COLMAP registered **87/87** frames on the fresh pod.
- `prepare` completed after rerunning the metric-scale phase with cuDNN SDPA
  disabled; metric scale was `4.353987`.
- Default H100 attention paths were unusable in this image: FA3 was skipped
  because its build was hundreds of CUDA targets, and FA4 failed at runtime in
  CuTe with `fmax() takes 2 positional arguments...`. The successful inference
  run monkey-patched `list_flash_attention_impls()` to return `[]`, used
  `--attention_backend native`, `--inference_pipeline bidirectional`,
  `--bidirectional_chunk_size 11`, and `--max_neighbors_per_encode 1`.
- ArtiFixer inference produced 10 corrected held-out frames. `run_artifixer3d`
  distilled them into a 30k 3DGRUT checkpoint, rendered 87 frames, and exported
  `/workspace/citadel_artifixer3d_30000.ply`.
- The exported PLY had extreme coordinate outliers. The deployed SOG was built
  from a cleaned local PLY using `scripts/despike_ply.py` with the 1st-99th
  percentile position box and glint filtering disabled.
- The 4th scene is now `citadel-af` / `citadel_af.sog` / `citadel_af.json`
  labeled **Citadel · ArtiFixer**.

The fresh-pod run used `/workspace/bootstrap_artifixer.sh` with logs:
`/workspace/bootstrap.log`, `/workspace/install.log`, `/workspace/ckpt_download.log`,
and `/workspace/colmap.log`. The image has CUDA under `/usr/local/cuda-12.8` but
does not put `nvcc` on PATH by default, so all remote scripts exported:
`CUDA_HOME=/usr/local/cuda-12.8` and prepended `$CUDA_HOME/bin`.

Last observed ArtiFixer state before deletion:
- Original `prepare` failed after 3DGRUT training/render/metric-scale because the
  Qwen captioning model download filled the 60 GB container disk
  (`RuntimeError: ... No space left on device`).
- A manual workaround created a valid zero-prompt
  `/workspace/af-prep/citadel/captions/citadel/caption.h5` and reran
  `prepare_colmap_artifixer_inputs --phases prepare,reconstruct,render,scale`,
  producing `/workspace/af-prep/citadel/split.json` without retraining.
- `run_inference --render_trajectory all_frames` with the default `kv_cache`
  pipeline OOMed on the H100 by trying to encode all 87 frames in one item.
- A lower-memory retry was launched with
  `--inference_pipeline bidirectional --bidirectional_chunk_size 21
  --max_neighbors_per_encode 1 --save_frame_outputs_only`, but the pod was deleted
  before it completed.

Recommended fresh-pod adjustment: use a larger container disk (for example 150 GB)
or otherwise force Hugging Face/Xet temp/cache writes onto the `/workspace` volume.
This was not fully confirmed before deletion; the symptom was the Qwen/HF cache
filling the container root filesystem.

## What's already DONE (do not redo)
- Code repo: `~/splat-tests` → `github.com/phdev/splat-tests` (committed/pushed).
- Live viewer: **https://phdev.github.io/machu-picchu-splat/** — scene switcher with
  **Citadel / Aerial · 4K / Close-up**. Deploy repo: `~/mp-deploy` →
  `github.com/phdev/machu-picchu-splat` (GitHub Pages, root).
- Pipeline (all reusable): `~/splat-tests/scripts/` — `despike_ply.py`,
  `make_sog_viewer.sh`, `set_viewer_camera.py`, `runpod_pod.py` (+ `--image` flag),
  `pod_full.sh`/`pod_machu.sh` (COLMAP+3DGS), `pod_citadel_colmap.sh`,
  `install_artifixer.sh`. Read `~/splat-tests/CLAUDE.md` + `docs/machu.md` for context.

## The ArtiFixer pod (BILLING — delete when done!)
- Pod id: **`5kafrg3yi0euq1`** (Runpod, **H100 80GB**, CUDA 12.8). ~$2.5–4/hr.
- SSH (zsh won't word-split a flags var — **inline every flag**):
  ```bash
  ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      -p 15562 root@103.207.149.137
  ```
  (If the IP/port changed: `python3 ~/splat-tests/scripts/runpod_pod.py status 5kafrg3yi0euq1`.)
- **Delete when finished:** `python3 ~/splat-tests/scripts/runpod_pod.py delete 5kafrg3yi0euq1`
- Runpod API key: `~/.config/ue-splat-capture/runpod_api_key`.

## State ON the pod (all under /workspace)
- ArtiFixer repo cloned + **fully installed & verified**: `/workspace/af`
  (3DGRUT built, FA3+FA4 compiled, MoGe, torch 2.11+cu128 — all imports pass).
- Model checkpoint (68 GB): `/workspace/af-ckpt/artifixer-14b.pt`.
- Citadel COLMAP dataset (87/87 registered): `/workspace/cit`
  (`images/` + `sparse/0/{cameras,images,points3D}.bin`).
  Train/val split file: `/workspace/cit/train_images.txt` (77 train, 10 held-out val).
- **`prepare` step is RUNNING** (or just finished): trains a 3DGRUT MCMC recon →
  outputs `/workspace/af-prep/citadel/` (split.json, selected_indices.json,
  selected_images.txt) + the recon. Log: `/workspace/prep.log`. It's done when
  `/workspace/af-prep/citadel/split.json` exists and no `prepare_colmap_artifixer`
  python process is running (`pgrep -f prepare_colmap_artifixer`).

## REMAINING STEPS (run on the pod)
Run each, check the log, then proceed. All under `cd /workspace/af`.

### 0. Confirm `prepare` finished
```bash
ls /workspace/af-prep/citadel/split.json && tail -5 /workspace/prep.log
```
If `prepare` died, re-run it (the val-empty crash is fixed by the split file):
```bash
cd /workspace/af && export CHECKPOINT_PT=/workspace/af-ckpt/artifixer-14b.pt
python -m data_processing.prepare_colmap_artifixer_inputs \
  --colmap_dir /workspace/cit --output_root /workspace/af-prep/citadel \
  --selected_image_names_file /workspace/cit/train_images.txt --replace
```

### 1. `run_inference` — ArtiFixer corrects/hallucinates views
```bash
cd /workspace/af
export CHECKPOINT_PT=/workspace/af-ckpt/artifixer-14b.pt
export SCENE_ROOT=/workspace/af-prep/citadel
export SAVE_DIR=/workspace/af-corrected
python -m model_eval.run_inference \
  --evalset reconstructed_colmap --checkpoint_pt "$CHECKPOINT_PT" \
  --save_dir "$SAVE_DIR" --split_path "$SCENE_ROOT/split.json" \
  --render_trajectory all_frames
```
Note the **`ARTIFIXER_OUTPUT_DIR`** path it prints (under `$SAVE_DIR/<ckpt>/<run>`).
(16.9B model inference; ~10–30 min. Run under `setsid bash -c '... > /workspace/inf.log 2>&1' </dev/null &` and tail the log if it's long.)

### 2. `run_artifixer3d` — distill corrected frames back into the recon
```bash
export ARTIFIXER_OUTPUT_DIR=<the dir printed in step 1>
export SCENE_ID=$(basename "$SCENE_ROOT")   # = citadel
export ARTIFIXER_FRAMES_DIR="$ARTIFIXER_OUTPUT_DIR/$SCENE_ID/frames/batch_0000/pred"
python -m data_processing.run_artifixer3d \
  --scene_root "$SCENE_ROOT" --artifixer_frames_dir "$ARTIFIXER_FRAMES_DIR"
```
This produces the final **3DGRUT** recon (the gap-filled citadel).

### 3. Export 3DGRUT → a standard 3DGS `.ply`
The output is a 3DGRUT checkpoint, NOT a plain 3DGS ply. Find the recon dir
(under `/workspace/af-prep/citadel/` or the artifixer3d output) and export to ply.
3DGRUT supports ply export — look in `/workspace/af/thirdparty/3DGRUT-ArtiFixer`
for an export entrypoint (e.g. `python -m threedgrut.export ...`, an
`export_ply.py`, or a `--export-ply` flag on its trainer/render CLI; check its
README/scripts). **This export step is the one unknown** — if it's fiddly, the
3DGRUT checkpoint may already contain a gaussians ply, or render a turntable to
sanity-check. Pull the ply to the Mac.

### 4. SOG + add as a 4th viewer scene (this part is well-trodden)
On the Mac:
```bash
cd ~/splat-tests
# optional clean (recipe in CLAUDE.md; gentle):
python3 scripts/despike_ply.py <citadel_af.ply> /tmp/af_clean.ply 0.35 3.5 1.5 0.15 0.1 <box> 1.0 1.0 1.5 16 0
npx -y @playcanvas/splat-transform /tmp/af_clean.ply -N ~/mp-deploy/citadel_af.sog -w
cp site/citadel.json ~/mp-deploy/citadel_af.json   # or fit with set_viewer_camera.py
```
Add a scene to the switcher: edit `~/splat-tests/site/index.html` **and**
`~/mp-deploy/index.html` — in the `SCENES` array add
`{ id:'citadel-af', file:'citadel_af.sog', settings:'citadel_af.json', label:'Citadel · ArtiFixer' }`.
The switcher self-hides scenes whose `.sog` is absent, so just push the new files.
```bash
cd ~/mp-deploy && git add -A && git commit -m "Add ArtiFixer gap-filled citadel scene" && git push
```
QA with the headed browser (WebGPU needs a real GPU; headless is blank):
`~/.claude/skills/gstack/browse/dist/browse --headed goto <url> && ... screenshot`.
End any "it's live" message with the Pages URL.

### 5. Delete the pod
`python3 ~/splat-tests/scripts/runpod_pod.py delete 5kafrg3yi0euq1`

## For a true 360° gap-fill (optional, better result)
The default run corrects the source arc. To fill the *unobserved* angles (so the
citadel can be orbited fully), re-run `prepare` with `--trajectory_path <orbit.json>`
(a transforms-style JSON camera path orbiting the scene), then `run_inference
--render_trajectory trajectory`, then `run_artifixer3d`. You must author the orbit
JSON from the COLMAP poses (sample a ring around the scene center).

## Gotchas already hit (don't repeat)
- `prepare` crashes "min(): non-zero size" if ALL images are train (val empty) →
  always pass `--selected_image_names_file` (the split file holds out every 8th).
- HF CLI: use **`hf download`** (not deprecated `huggingface-cli download`).
- Background launches over ssh: write a script file + `setsid bash script </dev/null &`
  (nested `setsid bash -c '...'` with quotes gets mangled and prints help).
- Mac→pod upload is SLOW (limited upstream) → do downloads/COLMAP **on the pod**
  (fast internet), not via scp of big files.
- macOS tar adds `._*` junk → `find -name '._*' -delete` after extract on the pod.

## Fallback if ArtiFixer's run/export fights back
Use **Difix3D+** (same lab, predecessor, gsplat-native, much simpler):
`github.com/nv-tlabs/Difix3D` + HF `nvidia/difix`. It has a `gsplat` trainer
(`examples/gsplat/simple_trainer_difix3d.py`) and a post-render `src/inference_difix.py`.
Runs on a standard 3DGS splat (we have the citadel ply locally:
`~/splat-tests/data/machu2/citadel_v2_30000.ply`). Same goal (artifact-clean + mild
gap-fill), far higher chance of a quick result.
