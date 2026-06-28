#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail(){ echo "FAIL: $*" >&2; exit 1; }
ok(){ echo "OK: $*"; }

[ -s data/sources/pexels_machu_picchu/source_manifest.json ] || fail "missing source_manifest.json"
python3 - <<'PY' || exit 1
import json
m=json.load(open("data/sources/pexels_machu_picchu/source_manifest.json"))
assert m.get("sha256"), "missing sha256"
assert m.get("license_url"), "missing license_url"
assert m.get("source_url") or m.get("local_path"), "missing source URL/path"
assert m.get("legal_review_needed") is True, "legal_review_needed must be true"
PY
ok "source manifest"

N=$(find data/processed/close/images -maxdepth 1 -type f -name '*.jpg' 2>/dev/null | wc -l | tr -d ' ')
[ "$N" -ge 150 ] || fail "need >=150 selected frames, found $N"
[ -s data/processed/close/frame_filter_report.json ] || fail "missing frame_filter_report.json"
[ -s data/processed/close/frame_contact_sheet.jpg ] || fail "missing frame_contact_sheet.jpg"
ok "frames ($N)"

[ -s data/processed/close/pose_report.json ] || fail "missing pose_report.json"
python3 - <<'PY' || exit 1
import json
r=json.load(open("data/processed/close/pose_report.json"))
assert r["registered_frames"] >= 150, r
assert r["registration_ratio"] >= 0.50, r
assert r["sparse_point_count"] > 0, r
PY
ok "SfM thresholds"

[ -s exports/close/close.ply ] || fail "missing exports/close/close.ply"
[ -s site/close.sog ] || fail "missing site/close.sog"
[ -s site/close.json ] || fail "missing site/close.json"
ok "exports and viewer assets"

[ -s eval/close/contact_sheet.png ] || fail "missing eval contact sheet"
[ -s eval/close/viewpoint_manifest.json ] || fail "missing viewpoint manifest"
VIEWS=$(find eval/close/headbox_renders -maxdepth 1 -type f -name '*.png' 2>/dev/null | wc -l | tr -d ' ')
[ "$VIEWS" -ge 8 ] || fail "need headbox/yaw validation renders, found $VIEWS"
ok "validation views ($VIEWS)"

python3 - <<'PY' || exit 1
from pathlib import Path
s=Path("site/index.html").read_text()
assert "id: 'close'" in s, "close scene missing"
assert "file: 'close.sog'" in s, "close scene does not point to close.sog"
assert "settings: 'close.json'" in s, "close scene does not point to close.json"
PY
ok "viewer scene mapping"

python3 - <<'PY' || exit 1
import http.server, socketserver, threading, urllib.request
class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *args): pass
Handler.directory = "site"
with socketserver.TCPServer(("127.0.0.1", 0), lambda *a, **kw: Handler(*a, directory="site", **kw)) as httpd:
    port=httpd.server_address[1]
    t=threading.Thread(target=httpd.serve_forever, daemon=True)
    t.start()
    for path in ["/?scene=close", "/close.sog", "/close.json"]:
        with urllib.request.urlopen(f"http://127.0.0.1:{port}{path}", timeout=5) as r:
            assert r.status == 200, path
    httpd.shutdown()
PY
ok "local static viewer"

[ -s docs/splat_pipeline/final_report.md ] || fail "missing final_report.md"
for needle in "source video" "license" "frame extraction" "registration" "training command" "exported splat" "validation render" "known visual issues" "next recommended"; do
  grep -qi "$needle" docs/splat_pipeline/final_report.md || fail "final_report.md missing: $needle"
done
ok "final report"

echo "PASS validate_close_splat"
