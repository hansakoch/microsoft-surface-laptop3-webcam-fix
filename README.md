# Surface Laptop 3 Webcam Fix (OV9734 RGB camera)

Fix for the **Microsoft Surface Laptop 3 (Model 1769)** front camera on Linux.
This is the OV9734 (720p RGB) sensor connected through the Intel IPU3 imaging
pipeline. It has been broken on Linux for years (in some cases 9+ months of
trying) because **three separate layers** are missing support.

**Status: WORKING** — both cameras probe at the kernel level, the RGB camera is
a fully registered libcamera camera, streams at ~30 fps, and works in browsers
(via pipewire).

---

## What this repo provides

| Item | Layer | Fix |
|------|-------|-----|
| `patches/kernel/0001-ipu-bridge-add-ovti9734.patch` | Kernel (media) | Adds `OVTI9734` to `ipu-bridge`'s supported-sensor table (180 MHz link freq) so the CIO2 graph connects the sensor |
| `patches/kernel/0002-ov9734-probe-fixes.patch` | Kernel (sensor) | ov9734 driver: defer probe until the fwnode endpoint exists, deassert the reset GPIO, enable MCLK + 50 ms settling delay before the chip-ID read |
| `patches/libcamera/libcamera-ov9734.patch` | Userspace | Adds the OV9734 `CameraSensorHelper` (gain model) and tolerates sensors without test-pattern support in the IPU3 pipeline |
| `patches/pipewire/pipewire-libcamera-plugin.patch` | Pipewire SPA | Adds framerate to `EnumFormat` and advertises the *validated* (actually delivered) sizes — required for Chromium to enumerate and stream without crashing |
| `scripts/build-kernel-modules.sh` | Build | Builds + installs both kernel modules for the running kernel |
| `scripts/build-libcamera.sh` | Build | Builds + installs libcamera 0.7.2 into `/usr/local` |
| `scripts/build-pipewire-plugin.sh` | Build | Builds + installs the patched pipewire libcamera SPA plugin |

---

## Quick start (Arch-based, e.g. Omarchy)

```sh
# 1. Kernel modules (rebuilds ipu-bridge + ov9734 for YOUR running kernel)
sudo pacman -S --needed linux-headers base-devel   # if not installed
./scripts/build-kernel-modules.sh
sudo reboot

# 2. After reboot: verify the camera is wired up
dmesg | grep -E "Found supported sensor|Connected"
#   expected: "Found supported sensor OVTI9734:00" and "Connected 2 cameras"

# 3. Userspace (libcamera with the OV9734 sensor helper)
sudo pacman -S --needed meson ninja base-devel git python-jinja python-ply
./scripts/build-libcamera.sh

# 4. Test
cam --list          # should show: 1: 'ov9734'
cam -c 1 --capture=5 --file=/tmp/webcam.bin   # grab frames
```

To take a photo easily:

```sh
# capture the last (auto-exposed) frame of 8 and convert to PNG
cam -c 1 --capture=8 --file=/tmp/f.bin
dd if=/tmp/f.bin of=/tmp/f.raw bs=1351680 skip=7 count=1
ffmpeg -f rawvideo -pixel_format nv12 -video_size 1280x704 -i /tmp/f.raw /tmp/webcam.png
```

### Browser / video-call support (pipewire + Chromium)

```sh
# 1. Build + install the patched pipewire libcamera SPA plugin
./scripts/build-pipewire-plugin.sh

# 2. Enable Chromium's pipewire camera backend. WITHOUT this Chromium only
#    enumerates V4L2 devices (the IPU3 camera exposes none) and reports
#    "Could not find a web camera".
#    NOTE: merge it into any existing --enable-features line as a single
#    comma-separated flag — Chromium only honours the LAST --enable-features,
#    so a second --enable-features=... would override the first.
echo '--enable-features=WebRtcPipeWireCamera' >> ~/.config/chromium-flags.conf

# 3. Verify the camera is a pipewire Video/Source node:
systemctl --user restart pipewire
systemctl --user restart wireplumber
pw-dump | grep libcamera_input
```

Then (re)start Chromium and test at https://webcamtests.com — the camera
should appear and stream at 1280x704@30fps.

**Important:** only one consumer can use the camera at a time. Close `cam` /
`qcam` before using a browser.

---

## Why was it broken? (the full story)

1. **ipu-bridge didn't know the sensor.** The kernel's `ipu-bridge` driver builds
   the sensor→CIO2 media graph only for ACPI HIDs in its `ipu_supported_sensors[]`
   table. `INT347E` (the OV7251 IR camera) was listed; **`OVTI9734` was not** — so
   the RGB sensor got no graph endpoint and its driver died with
   `failed to check HW configuration: -6 (-ENXIO)`.

2. **ov9734 hard-failed instead of waiting.** The ov7251 driver returns
   `-EPROBE_DEFER` when the bridge hasn't created its endpoint yet; ov9734 returned
   a hard error and never retried. On this platform the sensor can probe *before*
   ipu-bridge runs, so it failed every boot.

