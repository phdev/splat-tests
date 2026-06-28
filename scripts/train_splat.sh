#!/bin/bash
# Train/export the Pexels close splat. Prefer local Nerfstudio if available;
# otherwise use the repo's proven Runpod + Inria 3DGS path.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

IMAGES="${IMAGES:-data/processed/close/images}"
EXPORT_DIR="${EXPORT_DIR:-exports/close}"
ITERS="${ITERS:-30000}"
NT="${NT:-16}"
MATCHER="${MATCHER:-sequential}"
SEQ_OVERLAP="${SEQ_OVERLAP:-10}"
RUNPOD_GPU="${RUNPOD_GPU:-NVIDIA RTX A6000,NVIDIA A40,NVIDIA L40S,NVIDIA RTX 6000 Ada Generation,NVIDIA GeForce RTX 4090}"
mkdir -p "$EXPORT_DIR" docs/splat_pipeline data/processed/close

log(){ echo "[$(date +%H:%M:%S)] $*"; }
cmdlog(){ printf '\n```bash\n%s\n```\n' "$*" >> docs/splat_pipeline/commands_used.md; }

NIMG=$(find "$IMAGES" -maxdepth 1 -type f -name '*.jpg' | wc -l | tr -d ' ')
[ "$NIMG" -ge 150 ] || { echo "Need at least 150 extracted frames in $IMAGES; found $NIMG" >&2; exit 1; }

if command -v ns-train >/dev/null 2>&1 && command -v ns-process-data >/dev/null 2>&1; then
  log "Nerfstudio detected, but export wiring for this repo still expects PLY/SOG. Use Runpod path for now."
fi

log "Creating Runpod pod"
POD_ID=$(python3 scripts/runpod_pod.py create --name pexels-close-3dgs --disk 80 --vol 120 --gpu "$RUNPOD_GPU")
log "pod=$POD_ID"
cleanup(){
  if [ -n "${POD_ID:-}" ]; then
    log "Deleting pod $POD_ID"
    python3 scripts/runpod_pod.py delete "$POD_ID" || true
  fi
}
trap cleanup EXIT

ENDPOINT=$(python3 scripts/runpod_pod.py wait "$POD_ID")
HOST=$(echo "$ENDPOINT" | awk '{print $1}')
PORT=$(echo "$ENDPOINT" | awk '{print $3}')
log "ssh=$HOST port=$PORT"

SSH_BASE=(ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p "$PORT" "$HOST")
SCP_BASE=(scp -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -P "$PORT")

log "Packing frames"
rm -f /tmp/pexels_close_frames.tgz /tmp/pexels_close_colmap.tgz
COPYFILE_DISABLE=1 tar --no-xattrs -czf /tmp/pexels_close_frames.tgz -C data/processed/close images

log "Uploading frames and pod script"
"${SCP_BASE[@]}" /tmp/pexels_close_frames.tgz scripts/pod_full.sh "$HOST:/workspace/"

log "Launching remote training"
"${SSH_BASE[@]}" "set -e; mkdir -p /workspace/close; tar --no-same-owner -xzf /workspace/pexels_close_frames.tgz -C /workspace/close; mv /workspace/close/images /workspace/close/input; find /workspace/close -name '._*' -delete; DS=close ITERS=$ITERS NT=$NT MATCHER=$MATCHER SEQ_OVERLAP=$SEQ_OVERLAP setsid bash /workspace/pod_full.sh >/workspace/run.log 2>&1 </dev/null & echo \$!"

log "Monitoring remote training"
while true; do
  sleep 30
  OUT=$("${SSH_BASE[@]}" "tail -40 /workspace/run.log 2>/dev/null || true; echo __PS__; pgrep -af 'pod_full|train.py|colmap' || true; echo __PLY__; stat -c%s /workspace/close/output/point_cloud/iteration_$ITERS/point_cloud.ply 2>/dev/null || true" || true)
  echo "$OUT"
  if echo "$OUT" | grep -q "ALL_DONE"; then
    break
  fi
  if ! echo "$OUT" | awk '/__PS__/{p=1;next}/__PLY__/{p=0}p' | grep -qE 'pod_full|train.py|colmap'; then
    echo "Remote training process is not running and ALL_DONE was not observed" >&2
    "${SSH_BASE[@]}" "tail -120 /workspace/run.log; tail -80 /workspace/close/*.log 2>/dev/null || true" >&2 || true
    exit 1
  fi
done

log "Pulling trained PLY and COLMAP model"
"${SCP_BASE[@]}" "$HOST:/workspace/close/output/point_cloud/iteration_$ITERS/point_cloud.ply" "$EXPORT_DIR/close.ply"
"${SSH_BASE[@]}" "tar -czf /workspace/close_colmap.tgz -C /workspace/close sparse images distorted/sparse 2>/dev/null || tar -czf /workspace/close_colmap.tgz -C /workspace/close sparse images"
"${SCP_BASE[@]}" "$HOST:/workspace/close_colmap.tgz" /tmp/pexels_close_colmap.tgz
rm -rf data/processed/close_colmap
mkdir -p data/processed/close_colmap
tar -xzf /tmp/pexels_close_colmap.tgz -C data/processed/close_colmap

log "Writing pose report"
cmdlog "python3 scripts/run_colmap_or_nerfstudio_process.py --analyze-colmap-dir data/processed/close_colmap --notes Runpod/Inria_3DGS_COLMAP"
python3 scripts/run_colmap_or_nerfstudio_process.py \
  --analyze-colmap-dir data/processed/close_colmap \
  --notes "Runpod/Inria 3DGS COLMAP fallback; pod $POD_ID"

cmdlog "ITERS=$ITERS NT=$NT MATCHER=$MATCHER SEQ_OVERLAP=$SEQ_OVERLAP bash scripts/train_splat.sh"
log "Exported $EXPORT_DIR/close.ply"
