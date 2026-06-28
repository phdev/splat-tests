#!/bin/bash
# Continue the Pexels close Runpod job from the already-written best COLMAP model.
set -euo pipefail

export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.9}"
ITERS="${ITERS:-30000}"
DS="${DS:-close}"
ROOT="/workspace/$DS"
BEST="${BEST:-$ROOT/distorted/sparse/0}"

log(){ echo "[$(date +%H:%M:%S)] $*"; }

log "STOP_MULTIMODEL_MAPPER"
pkill -f "colmap mapper .*${ROOT}/distorted/database.db" || true
pkill -f "bash /workspace/pod_full.sh" || true
sleep 3

cd "$ROOT"
[ -f "$BEST/images.bin" ] || { log "MISSING_BEST_MODEL $BEST"; exit 1; }

log "BEST_MODEL_ANALYZE $BEST"
colmap model_analyzer --path "$BEST" 2>&1 || true

log "UNDISTORT_FROM_MODEL0"
rm -rf sparse images output
colmap image_undistorter \
  --image_path input \
  --input_path "$BEST" \
  --output_path "$ROOT" \
  --output_type COLMAP >undist_model0.log 2>&1 || { log UNDIST_FAIL; tail -40 undist_model0.log; exit 1; }

mkdir -p sparse/0
mv sparse/*.bin sparse/0/ 2>/dev/null || true
[ -f sparse/0/cameras.bin ] || { log LAYOUT_FAIL; find sparse -maxdepth 2 -type f; exit 1; }

log "TRAIN_MODEL0 iters=$ITERS"
python3 /workspace/gs/train.py \
  -s "$ROOT" \
  -m "$ROOT/output" \
  --iterations "$ITERS" \
  --test_iterations "$ITERS" \
  --save_iterations "$ITERS" >train_model0.log 2>&1 || { log TRAIN_FAIL; tail -60 train_model0.log; exit 1; }

PLY="output/point_cloud/iteration_$ITERS/point_cloud.ply"
log "ALL_DONE_MANUAL registered=208 ply_bytes=$(stat -c%s "$PLY" 2>/dev/null || echo MISSING)"