3. **The sensor was never powered up correctly.** The ACPI power resources
   (`CAMP`) on this device are a no-op. The reset line (GPIO 0x4D, active-low)
   stays asserted and the MCLK (19.2 MHz via `INT3472:00-clk`) is never enabled —
   so the chip-ID read returned `-EREMOTEIO`. The fix deasserts reset and enables
   the clock, plus a 50 ms settling delay (the OV9734 will not ACK I2C
   immediately after MCLK starts). The driver also **pulses the reset line on
   every stream start**, because after several stream start/stop cycles the
   sensor can otherwise get stuck producing black frames (verified: a re-probe
   does not wake it — only a reset low->high transition does).

4. **libcamera had no OV9734 sensor helper.** The IPU3 IPA refuses to initialize
   without a `CameraSensorHelper` for the sensor model. Added one
   (`gain_ = AnalogueGainLinear{ 1, 0, 0, 16 }` — the OV9734's 16-bit gain
   register at 0x350A, 1x = 16). Also fixed the IPU3 pipeline returning a hard
   error when the sensor has no test-pattern support (the start path calls
   `setTestPatternMode(Off)` unconditionally), and an unsigned underflow in the
   IPU3 ImgU size calculation that crashed `std::clamp` for 640x480 streams.

5. **pipewire's libcamera plugin omitted the framerate** from its `EnumFormat`
   params. Chromium's WebRTC pipewire camera factory requires a framerate to
   enumerate the device; gstreamer does not — which is why `gst-launch` worked
   but the browser showed "no web camera". Added `SPA_FORMAT_VIDEO_framerate`
   (30/1) to every format.

6. **Chromium's pipewire camera is off by default.** Chromium only uses its
   pipewire camera backend when `--enable-features=WebRtcPipeWireCamera` is set;
   otherwise it enumerates V4L2 devices only (of which the IPU3 exposes none).
   This must also be merged into any existing `--enable-features` line, because
   Chromium honours only the *last* such flag.

7. **The plugin advertised 1280x720 but delivered 1280x704.** libcamera's IPU3
   pipeline clamps the output height to `alignDown(sensor_height - 1, 32) =
   704` during `validate()`, but the advertised stream formats still said 720.
   Chromium requested the advertised 1280x720, received a 1280x704 frame, and
   its strict buffer-size `CHECK` crashed the video capture service (SIGTRAP).
   The plugin now validates every advertised size against the camera
   configuration, so it reports exactly what it delivers (1280x704, 832x480,
   768x600, ...).

**Verified working:** both sensors probe, `Connected 2 cameras` at boot, the
OV9734 is a registered libcamera camera, streams at ~30 fps (1280x704 NV12),
and the raw sensor data confirms a real image (this user confirmed "it looks
perfect"). The camera also works end-to-end in Chromium (webcamtests.com)
after the pipewire plugin + Chromium flag fixes: 1280x704 @ 30 FPS, ~0.9 MP,
real colour video.

---

## Troubleshooting

- **"failed to check HW configuration: -6"** → the kernel modules aren't patched
  or not loaded; verify with `lsmod | grep ipu_bridge` and the boot log.
- **"failed to find sensor: -121"** → the reset/clock probe fixes aren't applied
  (or the camera module needs the 50 ms settle delay).
- **Camera works in `cam` but not the browser** → (1) confirm
  `--enable-features=WebRtcPipeWireCamera` is set (and merged into any existing
  `--enable-features` line) in `~/.config/chromium-flags.conf`; (2) confirm the
  patched pipewire plugin is installed and the node enumerates a framerate
  (`pw-cli enum-params <node-id> Spa:Enum:ParamId:EnumFormat`); (3) close
  qcam/cam first — only one consumer at a time.
- **Browser finds the camera but shows black / crashes the video service** → the
  pipewire plugin is advertising sizes libcamera doesn't actually deliver.
  Rebuild with `build-pipewire-plugin.sh` and check the advertised sizes are
  64x4-aligned (`pw-cli enum-params ... | grep Rectangle`).
- **Image is very dark** → the AGC boosts exposure/gain; check with the lights
  on. (On one machine the frame only brightened after a clean driver reload:
  `echo i2c-OVTI9734:00 > /sys/bus/i2c/drivers/ov9734/unbind` then
  `echo i2c-OVTI9734:00 > /sys/bus/i2c/drivers/ov9734/bind`.)
- **IR camera (OV7251) not in libcamera** → it probes at kernel level but
  libcamera rejects it (missing mandatory control). Not needed for normal
  webcam use.

---

## Device notes

- Surface Laptop 3, model **1769** (13.5"), ACPI sensor `OVTI9734` (`_DDN` "OV9734-CRDD").
- The same IPU3 pipeline is used by other Surface models — the ipu-bridge entry
  pattern applies to any sensor listed in `ipu_supported_sensors[]`.
- Kernel tested: `7.2.11-arch1-1` (Omarchy / Arch). The patches are small and
  should apply to any recent mainline kernel; the scripts fetch mainline sources.

---

## License / contributions

Patches are minimal and GPL-2.0 (kernel) / BSD-3-Clause (libcamera) as per the
upstream projects. If your Surface model has a different sensor (e.g. OV8865),
the ipu-bridge entry + libcamera helper pattern here is your template. PRs welcome.
