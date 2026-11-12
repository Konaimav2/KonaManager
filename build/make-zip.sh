#!/bin/sh
# Build the flashable KernelSU zip from module/ (module.prop must be at zip root).
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
VER=$(sed -n 's/^version=//p' "$ROOT/module/module.prop" | head -n 1 | tr -d 'v \r')
[ -n "$VER" ] || { echo "cannot read version from module.prop" >&2; exit 1; }
OUT="$ROOT/build/KonaManager-v$VER.zip"
mkdir -p "$ROOT/build"
rm -f "$OUT" "$OUT.sha256"
cd "$ROOT/module"
if command -v zip >/dev/null 2>&1; then
  zip -qr "$OUT" . -x '*.log' -x '__pycache__/*' -x '*.pyc'
else
  python3 - "$OUT" <<'PY'
import os, sys, zipfile
out = sys.argv[1]
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for base, dirs, files in os.walk('.'):
        dirs[:] = [d for d in dirs if d not in ('__pycache__', '.git')]
        for f in files:
            if f.endswith('.log') or f.endswith('.pyc'):
                continue
            p = os.path.normpath(os.path.join(base, f))
            z.write(p, p[2:] if p.startswith('./') else p)
print(out)
PY
fi
sha256sum "$OUT" > "$OUT.sha256"
echo "$OUT"
cat "$OUT.sha256"
