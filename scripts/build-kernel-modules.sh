#!/bin/bash
# Build the two patched kernel modules for the current running kernel.
# Usage: sudo ./build-kernel-modules.sh
# Requires: linux-headers matching `uname -r`, gcc, make, zstd
set -e
KVER=$(uname -r)
KDIR=/usr/lib/modules/$KVER/build
[ -d "$KDIR" ] || { echo "Kernel headers not installed for $KVER"; echo "Install: sudo pacman -S linux-headers"; exit 1; }
HERE="$(cd "$(dirname "$0")/.." && pwd)"
SRC=$(mktemp -d)
trap 'rm -rf "$SRC"' EXIT

echo "== Fetching mainline sources =="
curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/pci/intel/ipu-bridge.c -o "$SRC/ipu-bridge.c"
curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/i2c/ov9734.c -o "$SRC/ov9734.c"

echo "== Applying patches =="
cd "$SRC"
patch -p0 < "$HERE/patches/kernel/0001-ipu-bridge-add-ovti9734.patch"
patch -p0 < "$HERE/patches/kernel/0002-ov9734-probe-fixes.patch"

echo "== Building ipu-bridge =="
mkdir -p b/ipu-bridge && cp ipu-bridge.c b/ipu-bridge/
echo "obj-m := ipu-bridge.o" > b/ipu-bridge/Kbuild
make -C "$KDIR" M="$SRC/b/ipu-bridge" modules

echo "== Building ov9734 =="
mkdir -p b/ov9734 && cp ov9734.c b/ov9734/
echo "obj-m := ov9734.o" > b/ov9734/Kbuild
make -C "$KDIR" M="$SRC/b/ov9734" modules

echo "== Installing =="
sudo zstd -f -q -19 b/ipu-bridge/ipu-bridge.ko \
  -o /lib/modules/$KVER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst
sudo zstd -f -q -19 b/ov9734/ov9734.ko \
  -o /lib/modules/$KVER/kernel/drivers/media/i2c/ov9734.ko.zst
sudo depmod -a
echo "Done. Reboot for the changes to take effect."
