#!/bin/bash
# Build libcamera 0.7.2 with the OV9734 sensor helper + IPU3 test-pattern fix.
# Usage: sudo ./build-libcamera.sh
# Installs into /usr/local (takes precedence over the distro libcamera).
set -e
HERE="$(cd "$(dirname "$0")/.." && pwd)"
VER=v0.7.2
SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT

echo "== Cloning libcamera $VER =="
git clone --depth 1 --branch $VER https://git.libcamera.org/libcamera/libcamera.git "$SRC/libcamera"

echo "== Applying patches =="
cd "$SRC/libcamera"
patch -p1 < "$HERE/patches/libcamera/libcamera-ov9734.patch"

echo "== Building (minimal: cam + ipu3 pipeline only) =="
meson setup build-min \
  -Ddocumentation=disabled -Dgstreamer=disabled -Dv4l2=disabled \
  -Dqcam=disabled -Dpycamera=disabled -Dtest=false -Dlc-compliance=disabled \
  -Dandroid=disabled -Dcam=enabled -Dpipelines=ipu3 -Dudev=enabled \
  -Dtracing=disabled -Dlibdw=disabled -Dlibunwind=disabled
ninja -C build-min

echo "== Installing to /usr/local =="
sudo ninja -C build-min install
sudo sh -c 'echo /usr/local/lib > /etc/ld.so.conf.d/local.conf'
sudo ldconfig
echo "Done. Verify with: cam --list"
