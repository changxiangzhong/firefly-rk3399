# Kernel Build Process for `firefly-rk3399` (BRANCH=current, RELEASE=resolute)

## Summary

| Item | Value |
|---|---|
| **Kernel version** | **6.18.34** |
| **Kernel series** | `6.18` |
| **Kernel source repo** | `https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git` |
| **Kernel branch** | `linux-6.18.y` |
| **Git revision** | `18ad16ce4a6b2714583fd1e1044c6ea8e53b3519` |
| **Defconfig** | `linux-rockchip64-current` |
| **Defconfig source** | `config/kernel/linux-rockchip64-current.config` (3474 lines) |
| **Patch directory** | `patch/kernel/archive/rockchip64-6.18/` — 179 `.patch` files + 51 DTS + 123 DT overlays |
| **Board-specific DTS patch** | `patch/kernel/archive/rockchip64-6.18/board-firefly-rk3399-dts.patch` |
| **LINUXFAMILY** | `rockchip64` |
| **ARCH** | `arm64` |
| **Cross-compiler** | `aarch64-linux-gnu-` |
| **Kernel image format** | `Image` |

---

## Step 1: Kernel Version Determination

### Chain of resolution

```
config/boards/firefly-rk3399.csc
  → BOARDFAMILY="rockchip64"
  → KERNEL_TARGET="current,edge"
  → (KERNELPATCHDIR not set by board)

config/sources/families/rockchip64.conf
  → sources include/rockchip64_common.inc

config/sources/families/include/rockchip64_common.inc:28-32
  → KERNEL_MAJOR_MINOR="6.18"              (hardcoded for current)
  → LINUXFAMILY="rockchip64"
  → LINUXCONFIG='linux-rockchip64-current'

config/sources/common.conf:114-128
  → KERNEL_PATCH_ARCHIVE_BASE="rockchip64"  (defaults to LINUXFAMILY)
  → KERNELPATCHDIR="archive/rockchip64-6.18"
```

Since `rockchip64` does not set `KERNELSOURCE`, the mainline kernel is used:

```
config/sources/mainline-kernel.conf.sh:38-41
  → KERNELBRANCH="branch:linux-6.18.y"

lib/functions/configuration/main-config.sh
  → MAINLINE_KERNEL_SOURCE='https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git'
  → KERNELSOURCE="${MAINLINE_KERNEL_SOURCE}"
```

**Result:** `KERNELSOURCE` + `KERNELBRANCH` → git clone of `linux-6.18.y` branch, which resolves to tag `v6.18.34`.

---

## Step 2: Kernel Source Download

Entry: `lib/functions/compilation/kernel.sh:10-104` — `compile_kernel()`.

```
1. kernel_prepare_git()                    [kernel-git.sh:10-25]
   → fetch_from_repo "$KERNELSOURCE" "kernel:6.18" "$KERNELBRANCH" "yes"
   → Clones/pulls from https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux.git
   → Checks out branch:linux-6.18.y at commit 18ad16ce4a6b...

2. Worktree location:
   linux-kernel-worktree/6.18__rockchip64__arm64/
```

If the kernel was previously built and cached as an OCI/ORAS artifact, the source is fetched from the remote cache (fast path). Otherwise, full git clone.

---

## Step 3: Defconfig Selection

Resolved in `lib/functions/compilation/kernel-config.sh`, function `kernel_config_initialize()` (lines 50-88):

1. `LINUXCONFIG` is `"linux-rockchip64-current"` (set in `rockchip64_common.inc:31`)
2. Config search order:
   - `$USERPATCHES_PATH/$LINUXCONFIG.config`
   - `$USERPATCHES_PATH/config/kernel/$LINUXCONFIG.config`
   - **`$SRC/config/kernel/$LINUXCONFIG.config`** ← used
3. Actual file: **`config/kernel/linux-rockchip64-current.config`** (3474 lines, header: `# Armbian defconfig generated with 6.18`)
4. This file is copied to `.config` in the kernel worktree
5. Extension hooks `armbian_kernel_config` + `custom_kernel_config` run
6. `make ARCH=arm64 olddefconfig` finalizes the configuration

---

## Step 4: Patch Selection and Application

Entry: `lib/functions/compilation/kernel-patching.sh:73-90` — `kernel_main_patching()`.

The Python patching engine (`lib/tools/patching.py`) is invoked with:

