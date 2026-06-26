#!/bin/bash
# Native install of ArtiFixer deps on a Runpod H100 (CUDA 12), replicating
# Dockerfile.cuda12 (Runpod has no docker-in-docker). Stage markers for monitoring.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive
export TORCH_CUDA_ARCH_LIST="9.0"            # H100 = sm_90
export MAX_JOBS=16 NVCC_THREADS=2
log(){ echo "[$(date +%H:%M:%S)] $*"; }
cd /workspace/af

log STAGE_APT
apt-get update -qq && apt-get install -y -qq wget git curl build-essential gcc-11 g++-11 \
  libgl1-mesa-dev libglib2.0-0 ninja-build >/workspace/af_apt.log 2>&1 || { log APT_FAIL; tail -5 /workspace/af_apt.log; exit 1; }
export CC=gcc-11 CXX=g++-11

log STAGE_TORCH
pip install -q torch==2.11.0 torchvision --index-url https://download.pytorch.org/whl/cu128 \
  >/workspace/af_torch.log 2>&1 || { log TORCH_FAIL; tail -8 /workspace/af_torch.log; exit 1; }
pip uninstall -y flash-attn opencv-python >/dev/null 2>&1 || true

log STAGE_3DGRUT_REQ
cd thirdparty/3DGRUT-ArtiFixer
pip install -q -r requirements.txt >/workspace/af_3dgrut.log 2>&1 || { log 3DGRUT_REQ_FAIL; tail -15 /workspace/af_3dgrut.log; }
log STAGE_SLANG
bash scripts/install_slangc.sh /usr/local >>/workspace/af_3dgrut.log 2>&1 || { log SLANG_FAIL; tail -10 /workspace/af_3dgrut.log; }
log STAGE_3DGRUT_BUILD
pip install -q -e . >>/workspace/af_3dgrut.log 2>&1 && log 3DGRUT_OK || { log 3DGRUT_BUILD_FAIL; tail -20 /workspace/af_3dgrut.log; }
cd /workspace/af

log STAGE_FA3_BUILD
git clone --depth 1 https://github.com/Dao-AILab/flash-attention.git /tmp/fa >/workspace/af_fa3.log 2>&1
( cd /tmp/fa/hopper && pip install . >>/workspace/af_fa3.log 2>&1 ) && log FA3_OK || { log FA3_FAIL; tail -25 /workspace/af_fa3.log; }
rm -rf /tmp/fa

log STAGE_FA4
pip install -q --pre flash-attn-4 >/workspace/af_fa4.log 2>&1 && log FA4_OK || log FA4_WARN
pip install -q --force-reinstall --no-deps "cuda-python==12.6.2.post1" >>/workspace/af_fa4.log 2>&1 || true

log STAGE_DEPS
pip install -q accelerate==1.13.0 diffusers==0.37.1 transformers==5.5.0 ftfy >/workspace/af_deps.log 2>&1 || log DEPS_WARN
pip install -q einops scipy wandb tqdm Pillow matplotlib opencv-python-headless pyyaml \
  torchmetrics imageio-ffmpeg h5py av torch-fidelity "git+https://github.com/microsoft/MoGe.git" \
  >>/workspace/af_deps.log 2>&1 && log MOGE_OK || log MOGE_WARN

log STAGE_VERIFY
python -c "import torch;print('torch',torch.__version__,'cuda',torch.version.cuda,'avail',torch.cuda.is_available())" 2>&1
python -c "import flash_attn_interface; print('FA3 import ok')" 2>&1 || echo FA3_IMPORT_FAIL
python -c "import cv2; print('cv2 ok',cv2.__version__)" 2>&1 || echo CV2_FAIL
python -c "from moge.model.v2 import MoGeModel; print('MoGe ok')" 2>&1 || echo MOGE_IMPORT_FAIL
log ALL_INSTALL_DONE
