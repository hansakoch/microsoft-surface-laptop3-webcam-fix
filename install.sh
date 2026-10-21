#!/usr/bin/env bash
# Surface Laptop 3 (1769) OV9734 webcam fix — one-shot installer.
# Run as your normal user (sudo is used for privileged steps), then reboot.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KVER="$(uname -r)"
KDIR="/usr/lib/modules/$KVER/build"

say() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Dependencies
# ---------------------------------------------------------------------------
say "Installing dependencies"
sudo pacman -S --needed --noconfirm \
    base-devel git curl meson ninja zstd \
    linux-headers \
    libcamera pipewire pipewire-libcamera

# ---------------------------------------------------------------------------
# 2. Kernel modules (ipu-bridge + ov9734)
# ---------------------------------------------------------------------------
say "Building kernel modules for $KVER"
[ -d "$KDIR" ] || { echo "No kernel headers for $KVER"; exit 1; }
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/pci/intel/ipu-bridge.c -o "$WORK/ipu-bridge.c"
curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/i2c/ov9734.c -o "$WORK/ov9734.c"

cd "$WORK"
patch -p0 < "$HERE/patches/kernel/0001-ipu-bridge-add-ovti9734.patch"
patch -p0 < "$HERE/patches/kernel/0002-ov9734-probe-fixes.patch"

for m in ipu-bridge ov9734; do
    mkdir -p "b/$m" && cp "$m.c" "b/$m/"
    echo "obj-m := $m.o" > "b/$m/Kbuild"
    make -C "$KDIR" M="$WORK/b/$m" modules
done

sudo zstd -f -q -19 "b/ipu-bridge/ipu-bridge.ko" \
    -o "/lib/modules/$KVER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst"
sudo zstd -f -q -19 "b/ov9734/ov9734.ko" \
    -o "/lib/modules/$KVER/kernel/drivers/media/i2c/ov9734.ko.zst"
sudo depmod -a

# ---------------------------------------------------------------------------
# 3. libcamera (OV9734 sensor helper + IPU3 fixes) -> /usr/local
# ---------------------------------------------------------------------------
say "Building libcamera 0.7.2 into /usr/local"
git clone --depth 1 --branch v0.7.2 https://git.libcamera.org/libcamera/libcamera.git "$WORK/libcamera"
cd "$WORK/libcamera"
patch -p1 < "$HERE/patches/libcamera/libcamera-ov9734.patch"

meson setup build-min \
    -Ddocumentation=disabled -Dgstreamer=disabled -Dv4l2=disabled \
    -Dqcam=disabled -Dpycamera=disabled -Dtest=false -Dlc-compliance=disabled \
    -Dandroid=disabled -Dcam=enabled -Dpipelines=ipu3 -Dudev=enabled \
    -Dtracing=disabled -Dlibdw=disabled -Dlibunwind=disabled
ninja -C build-min
sudo ninja -C build-min install
sudo sh -c 'echo /usr/local/lib > /etc/ld.so.conf.d/local.conf'
sudo ldconfig

# ---------------------------------------------------------------------------
# 4. pipewire libcamera SPA plugin (framerate + validated sizes)
# ---------------------------------------------------------------------------
say "Building pipewire libcamera plugin"
git clone --depth 1 --branch 1.6.9 https://gitlab.freedesktop.org/pipewire/pipewire.git "$WORK/pipewire"
cd "$WORK/pipewire"
patch -p1 < "$HERE/patches/pipewire/pipewire-libcamera-plugin.patch"

PKG_CONFIG_PATH=/usr/local/lib/pkgconfig meson setup build-plugin \
    -Dlibcamera=enabled \
    -Dsession-managers= \
    -Dgstreamer=disabled \
    -Ddocs=disabled -Dman=disabled -Dexamples=disabled -Dtests=disabled \
    -Dinstalled_tests=disabled \
    -Dsystemd-user-service=disabled -Dsystemd-system-service=disabled \
    -Dpipewire-alsa=disabled -Dpipewire-jack=disabled -Dpipewire-v4l2=disabled \
    -Dalsa=disabled -Davahi=disabled -Dbluez5=disabled -Dsndfile=disabled \
    -Dopus=disabled -Dffmpeg=disabled -Daudiotestsrc=disabled \
    -Dvideotestsrc=disabled -Djack=disabled -Dvulkan=disabled \
    -Dlibcanberra=disabled -Dv4l2=disabled -Droc=disabled -Dudev=disabled
ninja -C build-plugin spa/plugins/libcamera/libspa-libcamera.so

sudo mkdir -p /usr/lib/spa-0.2/libcamera
sudo cp /usr/lib/spa-0.2/libcamera/libspa-libcamera.so{,.bak} 2>/dev/null || true
sudo cp build-plugin/spa/plugins/libcamera/libspa-libcamera.so \
    /usr/lib/spa-0.2/libcamera/libspa-libcamera.so

# ---------------------------------------------------------------------------
# 5. Chromium: enable its pipewire camera backend
# ---------------------------------------------------------------------------
say "Configuring Chromium"
CONF="$HOME/.config/chromium-flags.conf"
mkdir -p "$(dirname "$CONF")"
touch "$CONF"
if grep -q '^--enable-features=.*WebRtcPipeWireCamera' "$CONF"; then
    :
elif grep -q '^--enable-features=' "$CONF"; then
    sed -i 's/^--enable-features=\(.*\)$/--enable-features=\1,WebRtcPipeWireCamera/' "$CONF"
else
    echo '--enable-features=WebRtcPipeWireCamera' >> "$CONF"
fi

systemctl --user restart pipewire
systemctl --user restart wireplumber

say "Done. REBOOT now, then test at https://webcamtests.com"
echo "Verify after reboot:  cam --list      # should list 'ov9734'"