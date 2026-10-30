# surfacepro7-camera-ir

Out-of-tree Linux **7.x** camera and IR driver stack for the
**Microsoft Surface Pro 7** (Intel Ice Lake, **IPU4P** imaging DSP at PCI
`8086:8a19`), with:

| Sensor | Role | ACPI HID | Driver |
|---|---|---|---|
| OV5693 | front camera | `INT33BE` | `ov5693.ko` |
| OV8865 | rear camera | `INT347A` | `ov8865.ko` |
| OV7251 | **IR** camera (Howdy) | `INT347E` | `ov7251.ko` |

plus the Intel IPU4/IPU4P ISP stack and a Surface Pro 7 ACPI/power glue
module.

All code is **C**, **GPL-2.0** compatible, and follows the Linux kernel
coding style. The drivers are **external modules**: the kernel source tree is
never modified.

---

## 1. Contents

Source layout:

```
surfacepro7-camera-ir-src/
├── PKGBUILD                     # package A - basic x86-64 (-O2)
├── PKGBUILD.v4                  # package B - x86-64-v4 (-O3)
├── Makefile                     # two-stage external-module build
├── Kbuild                       # sensor + ACPI module definitions
├── dkms.conf                    # optional DKMS integration
├── surfacepro7-camera-ir.install# pacman scriptlet (depmod)
├── src/
│   ├── intel-ipu4/              # IPU4P ISP stack (kernel-subtree layout)
│   │   ├── drivers/media/pci/intel/…      # core, ISYS, PSYS, MMU, CSI2
│   │   └── include/{media,uapi}/…         # driver public headers
│   ├── ov5693.c                 # front camera, V4L2 I2C subdev
│   ├── ov8865.c                 # rear camera, V4L2 I2C subdev
│   ├── ov7251.c                 # IR camera, V4L2 I2C subdev + illuminator
│   └── surfacepro7_acpi.c       # ACPI power resources / INT3472 glue
├── include/                     # (see src/intel-ipu4/include for the
│                                #  driver's public headers)
└── scripts/
    ├── build-basic.sh           # build + package A
    ├── build-v4.sh              # build + package B
    ├── fetch-firmware.sh        # obtain ipu4p_cpd.bin from Microsoft
    ├── test-capture.sh          # media-ctl pipeline + v4l2-ctl RAW capture
    ├── raw2png.py               # render a RAW10 capture as a PNG
    ├── setup-webcam-bridge.sh   # libcamera -> v4l2loopback virtual webcam
    ├── webcam-bridge.sh         # on/off/status toggle (LED control)
    ├── remove-webcam-bridge.sh  # undo the above
    └── verify.sh                # package / SIMD / layout verification
patches/                         # upstream-style fixes, for kernel builders
├── 0001-platform-x86-int3472-map-INT347E-power-enable-to-vdda.patch
└── 0002-media-ipu4-avoid-WARN-on-unlinked-capture-node.patch
```

Installed modules (9) land in a single directory:

```
/usr/lib/modules/<kernelrelease>/extra/surfacepro7-camera-ir/
├── intel-ipu4.ko              # core: PCI, buttress, CPD, MMU, DMA, fw-com
├── intel-ipu4-isys.ko         # ISYS: CSI2, video nodes, subdevs, TPG
├── intel-ipu4-psys.ko         # PSYS: processing system / resources
├── intel-ipu4-isys-csslib.ko  # ISYS firmware ABI library
├── intel-ipu4-psys-csslib.ko  # PSYS firmware ABI library
├── ov5693.ko  ov8865.ko  ov7251.ko
└── surfacepro7_acpi.ko
```

`depmod -a <kernelrelease>` is re-run by the pacman scriptlet on install,
upgrade and removal.

---

## 2. Requirements