```
PATCH_DIRS_TO_APPLY="archive/rockchip64-6.18"
BOARD=""          # kernel patching uses no BOARD filter
TARGET=""         # kernel patching uses no TARGET filter
```

### Patch directory resolution

The Python script constructs the filesystem path as:

```python
f"{SRC}/patch/kernel/{PATCH_DIRS_TO_APPLY}"
# → patch/kernel/archive/rockchip64-6.18/
```

And also searches the user patches directory (if `USERPATCHES_PATH` is set):

```python
f"{USERPATCHES_PATH}/kernel/archive/rockchip64-6.18/"
```

### Patch directory contents

**`patch/kernel/archive/rockchip64-6.18/`** (183 entries total):

| Type | Count | Description |
|---|---|---|
| `.patch` files | 179 | Regular kernel patches, applied alphabetically |
| `dt/` directory | 51 files | Bare DTS files copied into `arch/arm64/boot/dts/rockchip/` |
| `overlay/` directory | 124 files | DT overlay files copied into `arch/arm64/boot/dts/rockchip/overlay/` |
| `0000.patching_config.yaml` | 1 | Controls DTS/overlay copying and Makefile auto-patching |

### rk3399-specific patches (23 of 179)

```
board-firefly-rk3399-dts.patch         ← Firefly-specific (HDMI, PCIe, BT, regulators, pinmux)
board-orangepi-rk3399-pcie.patch
rk3399-add-sclk-i2sout-src-clock.patch
rk3399-dmc-polling-rate.patch
rk3399-enable-dwc3-xhci-usb-trb-quirk.patch
rk3399-fix-pci-phy.patch
rk3399-fix-usb-phy.patch
rk3399-rp64-pcie-Reimplement-rockchip-PCIe-bus-scan-delay.patch
rk3399-sd-drive-level-8ma.patch
rk3399-sd-pwr-pinctrl.patch
rk3399-unlock-temperature.patch
rk3399-usbc-* (12 USB-C related patches)
HACK-Ignore-SError-to-enable-rk3399-PCIe-bus-enumera.patch
```

Other SoC patches exist for rk3308 (10), rk3328 (9), rk3528 (15), rk356x (2), rk3576 (9), rk3588 (22), rk35xx (1) — all are applied because kernel patching uses no per-board filtering.

### Patching steps (in order)

1. **Git reset** to `BASE_GIT_REVISION=18ad16ce4a6b...`
2. **EXTRA_PATCH_FILES_FIRST** — legacy driver patches (if any)
3. **Series patches** — `series` file patches (if any)
4. **All `.patch` files** — 179 patches, deduplicated by filename, sorted alphabetically, applied in order
5. **DTS files** — 51 files from `dt/` copied to `arch/arm64/boot/dts/rockchip/`
6. **Overlay files** — 123 overlays from `overlay/` copied to `arch/arm64/boot/dts/rockchip/overlay/`
7. **Makefile auto-patching** — DT Makefile updated to include new DTS/overlay files

### Key DTS file for firefly-rk3399

`board-firefly-rk3399-dts.patch` (320 lines) patches the mainline `rk3399-firefly.dts` to add/enhance:
- HDMI output support
- PCIe bus configuration
- Bluetooth UART
- Voltage regulators (vcc3v3-sd, vcc5v0-host, etc.)
- Pinmux configuration
- LED and GPIO definitions

---

## Step 5: Version Detection

`lib/functions/compilation/utils-compilation.sh:22-31` — `grab_version()`:

```bash
# Reads kernel Makefile:
VERSION=6
PATCHLEVEL=18
SUBLEVEL=34
# → kernel version string: "6.18.34"
```

---

## Step 6: Toolchain Selection

`lib/functions/compilation/kernel-config.sh:77` — `kernel_determine_toolchain()`:

```bash
KERNEL_COMPILER='aarch64-linux-gnu-'
```

Uses the pre-built armbian cross-compilation toolchain for aarch64.

---

## Step 7: Kernel Build

`lib/functions/compilation/kernel.sh:254-267` — `kernel_build()`:

```bash
# Build kernel image and modules:
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j$(nproc) all Image
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- modules_install
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- headers_install
make ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- dtbs_install
```

Key build targets:
- `all` — builds vmlinux, modules, and all configured targets
- `Image` — uncompressed ARM64 kernel image (bootable format, no decompressor needed)
- `modules_install` — installs kernel modules to staging directory
- `headers_install` — installs kernel headers
- `dtbs_install` — builds and installs all device tree blobs

