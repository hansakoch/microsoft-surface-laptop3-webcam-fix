# Microsoft Surface Laptop 3 Webcam + Touchscreen Fix

Fixes the front webcam and touchscreen on the **Microsoft Surface Laptop 3**
(and other Microsoft Surface devices using the same Intel IPU3 front-camera
module **OV9734 RGB + OV7251 IR**) on Linux / Arch-based distros (Omarchy,
EndeavourOS, Manjaro, etc.).

## Install

```sh
git clone https://github.com/hansakoch/microsoft-surface-laptop3-webcam-fix.git
cd microsoft-surface-laptop3-webcam-fix
./install.sh
sudo reboot
```

After reboot, the webcam works in Chromium/Chrome/Brave and the touchscreen
works. Test the webcam at https://webcamtests.com.

## Compatible devices

Confirmed working:

- **Microsoft Surface Laptop 3, 13.5"** (model **1769**) — Intel Core

The same hardware (OV9734 + OV7251 front camera on the Intel IPU3 pipeline) is
used by other Microsoft Surface models, so this fix applies to them too:

- Microsoft Surface Laptop 3, 15" (model 1872) — Intel
- Microsoft Surface Laptop 4, 13.5" (Intel models)
- Any laptop whose front camera is `OVTI9734` on IPU3 — check with:
  `sudo dmesg | grep -i ovti9734` or `ls /sys/bus/i2c/devices | grep -i ovti`

The kernel patches are generic (they add `OVTI9734` to the IPU3 bridge table
and fix the ov9734 driver power-on), so they help every OV9734+IPU3 device,
not just the Laptop 3.

## Verify

```sh
cam --list                        # webcam: should list 1: 'ov9734'
dmesg | grep -E "OVTI9734|Connected 2 cameras"
ls /dev/ipts                      # touchscreen: device nodes present
pgrep -x iptsd                    # touchscreen: daemon running
```

## What the installer does

1. Patches **ipu-bridge** to recognize the `OVTI9734` sensor (so the camera
   graph connects) and **ov9734** to power it up correctly (reset GPIO, MCLK,
   50 ms settle, reset pulse per stream).
2. Builds **libcamera 0.7.2** with an OV9734 sensor helper + IPU3 pipeline
   fixes, installed into `/usr/local`.
3. Builds the **pipewire libcamera SPA plugin** with two fixes so Chromium can
   enumerate and stream the camera (framerate in `EnumFormat`, and advertising
   the *actually delivered* sizes — the IPU3 delivers 1280x704, not 1280x720).
4. Enables the pipewire camera backend in **Chromium, Chrome, and Brave**
   (`--enable-features=WebRtcPipeWireCamera` in their flags configs).
5. Installs **linux-surface** + **iptsd** and makes linux-surface the default
   boot kernel — the Surface touchscreen (Intel Precise Touch) only works on
   the surface kernel. Camera patches are built for both kernels.

## Touchscreen

The Surface Laptop 3 touchscreen uses **Intel Precise Touch (IPTS)** — raw
touch data is processed in userspace by `iptsd`. This is not in the mainline
kernel, so the installer installs the **linux-surface** kernel (which has the
`ipts` driver), installs `iptsd` (auto-starts via udev), and sets linux-surface
as the default boot entry. Nothing else to do — after the reboot it just works.

## Screen recording with webcam

The camera is a libcamera/pipewire camera, not a V4L2 device — so tools that
only speak V4L2 (like Omarchy's screen recorder) can't see it directly. The
installer sets up a **v4l2loopback** bridge and a background service so it
**just works, automatically**:

```sh
omarchy capture screenrecording-with-webcam   # pick "OV9734 Webcam"
```

The bridge starts itself when the recorder runs and stops when it's done,
so Google Meet / Chromium still get the camera the rest of the time. The
other two options in the picker (`Intel IPU3 CIO2`, `ipu3-imgu`) are internal
hardware nodes — always pick **OV9734 Webcam**.

For non-Omarchy V4L2 apps there's also a manual bridge:
`webcam-loopback start` / `webcam-loopback stop`.

## Troubleshooting

- **Black / dark image** → turn on room lights; the sensor is fine.
- **Blurry / soft image in Google Meet** → Chromium's PipeWire camera path used
  to lock the OV9734 at **320×240**. The PipeWire plugin now prefers **1280×704**
  and no longer advertises modes below 640×360. After updating the plugin,
  restart PipeWire (`systemctl --user restart pipewire wireplumber`) and fully
  reload Meet (or toggle the camera off/on). Confirm the active size with
  `pw-cli ls Node` → `pw-cli e <id> Format` (should be 1280×704 or ≥640×360).
  In Meet: Settings → Video → send resolution **High definition**.
- **Fans spin / high CPU after install** → an older `ov9734-loopback-monitor`
  used `pgrep -f`, which matches itself and (with Chromium's huge argv) can burn
  ~40% CPU forever. Update `scripts/ov9734-loopback-monitor`, reinstall or copy
  it to `~/.local/bin/`, then `systemctl --user restart ov9734-loopback`.
- **Browser still says no camera** → close `cam`/`qcam` first (one consumer at
  a time), then check the browser's flags config has `WebRtcPipeWireCamera`
  (Chromium: `~/.config/chromium-flags.conf`, Chrome: `~/.config/chrome-flags.conf`,
  Brave: `~/.config/brave-origin-flags.conf`). Fully restart the browser.
- **Touchscreen not working** → confirm you booted linux-surface
  (`uname -r` ends in `-surface`), and `pgrep -x iptsd` is running. If iptsd
  fails with `The screen size is 0!`, the kernel `ipts` touchscreen may still
  work in Hyprland — check `hyprctl devices` for `ipts-…-touchscreen`.
- **IR camera (OV7251) not listed** → kernel-probed but not a libcamera camera;
  not needed for normal webcam use.
- **Screen recorder shows multiple cameras, webcam doesn't record** → pick
  "OV9734 Webcam" (the others are raw IPU3 nodes). If the overlay is still
  black, check `systemctl --user status ov9734-loopback` and that the camera is
  free (close Meet first — one consumer at a time).

## Notes

- Patches are for kernel `7.2.11-arch1-1`, libcamera `0.7.2`, pipewire `1.6.9`.
  Small and apply to nearby versions.
- Kernel patches are GPL-2.0, libcamera/pipewire patches follow their upstream
  licenses.