* Surface Pro 7 with the IPU4P ISP (`lspci -nn | grep 8086:8a19`).
* Linux 7.x kernel with a matching `/lib/modules/$(uname -r)/build` tree.
* Toolchain, `make`, `pacman`/`makepkg`, `v4l-utils`, `kmod`.
* **IPU4P CPD firmware** `ipu4p_cpd.bin` in `/usr/lib/firmware/` — required at
  runtime for the ISP to boot. It is Microsoft-signed, is **not** part of
  this package, and is not redistributed here. Without it `intel_ipu4` fails
  to probe (`Direct firmware load for ipu4p_cpd.bin failed with error -2`),
  there is no `/dev/media0`, and all three sensors stay in
  `deferred probe pending: waiting for fwnode graph endpoint`.
  `scripts/fetch-firmware.sh` downloads Microsoft's Surface Pro 7 driver
  package and installs `cpd_component_signed.bin` as `ipu4p_cpd.bin`:

  ```sh
  sudo pacman -S msitools        # provides msiextract
  sudo ./scripts/fetch-firmware.sh
  # or, if you already have the file:
  sudo FIRMWARE=/path/to/cpd_component_signed.bin ./scripts/fetch-firmware.sh
  ```

  The package is ~678 MB and unpacking needs several GB. The script therefore
  **refuses to use a work directory without room** (`MIN_FREE_MB`, default
  4096) and picks the first candidate that has space — `$SUDO_USER`'s
  `~/.cache`, then `/var/tmp`, then `$TMPDIR`, then `/tmp`. On systems where
  `/tmp` is a small RAM-backed tmpfs, extracting into it fails with
  `Error writing to file: No space left on device`; point the script at a real
  filesystem instead:

  ```sh
  sudo ./scripts/fetch-firmware.sh --workdir /home/$USER/sp7-fw
  # or, if you also have little disk, lower the threshold
  sudo MIN_FREE_MB=2048 ./scripts/fetch-firmware.sh --workdir /data/sp7-fw
  ```

  The downloaded `.msi` and the extracted tree are deleted again unless
  `--keep` is given. Run `--help` for all options.
* The kernel's own `ipu-bridge` module (the IPU4 stack imports the
  `INTEL_IPU_BRIDGE` symbol namespace). It is already present in
  linux-surface / CachyOS-Surface kernels.

The build automatically selects the LLVM toolchain when the target kernel was
built with clang (`CONFIG_CC_IS_CLANG=y` in the kernel build tree), and GCC
otherwise. This matters: clang-built kernels record clang-only flags that a
GCC external-module build cannot consume.

---

## 3. Building

Both packages are produced from this **same source folder**; only the
optimisation profile differs.

```sh
cd surfacepro7-camera-ir-src

# package A - basic x86-64
./scripts/build-basic.sh

# package B - x86-64-v4
./scripts/build-v4.sh
```

or directly with `makepkg` (package A):

```sh
export KERNEL_VERSION=$(uname -r)
makepkg -p PKGBUILD    -f --noconfirm --nodeps BUILDDIR=/tmp/makepkg-sp7-a
makepkg -p PKGBUILD.v4 -f --noconfirm --nodeps BUILDDIR=/tmp/makepkg-sp7-b
```

> **Always pass `BUILDDIR`.** `makepkg` defaults `BUILDDIR` to the PKGBUILD
> directory, which makes its own `$srcdir` resolve to **this project's `src/`
> directory** — the driver sources. A `makepkg -C` (or a stray `rm -rf src`)
> would then delete them. The `scripts/build-*.sh` wrappers set `BUILDDIR`
> outside the source tree for exactly this reason.

`--nodeps` is needed on derivative kernels because the metadata dependency is
the `linux` package, which is not installed under names such as
`linux-surface` or `linux-cachyos-surface`, and `makepkg` must not try to
install it as an unprivileged user.

The equivalent manual module build is:

```sh
export KERNEL_VERSION=$(uname -r)
make modules KERNEL_VERSION=$KERNEL_VERSION          # both stages
# equivalently, the sensor/ACPI stage alone:
make -C /lib/modules/$KERNEL_VERSION/build M=$PWD modules
```

### Optimisation profiles

| | Package A (basic) | Package B (v4) |
|---|---|---|
| KCFLAGS | `-O2 -march=x86-64 -mtune=generic -fno-strict-aliasing` | `-O3 -march=x86-64-v4 -mtune=generic -fno-strict-aliasing -mgeneral-regs-only` |
| pkgname | `…-7x` | `…-7x-v4` |
| `pkg arch` | `x86_64` | `x86_64` |

`KCFLAGS` is passed to the external-module build only; the kernel top-level
Makefile is not modified.

