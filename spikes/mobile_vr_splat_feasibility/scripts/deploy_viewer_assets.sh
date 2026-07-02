#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
VIEWER_DIR="${GHP_VIEWER_DIR:-}"

cd "$ROOT"

if [ -z "$VIEWER_DIR" ]; then
  if [ -f "$ROOT/docs/index.html" ]; then
    VIEWER_DIR="$ROOT/docs"
  elif [ -f "$ROOT/public/index.html" ]; then
    VIEWER_DIR="$ROOT/public"
  elif [ -f "$ROOT/site/index.html" ]; then
    VIEWER_DIR="$ROOT/site"
  elif [ -f "$ROOT/gh-pages/index.html" ]; then
    VIEWER_DIR="$ROOT/gh-pages"
  else
    VIEWER_DIR="$ROOT/gh_pages_splat_viewer_package"
  fi
fi

VIEWER_DIR="$(cd "$VIEWER_DIR" 2>/dev/null && pwd || true)"
if [ -z "$VIEWER_DIR" ] || [ ! -d "$VIEWER_DIR" ]; then
  echo "[viewer-deploy] missing viewer directory. Run a viewer packaging script first." >&2
  exit 1
fi

if [ "${GH_PAGES_DEPLOY:-0}" != "1" ]; then
  cat <<EOF
[viewer-deploy] GH_PAGES_DEPLOY is not 1, so no git commit or push was performed.

Review packaged assets:
  $VIEWER_DIR/splats/manifest.json
  $VIEWER_DIR/panos/panos.json

Manual deploy, if this viewer directory is in the intended Pages repo:
  cd "$VIEWER_DIR"
  git status --short
  git add splats/ panos/ README_DEPLOY.md index.html
  git commit -m "Package research viewer assets"
  git push origin \$(git branch --show-current)

Or run the gated deploy:
  GH_PAGES_DEPLOY=1 GHP_VIEWER_DIR="$VIEWER_DIR" bash spikes/mobile_vr_splat_feasibility/scripts/deploy_viewer_assets.sh
EOF
  exit 0
fi

GIT_ROOT="$(git -C "$VIEWER_DIR" rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "$GIT_ROOT" ]; then
  echo "[viewer-deploy] $VIEWER_DIR is not inside a git repo." >&2
  exit 1
fi

REMOTE="${GH_PAGES_REMOTE:-origin}"
BRANCH="${GH_PAGES_BRANCH:-$(git -C "$GIT_ROOT" branch --show-current)}"
if [ -z "$BRANCH" ]; then
  echo "[viewer-deploy] unable to determine branch; set GH_PAGES_BRANCH." >&2
  exit 1
fi

if ! git -C "$GIT_ROOT" remote get-url "$REMOTE" >/dev/null 2>&1; then
  echo "[viewer-deploy] remote '$REMOTE' not found in $GIT_ROOT." >&2
  exit 1
fi

REL_VIEWER="$(python3 - "$GIT_ROOT" "$VIEWER_DIR" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[2]).resolve().relative_to(Path(sys.argv[1]).resolve()))
PY
)"

add_if_exists() {
  local path="$1"
  if [ -e "$GIT_ROOT/$path" ]; then
    git -C "$GIT_ROOT" add -- "$path"
  fi
}

add_if_exists "$REL_VIEWER/splats"
add_if_exists "$REL_VIEWER/panos"
add_if_exists "$REL_VIEWER/index.html"
add_if_exists "$REL_VIEWER/README.md"
add_if_exists "$REL_VIEWER/README_DEPLOY.md"

if git -C "$GIT_ROOT" diff --cached --quiet; then
  echo "[viewer-deploy] no staged viewer changes to deploy."
  exit 0
fi

COMMIT_MSG="${GH_PAGES_COMMIT_MSG:-Package research splats for viewer}"
git -C "$GIT_ROOT" commit -m "$COMMIT_MSG"
git -C "$GIT_ROOT" push "$REMOTE" "$BRANCH"
echo "[viewer-deploy] pushed $REMOTE/$BRANCH from $GIT_ROOT"
