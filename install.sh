#!/usr/bin/env bash
# Surface Laptop 3 (1769) webcam + touchscreen fix — one-shot installer.
# Run as your normal user (sudo is used for privileged steps), then reboot.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
KVER="$(uname -r)"

say() { printf '\n\033[1;32m== %s ==\033[0m\n' "$*"; }

# ---------------------------------------------------------------------------
# 1. Dependencies
# ---------------------------------------------------------------------------
say "Installing dependencies"
sudo pacman -S --needed --noconfirm \
    base-devel git curl meson ninja zstd \
    linux-headers linux-surface linux-surface-headers iptsd \
    libcamera pipewire pipewire-libcamera \
    v4l2loopback-dkms gst-plugins-good

# ---------------------------------------------------------------------------
# 2. Kernel modules (ipu-bridge + ov9734) — for the running kernel AND
#    linux-surface (touchscreen needs surface; the camera needs both)
# ---------------------------------------------------------------------------
say "Building kernel modules"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/pci/intel/ipu-bridge.c -o "$WORK/ipu-bridge.c"
curl -sfL https://raw.githubusercontent.com/torvalds/linux/master/drivers/media/i2c/ov9734.c -o "$WORK/ov9734.c"

cd "$WORK"
patch -p0 < "$HERE/patches/kernel/0001-ipu-bridge-add-ovti9734.patch"
patch -p0 < "$HERE/patches/kernel/0002-ov9734-probe-fixes.patch"

KERNELS=("$KVER")
[ -d "/lib/modules/$KVER-surface" ] && KERNELS+=("$KVER-surface")

for KVER in "${KERNELS[@]}"; do
    KDIR="/usr/lib/modules/$KVER/build"
    [ -d "$KDIR" ] || { echo "skip $KVER (no headers)"; continue; }
    echo "Building for $KVER"
    for m in ipu-bridge ov9734; do
        rm -rf "b/$m"; mkdir -p "b/$m" && cp "$m.c" "b/$m/"
        echo "obj-m := $m.o" > "b/$m/Kbuild"
        make -C "$KDIR" M="$WORK/b/$m" modules
    done
    sudo zstd -f -q -19 "b/ipu-bridge/ipu-bridge.ko" \
        -o "/lib/modules/$KVER/kernel/drivers/media/pci/intel/ipu-bridge.ko.zst"
    sudo zstd -f -q -19 "b/ov9734/ov9734.ko" \
        -o "/lib/modules/$KVER/kernel/drivers/media/i2c/ov9734.ko.zst"
    sudo depmod -a "$KVER"
done

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
# 5. Browsers: enable the pipewire camera backend (Chromium, Chrome, Brave)
# ---------------------------------------------------------------------------
say "Configuring browsers"
for CONF in \
    "$HOME/.config/chromium-flags.conf" \
    "$HOME/.config/chrome-flags.conf" \
    "$HOME/.config/brave-origin-flags.conf"; do
    mkdir -p "$(dirname "$CONF")"
    touch "$CONF"
    if grep -q '^--enable-features=.*WebRtcPipeWireCamera' "$CONF"; then
        :
    elif grep -q '^--enable-features=' "$CONF"; then
        sed -i 's/^--enable-features=\(.*\)$/--enable-features=\1,WebRtcPipeWireCamera/' "$CONF"
    else
        echo '--enable-features=WebRtcPipeWireCamera' >> "$CONF"
    fi
done

systemctl --user restart pipewire
systemctl --user restart wireplumber

# ---------------------------------------------------------------------------
# 6. V4L2 loopback (lets V4L2-only apps like the screen recorder use the camera)
# ---------------------------------------------------------------------------
say "Setting up V4L2 loopback for screen recording"
echo 'options v4l2loopback video_nr=20 card_label="OV9734 Webcam"' \
    | sudo tee /etc/modprobe.d/v4l2loopback.conf
echo 'v4l2loopback' | sudo tee /etc/modules-load.d/v4l2loopback.conf
echo 'SUBSYSTEM=="video4linux", KERNEL=="video20", GROUP="video", MODE="0660"' \
    | sudo tee /etc/udev/rules.d/99-v4l2loopback-webcam.rules
mkdir -p "$HOME/.local/bin" "$HOME/.config/systemd/user"
cp "$HERE/scripts/webcam-loopback" "$HOME/.local/bin/webcam-loopback"
cp "$HERE/scripts/ov9734-loopback-monitor" "$HOME/.local/bin/ov9734-loopback-monitor"
cp "$HERE/systemd/ov9734-loopback.service" "$HOME/.config/systemd/user/ov9734-loopback.service"
chmod +x "$HOME/.local/bin/webcam-loopback" "$HOME/.local/bin/ov9734-loopback-monitor"
systemctl --user daemon-reload
systemctl --user enable --now ov9734-loopback.service

# ---------------------------------------------------------------------------
# 7. Touchscreen: boot the linux-surface kernel (it has the IPTS driver)
# ---------------------------------------------------------------------------
say "Setting linux-surface as the default boot kernel (touchscreen)"
if [ -f /boot/limine.conf ] || [ -f /etc/default/limine ]; then
    if grep -q '^BOOT_ORDER=' /etc/default/limine 2>/dev/null; then
        sudo sed -i 's/^BOOT_ORDER=.*/BOOT_ORDER="linux-surface, linux-t2, linux-omarchy, linux-omarchy-*, *, *fallback, Snapshots"/' /etc/default/limine
    else
        echo 'BOOT_ORDER="linux-surface, linux-t2, linux-omarchy, linux-omarchy-*, *, *fallback, Snapshots"' \
            | sudo tee -a /etc/default/limine
    fi
    sudo limine-update >/dev/null 2>&1 || true
    # With that BOOT_ORDER, linux-surface is the first kernel entry (entry 2,
    # after the OS submenu header). Show the menu for 5s as a fallback.
    sudo sed -i 's/^default_entry:.*/default_entry: 2/' /boot/limine.conf
    sudo sed -i 's/^#timeout:.*/timeout: 5/' /boot/limine.conf
    sudo sync
else
    echo "NOTE: limine not detected — select the linux-surface kernel in your"
    echo "      bootloader menu to enable the touchscreen."
fi

say "Done. REBOOT now"
echo "After reboot:"
echo "  - Touchscreen: works (linux-surface kernel + iptsd)"
echo "  - Webcam:      works in Chromium/Chrome/Brave (cam --list shows 'ov9734')"
echo "  - Recording:   omarchy capture screenrecording-with-webcam -> 'OV9734 Webcam'"