---

## Step 8: Packaging

`lib/functions/compilation/kernel-debs.sh:42-94` — `prepare_kernel_packaging_debs()`:

Creates **4 `.deb` packages**:

| Package | Contents |
|---|---|
| `linux-image-current-rockchip64_6.18.34_arm64.deb` | Kernel image (`vmlinuz-*`), modules, DTBs, boot script |
| `linux-dtb-current-rockchip64_6.18.34_arm64.deb` | Device tree blobs (separate package for flexibility) |
| `linux-headers-current-rockchip64_6.18.34_arm64.deb` | Kernel headers for module compilation |
| `linux-libc-dev-current-rockchip64_6.18.34_arm64.deb` | Compatibility symlinks for libc headers |

---

## Complete Flow Diagram

```
firefly-rk3399.csc (BOARDFAMILY="rockchip64")
│
├─► rockchip64_common.inc
│   ├─ KERNEL_MAJOR_MINOR="6.18"
│   ├─ LINUXFAMILY="rockchip64"
│   ├─ LINUXCONFIG="linux-rockchip64-current"
│   ├─ BOOT_SOC="rk3399"
│   └─ SERIALCON="ttyS2"
│
├─► common.conf
│   ├─ KERNELSOURCE = mainline kernel (linux.git)
│   └─ KERNELPATCHDIR = "archive/rockchip64-6.18"
│
├─► mainline-kernel.conf.sh
│   └─ KERNELBRANCH = "branch:linux-6.18.y"
│
▼
┌─────────────────────────────────────────────────────┐
│ 1. GIT CLONE                                         │
│    linux.git → linux-6.18.y → v6.18.34              │
│    worktree: linux-kernel-worktree/6.18__rockchip64__arm64/ │
├─────────────────────────────────────────────────────┤
│ 2. PATCHING (patching.py)                            │
│    179 patches from patch/kernel/archive/rockchip64-6.18/ │
│    51 DTS files from dt/ subdirectory               │
│    123 DT overlays from overlay/ subdirectory        │
├─────────────────────────────────────────────────────┤
│ 3. CONFIG (kernel-config.sh)                         │
│    → config/kernel/linux-rockchip64-current.config   │
│    → make olddefconfig                               │
│    → grab_version() → "6.18.34"                      │
├─────────────────────────────────────────────────────┤
│ 4. BUILD (kernel-make.sh)                            │
│    make ARCH=arm64 Image modules dtbs                │
│    make modules_install headers_install dtbs_install │
├─────────────────────────────────────────────────────┤
│ 5. PACKAGE (kernel-debs.sh)                          │
│    → linux-image-current-rockchip64                  │
│    → linux-dtb-current-rockchip64                    │
│    → linux-headers-current-rockchip64                │
│    → linux-libc-dev-current-rockchip64               │
└─────────────────────────────────────────────────────┘
```

## Key Source Files

| File | Purpose |
|---|---|
| `config/boards/firefly-rk3399.csc` | Board definition (`BOARDFAMILY`, `BOOTCONFIG`, `KERNEL_TARGET`) |
| `config/sources/families/rockchip64.conf` | Family config entry (sources `rockchip64_common.inc`) |
| `config/sources/families/include/rockchip64_common.inc` | Kernel version, defconfig name, SoC config |
| `config/sources/common.conf` | Kernel patch directory defaults, mainline source mapping |
| `config/sources/mainline-kernel.conf.sh` | Branch name resolution to `linux-6.18.y` |
| `config/kernel/linux-rockchip64-current.config` | Kernel .config (3474 lines) |
| `patch/kernel/archive/rockchip64-6.18/` | 179 patches + DTS + DT overlays |
| `lib/tools/patching.py` | Python patching engine |
| `lib/functions/compilation/kernel.sh` | Top-level `compile_kernel()` |
| `lib/functions/compilation/kernel-git.sh` | Git clone/checkout |
| `lib/functions/compilation/kernel-patching.sh` | Patch orchestration |
| `lib/functions/compilation/kernel-config.sh` | Defconfig + olddefconfig |
| `lib/functions/compilation/kernel-make.sh` | Kernel build execution |
| `lib/functions/compilation/kernel-debs.sh` | .deb packaging |
| `lib/functions/compilation/utils-compilation.sh` | Version extraction from Makefile |