**v4 SIMD/FPU safety.** The kernel does not preserve SSE/AVX state across
context switches, so `-march=x86-64-v4` (AVX-512) alone would be unsafe.
Because `KCFLAGS` is appended *after* the kernel's own `-mno-sse/-mno-avx`
flags, `-march=x86-64-v4` would re-enable those register classes, therefore
`-mgeneral-regs-only` is appended as the last flag. `scripts/verify.sh`
disassembles every shipped `.ko` and fails if any `%xmm/%ymm/%zmm` register
or SSE/AVX mnemonic appears. Package B is only a "v4" package in the sense
that the compiler is *allowed* to use the x86-64-v4 feature set for scalar
code; the FP/SIMD register classes stay disabled by design.

---

## 4. Installing

```sh
export KERNEL_VERSION=$(uname -r)

sudo pacman -U ./surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x-1-1-x86_64.pkg.tar.zst
# or, instead of the basic build:
sudo pacman -U ./surfacepro7-camera-ir-ipu4-ov5693-ov8865-ov7251-7x-v4-1-1-x86_64.pkg.tar.zst

sudo depmod -a "$KERNEL_VERSION"     # also done by the package scriptlet
```

The two packages install the same files and therefore **conflict**: install
exactly one. They both `provides=('surfacepro7-camera-ir')`.

> **`depends=('linux')` on derivative kernels.** The metadata dependency is
> literally the Arch `linux` package. On `linux-cachyos-surface`,
> `linux-surface` and friends that package is not installed, so a plain
> `pacman -U` stops with *"unable to satisfy dependency 'linux'"*. Either
> tell pacman to assume it, or point the dependency at your kernel package:
>
> ```sh
> sudo pacman -U --assume-installed linux ./surfacepro7-...-7x-1-1-x86_64.pkg.tar.zst
> # or edit depends=('linux') -> depends=('linux-cachyos-surface') and rebuild
> ```

---

## 5. Loading and testing

### IOMMU: the ISP must be in an identity-mapped IOMMU group

The IPU4 driver writes CPU physical addresses into the IPU MMU page tables.
If the kernel's IOMMU translates DMA for the ISP (the default on Ubuntu,
Fedora and most distribution kernels; check
`cat /sys/bus/pci/devices/0000:00:05.0/iommu_group/type`, anything other than
`identity` is affected), firmware authentication fails:

```
DMAR: [DMA Read NO_PASID] Request device [0000:00:05.0] fault addr ... PTE Read access is not set
intel-ipu4 intel-ipu: CSE boot_load failed
FW authentication failed, retrying...
```

Every open of one of the ~55 video nodes then retries authentication, so
udev's `v4l_id` probes pile up in uninterruptible sleep and only a reboot
clears them.

Fix it without turning the IOMMU off for the whole system: switch only the
ISP's group (on the Surface Pro 7 it contains nothing but `0000:00:05.0`) to
identity mode before the driver binds. The group type cannot change while a
driver is bound, so keep udev from loading the stack and load it with
`scripts/load-ipu4.sh` instead:

```sh
printf 'blacklist intel_ipu4\nblacklist surfacepro7_acpi\n' | \
	sudo tee /etc/modprobe.d/ipu4-no-autoload.conf
# reboot, then (or from a boot-time systemd unit):
sudo ./scripts/load-ipu4.sh
```

`blacklist` only stops alias-based autoloading; `modprobe intel_ipu4` in the
script still works. Booting with `iommu=pt` or `intel_iommu=off` also works but
relaxes DMA protection for every device.

### Loading by hand

```sh
export KERNEL_VERSION=$(uname -r)

# 1. IR illuminator (optional, Howdy): load ov7251 with STROBE frame-PWM on
sudo modprobe ov7251 experimental_strobe_output=1

# 2. ISP stack
sudo modprobe intel_ipu4            # pulls in isys/psys/csslibs via softdep
sudo modprobe ov5693 ov8865
sudo modprobe surfacepro7_acpi

dmesg | grep -Ei 'ipu4|ov5693|ov8865|ov7251|media|v4l2' | tail -n 80

v4l2-ctl --list-devices
media-ctl -p
v4l2-ctl -d /dev/videoX --stream-mmap --stream-count=10
```

`scripts/test-capture.sh` does the whole pipeline for you using the CSI-2 BE
SOC path (the per-CSI-2 direct capture nodes emit MIPI packet dumps, not
raster frames):

```sh
./scripts/test-capture.sh front         # ov5693 2592x1944 -> /var/tmp/front.raw
GAIN=127 ./scripts/test-capture.sh rear # ov8865 3264x2448 -> /var/tmp/rear.raw
./scripts/raw2png.py /var/tmp/front.raw front.png --width 2592 --height 1944
```

