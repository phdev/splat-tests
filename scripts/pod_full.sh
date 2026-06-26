#!/bin/bash
# Fresh-pod: full setup (apt colmap + clone Inria 3DGS + build rasterizer) THEN
# robust COLMAP (capped threads — 62GB container OOM-kills default 128) + train.
#   DS=<name> ITERS=30000 NT=16 bash pod_full.sh   (frames at /workspace/$DS/input/*.jpg)
set -uo pipefail
DS="${DS:-ed}"; NT="${NT:-16}"; ITERS="${ITERS:-30000}"
export DEBIAN_FRONTEND=noninteractive
export TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST:-8.0;8.6;8.9+PTX}"
log(){ echo "[$(date +%H:%M:%S)] $*"; }

log "SETUP_APT"
apt-get update -qq && apt-get install -y -qq colmap imagemagick >/workspace/apt.log 2>&1 || { log APT_FAIL; tail -20 /workspace/apt.log; exit 1; }
log "SETUP_CLONE"
[ -d /workspace/gs ] || git clone --recursive https://github.com/graphdeco-inria/gaussian-splatting.git /workspace/gs >/workspace/clone.log 2>&1 || { log CLONE_FAIL; exit 1; }
log "SETUP_PIP (build rasterizer)"
pip install -q plyfile tqdm opencv-python-headless >/workspace/pip.log 2>&1
pip install -q /workspace/gs/submodules/diff-gaussian-rasterization /workspace/gs/submodules/simple-knn >>/workspace/pip.log 2>&1 || { log PIP_FAIL; tail -30 /workspace/pip.log; exit 1; }
pip install -q "numpy<2" >>/workspace/pip.log 2>&1 || log NUMPY_WARN

cd "/workspace/$DS"
NIMG=$(ls input | wc -l)
rm -rf distorted sparse images output; mkdir -p distorted/sparse
log "FEAT (nt=$NT, imgs=$NIMG)"
colmap feature_extractor --database_path distorted/database.db --image_path input \
  --ImageReader.single_camera 1 --ImageReader.camera_model OPENCV \
  --SiftExtraction.use_gpu 0 --SiftExtraction.num_threads "$NT" --SiftExtraction.max_image_size 1920 \
  >feat.log 2>&1 || { log FEAT_FAIL; tail -8 feat.log; exit 1; }
log "MATCH (exhaustive)"
colmap exhaustive_matcher --database_path distorted/database.db \
  --SiftMatching.use_gpu 0 --SiftMatching.num_threads "$NT" >match.log 2>&1 || { log MATCH_FAIL; tail -8 match.log; exit 1; }
log "MAP"
colmap mapper --database_path distorted/database.db --image_path input \
  --output_path distorted/sparse --Mapper.num_threads "$NT" >map.log 2>&1 || { log MAP_FAIL; tail -8 map.log; exit 1; }
BEST=""; BESTN=0
for d in distorted/sparse/*/; do
  [ -f "$d/cameras.bin" ] || continue
  n=$(colmap model_analyzer --path "$d" 2>&1 | grep -i 'Registered images' | grep -oE '[0-9]+' | head -1); n=${n:-0}
  log "  submodel $d -> $n"; [ "$n" -gt "$BESTN" ] && { BESTN=$n; BEST=$d; }
done
[ -n "$BEST" ] || { log NO_MODEL; exit 1; }
log "REGISTERED=$BESTN of $NIMG"
colmap image_undistorter --image_path input --input_path "${BEST%/}" \
  --output_path "/workspace/$DS" --output_type COLMAP >undist.log 2>&1 || { log UNDIST_FAIL; exit 1; }
mkdir -p sparse/0 && mv sparse/*.bin sparse/0/ 2>/dev/null
[ -f sparse/0/cameras.bin ] || { log LAYOUT_FAIL; exit 1; }
log "TRAIN iters=$ITERS"
python3 /workspace/gs/train.py -s "/workspace/$DS" -m "/workspace/$DS/output" \
  --iterations "$ITERS" --test_iterations "$ITERS" --save_iterations "$ITERS" \
  >train.log 2>&1 || { log TRAIN_FAIL; tail -30 train.log; exit 1; }
PLY="output/point_cloud/iteration_$ITERS/point_cloud.ply"
log "ALL_DONE registered=$BESTN ply_bytes=$(stat -c%s "$PLY" 2>/dev/null || echo MISSING)"
