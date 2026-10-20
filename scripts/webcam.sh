#!/bin/bash
# Webcam photo capture (Surface Laptop 3 OV9734 via IPU3/libcamera)
out="${1:-$HOME/Pictures/webcam-$(date +%Y%m%d-%H%M%S).png}"
mkdir -p "$(dirname "$out")"
tmp=$(mktemp -d)
/usr/local/bin/cam -c 1 --capture=8 --file="$tmp/f.bin" >/dev/null 2>&1
python3 - "$tmp" "$out" <<'PYEOF'
import numpy as np, sys
tmp, out = sys.argv[1], sys.argv[2]
d = np.fromfile(f"{tmp}/f.bin", dtype=np.uint8)
chunk = 1351680
n = len(d)//chunk
if n == 0:
    print("ERROR: no frames captured"); sys.exit(1)
i = n-1  # last frame (AE settled)
open(f"{tmp}/frame.raw","wb").write(d[i*chunk:(i+1)*chunk].tobytes())
print(f"captured {n} frames, using last")
PYEOF
ffmpeg -v error -f rawvideo -pixel_format nv12 -video_size 1280x704 -i "$tmp/frame.raw" -frames:v 1 "$out" -y
rm -rf "$tmp"
echo "Saved: $out"