Frame 0 after stream start is always a flat pedestal frame, so capture at
least two. Verified on a Surface Pro 7 / 7.2.9-2-cachyos-surface-latest: front
`3 x 2592 x 1944 x 2 = 30233088` bytes, rear
`3 x 3264 x 2448 x 2 = 47941632` bytes, and raising `analogue_gain` from 8 to
127 raised the frame standard deviation from ~3.2 to ~9.3.

`surfacepro7_acpi` publishes a read-only summary:

```
/sys/kernel/surfacepro7_camera_ir/ipu4p           # present|absent
/sys/kernel/surfacepro7_camera_ir/sensors         # HID, ACPI path, _PR0/_PR3/_DSM
/sys/kernel/surfacepro7_camera_ir/int3472         # INT3472 device count
/sys/kernel/surfacepro7_camera_ir/ir_camera       # IR sensor presence
/sys/kernel/surfacepro7_camera_ir/ir_illuminator  # illuminator control path
/sys/kernel/surfacepro7_camera_ir/power
```

Its `power_on_sensors=1` module parameter forces the sensor ACPI devices into
D0, which recovers a stack whose sensor probe failed on a cold power state:

```sh
sudo modprobe -r surfacepro7_acpi
sudo modprobe surfacepro7_acpi power_on_sensors=1
```

---

## 6. IR camera and the illuminator (Howdy)

* `ov7251` exposes a V4L2 video node with `MEDIA_BUS_FMT_Y10_1X10` (GREY/Y10
  family) and the standard `V4L2_CID_EXPOSURE` and `V4L2_CID_ANALOGUE_GAIN`
  controls, which is what Howdy needs.
* The Surface Pro 7 has **no ACPI or GPIO illuminator resource**. The IR LED
  is driven from the OV7251's own **STROBE / frame-PWM output**:
  * `0x3005` bit 3 — STROBE I/O direction (input → output)
  * `0x3b96` bit 7 — frame-PWM enable (lower six bits preserved)
* The illuminator is enabled with the read-only module parameter
  `experimental_strobe_output=1`, is switched on only for the duration of a
  stream, and is switched back off on stream stop / power-off / remove.

**TODO (not faked):** because there is no discrete ACPI/GPIO illuminator
resource, no V4L2 illuminator control is fabricated. The intended interface
is a V4L2 control on the OV7251 subdev (exposure-synchronised, refuse to
enable while not streaming) instead of the current module parameter. Also
open: independent verification of emitted IR power and LED current.

---

## 7. Using the cameras from applications (webcam bridge)

The intel_ipu4 stack does **not** expose a webcam. `v4l2-ctl --list-devices`
lists ~55 nodes and none of them is usable by an ordinary application:

| nodes | what they are |
|---|---|
| `/dev/video0` - `/dev/video41` | CSI-2 **packet-dump** nodes (MIPI headers, not pixels) |
| the `BE SOC capture` nodes | the only raster path, but **raw Bayer / Y10**, and 0 links until `media-ctl` configures the pipeline |
| `/dev/v4l-subdev*` | sensor and CSI-2 subdevices |

So a test tool that opens the first node shows white or garbage (that is MIPI
packet data, not an image), and Webcamoid or a browser lists no camera at all,
because there is no standard capture format and no ISP - no debayer, no auto
exposure, no white balance.

The fix is to put **libcamera** in front - recent versions support the IPU4P
through the `intel-ipu6` Simple-pipeline entry plus SoftISP, so no patching is
needed - and bridge it into a **v4l2loopback** device:

```sh
sudo pacman -S libcamera libcamera-tools gst-plugin-libcamera \
               gst-plugins-good v4l2loopback-dkms v4l2loopback-utils
sudo ./scripts/setup-webcam-bridge.sh        # see --help for --camera/--video-nr
./scripts/webcam-bridge.sh on                # start streaming when you need it
```

`setup-webcam-bridge.sh` deliberately does **not** enable the unit, because
running the bridge keeps the sensor powered and the indicator LED lit; pass
`--autostart` if you want it up at every login.

That pins a v4l2loopback device (`video_nr=60`, label `Surface Camera`) and
installs a `systemd --user` unit running

