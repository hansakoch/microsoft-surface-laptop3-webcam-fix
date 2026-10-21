#!/usr/bin/env bash
# Build + install the pipewire libcamera SPA plugin with the Surface Laptop 3
# OV9734 fixes (framerate in EnumFormat + advertise validated sizes).
#
# Why: Chromium's WebRTC pipewire camera requires a framerate in EnumFormat,
# and crashes (SIGTRAP in its video capture service) when libcamera delivers a
# frame smaller than the advertised size (IPU3 clamps 1280x720 -> 1280x704).
#
# Tested with pipewire 1.6.9 and libcamera 0.7.2 installed into /usr/local
# (see build-libcamera.sh). Run this AFTER building/installing libcamera.

set -euo pipefail

PW_VERSION="${PW_VERSION:-1.6.9}"
SRC="${SRC:-/tmp/pipewire-src}"

# pipewire must be installed for its headers/SPA libs
sudo pacman -S --needed --noconfirm meson ninja base-devel pipewire pipewire-libcamera

if [ ! -d "$SRC/.git" ]; then
    rm -rf "$SRC"
    git clone --depth 1 --branch "$PW_VERSION" \
        https://gitlab.freedesktop.org/pipewire/pipewire.git "$SRC"
fi

cd "$SRC"
git apply "$(dirname "$0")/../patches/pipewire/pipewire-libcamera-plugin.patch"

# Minimal build: only the libcamera plugin. libcamera is found via
# /usr/local/lib/pkgconfig (set PKG_CONFIG_PATH so the patched 0.7.2 is used).
# -Dsession-managers= (empty) avoids the wireplumber subproject (which needs
# glib-mkenums and fails on Arch).
PKG_CONFIG_PATH=/usr/local/lib/pkgconfig meson setup build-libcamera-plugin \
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

ninja -C build-libcamera-plugin spa/plugins/libcamera/libspa-libcamera.so

sudo cp /usr/lib/spa-0.2/libcamera/libspa-libcamera.so{,.bak}
sudo cp build-libcamera-plugin/spa/plugins/libcamera/libspa-libcamera.so \
    /usr/lib/spa-0.2/libcamera/libspa-libcamera.so

systemctl --user restart pipewire
systemctl --user restart wireplumber

echo "Done. Verify: pw-dump | grep libcamera_input"