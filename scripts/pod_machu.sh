#!/bin/bash
# Robust pod-side COLMAP (capped threads — the 62GB container OOM-kills default
# 128-thread CPU SIFT) + Inria 3DGS. Explicit checks (Inria convert.py masks
# COLMAP failure via exit-code truncation). Dataset at /workspace/ed/input/*.jpg.
set -uo pipefail
cd /workspace/ed
NT="${NT:-16}"
ITERS="${ITERS:-30000}"
log(){ echo "[$(date +%H:%M:%S)] $*"; }

log "PIN_NUMPY (<2 for torch 2.1 ABI)"
pip install -q "numpy<2" >/workspace/np.log 2>&1 || log NUMPY_WARN

rm -rf distorted sparse images output
mkdir -p distorted/sparse

log "FEAT (nt=$NT)"
colmap feature_extractor --database_path distorted/database.db --image_path input \
  --ImageReader.single_camera 1 --ImageReader.camera_model OPENCV \
  --SiftExtraction.use_gpu 0 --SiftExtraction.num_threads "$NT" --SiftExtraction.max_image_size 1920 \
  >feat.log 2>&1 || { log FEAT_FAIL; tail -8 feat.log; exit 1; }

log "MATCH (exhaustive, nt=$NT)"
colmap exhaustive_matcher --database_path distorted/database.db \
  --SiftMatching.use_gpu 0 --SiftMatching.num_threads "$NT" \
  >match.log 2>&1 || { log MATCH_FAIL; tail -8 match.log; exit 1; }

log "MAP"
colmap mapper --database_path distorted/database.db --image_path input \
  --output_path distorted/sparse --Mapper.num_threads "$NT" \
  >map.log 2>&1 || { log MAP_FAIL; tail -8 map.log; exit 1; }

# pick the largest sub-model (mapper may fragment a cut-up montage into several)
BEST=""; BESTN=0
for d in distorted/sparse/*/; do
  [ -f "$d/cameras.bin" ] || continue
  n=$(colmap model_analyzer --path "$d" 2>&1 | grep -i 'Registered images' | grep -oE '[0-9]+' | head -1)
  n=${n:-0}
  log "  submodel $d -> $n registered"
  if [ "$n" -gt "$BESTN" ]; then BESTN=$n; BEST=$d; fi
done
[ -n "$BEST" ] || { log NO_MODEL; exit 1; }
log "BEST_MODEL=$BEST REGISTERED=$BESTN of 169"

log "UNDISTORT"
colmap image_undistorter --image_path input --input_path "${BEST%/}" \
  --output_path /workspace/ed --output_type COLMAP \
  >undist.log 2>&1 || { log UNDIST_FAIL; tail -8 undist.log; exit 1; }
mkdir -p sparse/0 && mv sparse/*.bin sparse/0/ 2>/dev/null
[ -f sparse/0/cameras.bin ] || { log LAYOUT_FAIL; ls -R sparse; exit 1; }
log "DATASET_READY images=$(ls images | wc -l) sparse0=$(ls sparse/0)"

log "TRAIN iters=$ITERS"
python3 /workspace/gs/train.py -s /workspace/ed -m /workspace/ed/output \
  --iterations "$ITERS" --test_iterations "$ITERS" --save_iterations "$ITERS" \
  >train.log 2>&1 || { log TRAIN_FAIL; tail -30 train.log; exit 1; }

PLY="output/point_cloud/iteration_$ITERS/point_cloud.ply"
log "ALL_DONE registered=$BESTN ply_bytes=$(stat -c%s "$PLY" 2>/dev/null || echo MISSING)"