```
gst-launch-1.0 -e libcamerasrc ! queue ! videoconvert ! videoscale \
    ! video/x-raw,format=YUY2,width=1280,height=720 ! v4l2sink device=/dev/video60
```

Afterwards `/dev/video60` behaves like a normal webcam, so Webcamoid, Cheese,
browsers and GStreamer all work. Pick front vs rear with
`--camera "<name from cam -l>"`. Undo with
`sudo ./scripts/remove-webcam-bridge.sh`.

### The camera indicator LED stays on while the bridge runs

This is expected, and it is a hardware property rather than a driver bug: on
the Surface Pro 7 the camera indicator LED is wired to the sensor's power
rail, so it lights whenever a sensor is powered. A v4l2loopback bridge must
keep the real sensor streaming continuously for the virtual camera to have
frames, so the LED stays on for as long as the bridge is active. Software
cannot stream *and* keep the LED dark - that is the point of the indicator.

Measured while the bridge was running:

```
INT33BE:00 (ov5693) active     INT347A:00 (ov8865) active     IPU4: active
```

and immediately after `systemctl --user stop surface-camera-bridge`:

```
INT33BE:00 suspended           INT347A:00 suspended           IPU4: suspended
```

So control the bridge, not the LED:

```sh
./scripts/webcam-bridge.sh status   # running -> LED on, camera usable
./scripts/webcam-bridge.sh off      # LED off, no camera for apps
./scripts/webcam-bridge.sh on       # camera back
```

**The bridge is not enabled at login by default** - it is installed and left
stopped, so the camera stays off and the LED stays dark until you ask for it
with `scripts/webcam-bridge.sh on`. Add `--autostart` to
`setup-webcam-bridge.sh` if you would rather have it come up with the session.
The alternative design that only
powers the sensor while an application is actually using the camera is to skip
v4l2loopback and use either `libcamerify <app>` or PipeWire/libcamera through
the xdg-desktop-portal; both stream on demand, so the LED only lights during
use, at the cost of per-application setup.

**Do not run `scripts/test-capture.sh` while the bridge is running.** Both need
the single ISP, and libcamera configures the media pipeline itself, so manual
`media-ctl` link setup will fight it.

## 8. Known limitations

1. **Reloading the stack.** The upstream "one load per boot" behaviour is
   caused by the clock leak described in item 3; this tree fixes that, so a
   *failed* probe can be retried without rebooting. Verified: after a fresh
   boot the fixed module bound `0000:00:05.0` and enumerated `/media0` plus
   55 video nodes.
   A **separate**, still-unfixed instance of the same "needs a reboot"
   symptom happens at *stream* time: if a pipeline start fails, ISYS reports
   `failed to stop pipeline after stream-start error: -5` and
   `skipping ISYS device close after firmware lifecycle failure`, after which
   every further stream attempt on that ISP fails with `-ETIMEDOUT` until the
   modules are reloaded or the machine reboots. A full
   `rmmod` -> `modprobe` after *streaming* has not been re-validated.
2. **Firmware.** Without `ipu4p_cpd.bin` the ISP cannot boot and no video
   node will stream. Obtain it with `scripts/fetch-firmware.sh` (see
   section 2).
3. **Re-probe after a failed probe (fixed).** Upstream's `ipu_pci_probe()`
   returned early when `request_cpd_fw()` failed, *after*
   `ipu_buttress_init()` had already registered the sensor and PLL clocks.
   The leaked clock names made every later `modprobe` fail with
   `Clock init failed` / `probe with driver intel-ipu4 failed with error -17`
   (`__clk_core_init()` returns `-EEXIST` on a duplicate clock name), i.e.
   the driver could not be retried without a reboot. This tree fixes the
   unwind (`goto out_ipu_buttress_exit`) and also drops the clkdev lookups
   that `clk_register_clkdev()` leaked even on a clean teardown.
4. **Runtimes grabbing the nodes.** A logged-in desktop session
   (PipeWire/wireplumber) opens every `/dev/video*` node as soon as the
   modules load. This does not stop the modules probing, but it floods the
   log: see item 8.
5. **libcamera/PipeWire integration** is not provided: capture is via
   `v4l2-ctl` / `media-ctl` or `scripts/test-capture.sh`.
