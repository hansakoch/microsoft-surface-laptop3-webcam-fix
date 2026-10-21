# Microsoft Surface Laptop 3 Webcam Fix

Fixes the front webcam on the **Microsoft Surface Laptop 3** (and other
Microsoft Surface devices using the same Intel IPU3 front-camera module:
**OV9734 RGB + OV7251 IR**) on Linux / Arch-based distros (Omarchy, EndeavourOS,
Manjaro, etc.).

## Install

```sh
git clone https://github.com/hansakoch/microsoft-surface-laptop3-webcam-fix.git
cd microsoft-surface-laptop3-webcam-fix
./install.sh
sudo reboot
```

After reboot, open https://webcamtests.com in Chromium and the camera works.

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
cam --list                        # should list: 1: 'ov9734'
dmesg | grep -E "OVTI9734|Connected 2 cameras"
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
4. Enables Chromium's pipewire camera backend
   (`--enable-features=WebRtcPipeWireCamera` in `~/.config/chromium-flags.conf`).

## Troubleshooting

- **Black / dark image** → turn on room lights; the sensor is fine.
- **Browser still says no camera** → close `cam`/`qcam` first (one consumer at
  a time), then check `~/.config/chromium-flags.conf` has
  `WebRtcPipeWireCamera`.
- **IR camera (OV7251) not listed** → kernel-probed but not a libcamera camera;
  not needed for normal webcam use.

## Notes

- Patches are for kernel `7.2.11-arch1-1`, libcamera `0.7.2`, pipewire `1.6.9`.
  Small and apply to nearby versions.
- Kernel patches are GPL-2.0, libcamera/pipewire patches follow their upstream
  licenses.