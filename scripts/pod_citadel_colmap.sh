#!/bin/bash
# On the ArtiFixer pod: fetch the citadel clip + extract the continuous-orbit
# frames + run COLMAP -> a COLMAP dir (images/ + sparse/0) for ArtiFixer prep.
# (Avoids slow Mac->pod upload; the pod has fast internet.)
set -uo pipefail
log(){ echo "[$(date +%H:%M:%S)] $*"; }
cd /workspace
NT="${NT:-16}"

log SETUP
pip install -q yt-dlp >/workspace/cm_setup.log 2>&1
apt-get update -qq && apt-get install -y -qq colmap ffmpeg >>/workspace/cm_setup.log 2>&1 || { log APT_FAIL; tail -5 /workspace/cm_setup.log; exit 1; }

log DOWNLOAD
python3 -m yt_dlp --no-warnings -f 137 -o /workspace/wt.mp4 "https://www.youtube.com/watch?v=_hbRXmSzK38" >/workspace/cm_dl.log 2>&1 || { log DL_FAIL; tail -5 /workspace/cm_dl.log; exit 1; }
rm -rf /workspace/cit && mkdir -p /workspace/cit/input
ffmpeg -hide_banner -loglevel error -ss 34 -to 63 -i /workspace/wt.mp4 -vf fps=3 -qscale:v 2 /workspace/cit/input/c%04d.jpg
log "FRAMES=$(ls /workspace/cit/input | wc -l)"

cd /workspace/cit
mkdir -p distorted/sparse
log FEAT
colmap feature_extractor --database_path distorted/database.db --image_path input \
  --ImageReader.single_camera 1 --ImageReader.camera_model OPENCV \
  --SiftExtraction.use_gpu 0 --SiftExtraction.num_threads "$NT" --SiftExtraction.max_image_size 1920 \
  >feat.log 2>&1 || { log FEAT_FAIL; tail -6 feat.log; exit 1; }
log MATCH
colmap exhaustive_matcher --database_path distorted/database.db \
  --SiftMatching.use_gpu 0 --SiftMatching.num_threads "$NT" >match.log 2>&1 || { log MATCH_FAIL; tail -6 match.log; exit 1; }
log MAP
colmap mapper --database_path distorted/database.db --image_path input \
  --output_path distorted/sparse --Mapper.num_threads "$NT" >map.log 2>&1 || { log MAP_FAIL; tail -6 map.log; exit 1; }
[ -f distorted/sparse/0/cameras.bin ] || { log NO_MODEL; exit 1; }
REG=$(colmap model_analyzer --path distorted/sparse/0 2>&1 | grep -i 'Registered images' | grep -oE '[0-9]+' | head -1)
log "REGISTERED=$REG"
log UNDISTORT
colmap image_undistorter --image_path input --input_path distorted/sparse/0 \
  --output_path /workspace/cit --output_type COLMAP >undist.log 2>&1 || { log UNDIST_FAIL; tail -6 undist.log; exit 1; }
mkdir -p sparse/0 && mv sparse/*.bin sparse/0/ 2>/dev/null
[ -f sparse/0/cameras.bin ] || { log LAYOUT_FAIL; exit 1; }
log "COLMAP_DONE images=$(ls images | wc -l) reg=$REG"