6. **OV7251 illuminator** is experimental and only drives the sensor's
   STROBE output; no optical result is claimed. Worth checking once the IR
   sensor probes: the INT3472 driver already maps an ACPI `STROBE` GPIO
   resource to the consumer supply **`ir_flood`** (`INT3472_GPIO_TYPE_STROBE`
   in `discrete.c`), so if the Surface Pro 7 firmware declares one, a real
   GPIO-driven illuminator exists and should be preferred over the
   sensor-STROBE path (and exposed as a V4L2 control).
7. **IR camera (fixed).** `ov7251` used to fail its probe: it asked for the
   `vdda` supply, but the Intel Skylake INT3472 driver names the rail after
   the ACPI GPIO function it gates and hands INT347E:00 its power-enable pin
   as the consumer supply **`avdd`**. Not finding `vdda`, the regulator core
   silently substituted the dummy regulator, the sensor stayed unpowered and
   the first I2C write failed with `-EREMOTEIO` (`reg=103` = `0x0103`).
   Fixed twice over:
   * `src/ov7251.c` now asks for a real `vdda` and, only if the firmware
     provides none (`-ENODEV`), falls back to `avdd`. This works on the
     running distro kernel with no kernel change.
   * `patches/0001-...vdda.patch` adds the upstream-style mapping
     (`INT347E` + `INT3472_GPIO_TYPE_POWER_ENABLE` -> `vdda`) for anyone
     building a kernel from source.
   * The driver also exposed its gain as the non-standard `V4L2_CID_GAIN`.
     libcamera treats `V4L2_CID_ANALOGUE_GAIN` as **mandatory** for a raw
     sensor and dropped the camera entirely with
     `Mandatory V4L2 control 0x009e0903 not available` / `Failed to create
     sensor for 'ov7251 2-0060': -22`, so the IR camera was invisible to
     libcamera (and therefore to the webcam bridge). `src/ov7251.c` now
     registers `V4L2_CID_ANALOGUE_GAIN`, matching ov5693/ov8865 and every
     other mainline raw sensor; userspace uses `analogue_gain=N`.
     `V4L2_CID_CAMERA_ORIENTATION` is still absent, but libcamera only warns
     about that one.
8. **`ipu_isys_get_pixelformat()` spuriously WARNed (fixed).** Capture video
   nodes have no data link until a pipeline is configured, which is a normal
   state, but `ipu-isys-video.c` did `WARN_ON(1)` and returned `NULL`. Any
   client that touches the nodes first - PipeWire at login - tainted the
   kernel with ~180 WARNINGs per boot. The function now returns `NULL`
   quietly. Related: the driver advertises 17 private fourccs
   (`include/uapi/linux/ipu4-v4l2.h`) that the V4L2 core does not know, so
   `v4l_fill_fmtdesc()` warned once per format; `ipu_isys_vidioc_enum_fmt()`
   now fills `f->description` itself so the core leaves it alone. Both fixes
   are also in `patches/0002-...WARN...patch`.
9. **Frame content.** Verified: frames flow with the exact expected byte
   count and `analogue_gain` changes the image (frame std 3.2 -> 9.3). The
   scene present during validation was unlit, so the captured content was
   noise-level rather than a recognisable picture - re-check in a lit room
   with the device open.
10. **Hardware validation.** Capture was validated on a Surface Pro 7 running
    `7.2.9-2-cachyos-surface-latest` with `ipu4p_cpd.bin` from Microsoft's
    driver package. Treat exact results as hardware- and firmware-specific.

---

## 9. Licensing and provenance

All sources are `GPL-2.0-only` / `GPL-2.0` compatible, and upstream copyright
and licence headers are preserved.

* IPU4P ISP stack: derived from Intel's out-of-tree IPU4 driver
  (Clear Linux `linux-iot-lts2018`), the upstream IPU6 driver, and the
  Surface Pro 7 port *ipu4-next* / `ruslanbay/sp7-ipu4-camera`
  (GPL-2.0). SP7-specific DMI MIPI-receiver quirks and the OV7251
  STROBE/frame-PWM illuminator control come from that work.
* `ov5693.c`, `ov8865.c`: Linux kernel `drivers/media/i2c/` (GPL-2.0-only),
  taken at the target kernel release.
* `ov7251.c`: Linux kernel `drivers/media/i2c/ov7251.c` (GPL-2.0) plus the
  OV7251 IR diagnostics and illuminator patches from the SP7 stack.
* `surfacepro7_acpi.c`: original, GPL-2.0-only.

No closed-source firmware is included in either package.
