# Surface Laptop 3 Webcam Fix

Fixes the **Surface Laptop 3 (model 1769)** front camera (OV9734 RGB, Intel
IPU3 pipeline) on Linux / Arch-based distros (Omarchy, etc.).

## Install

```sh
git clone https://github.com/hansakoch/surface-laptop3-webcam-fix.git
cd surface-laptop3-webcam-fix
./install.sh
sudo reboot
```

After reboot, open https://webcamtests.com in Chromium and the camera works.

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