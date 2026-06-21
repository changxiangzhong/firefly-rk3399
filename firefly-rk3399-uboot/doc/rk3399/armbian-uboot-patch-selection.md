# U-Boot Patch Selection for firefly-rk3399

## Summary

When building for `firefly-rk3399`, **all 42 `.patch` files** in the root of `patch/u-boot/u-boot-rockchip64/` are applied. Board-specific subdirectories (e.g., `board_nanopi-r4s/`) are **not** applied because there is no `board_firefly-rk3399/` subdirectory.

## Directory Structure of `patch/u-boot/u-boot-rockchip64/`

### Root-level `.patch` files (applied to all rockchip64 boards)

42 files including:
- `add-board-*.patch` (clockworkpi-a06, fine3399, helios64, nanopi-m4v2, orangepi-4, orangepi-r1-plus-*, rock-pi-s, tinker-edge-r, xiaobao-nas-dts)
- `board-pinebook-pro-*.patch` (5 files)
- `board-rock-pi-4-enable-spi-flash.patch`
- `board-rockpro64-*.patch` (2 files)
- `general-*.patch` (xtx-spi-nor, dwc-otg-usb-fix, compressed-btrfs, semantic-versioning, zstd-max-window, set-eth1addr, recovery-button, rmii-integrated-phy)
- `rk3399-*.patch` (8 files)
- `u-boot-rk-rk3399-usb-start-firefly-rk3399.patch` (firefly-specific)
- `u-boot-rk-rk3399-usb-start-generic.patch`
- `u-boot-rk-rk3399-usb-start-nanopc-t4.patch`
- Others: `enable-DT-overlays-support.patch`, `add-trust-ini.patch`, `sdmmc-force-fifo-mode-in-spl.patch`, etc.

### Board-specific subdirectories (NOT applied for firefly-rk3399)

| Directory | Applied when |
|---|---|
| `board_nanopi-r4s/` | `BOARD=nanopi-r4s` |
| `board_station-m1/` | `BOARD=station-m1` |
| `board_station-p1/` | `BOARD=station-p1` |
| `board_mkspi/` | `BOARD=mkspi` |
| `board_rockpi-s/` | `BOARD=rockpi-s` |
| `board_rk3318-box/` | `BOARD=rk3318-box` |

## How BOOTPATCHDIR is Mapped

### Step 1: Board config → Family name

`config/boards/firefly-rk3399.csc`:
```bash
BOARDFAMILY="rockchip64"
```

### Step 2: Family name → Family config

`lib/functions/configuration/main-config.sh:141,556`:
```bash
LINUXFAMILY="${BOARDFAMILY}"                           # = "rockchip64"
# sources: config/sources/families/${LINUXFAMILY}.conf  # = rockchip64.conf
```

### Step 3: Family config → Common include

`config/sources/families/rockchip64.conf:10`:
```bash
source "${BASH_SOURCE%/*}/include/rockchip64_common.inc"
```

### Step 4: Common include → BOOTPATCHDIR

`config/sources/families/include/rockchip64_common.inc:20`:
```bash
BOOTPATCHDIR="${BOOTPATCHDIR:-"u-boot-rockchip64"}"
```

### Step 5: BOOTPATCHDIR → Python script

`lib/functions/compilation/uboot-patching.sh:24`:
```bash
"PATCH_DIRS_TO_APPLY=${BOOTPATCHDIR}"
```

### Step 6: Python → Filesystem path

`lib/tools/patching.py:85`:
```python
f"{SRC}/patch/{PATCH_TYPE}/{patch_dir_to_apply}"
# resolves to: $SRC/patch/u-boot/u-boot-rockchip64/
```

## Patch Selection Algorithm

Defined in `lib/tools/patching.py:87-99` and `lib/tools/common/patching_utils.py:100-111`.

### Sub-directory candidates

Built from `BOARD` and `TARGET` (for firefly-rk3399, TARGET is empty):

```python
CONST_PATCH_SUB_DIRS = [
    PatchSubDir(f"target_{TARGET}", "target"),    # "target_" (does not exist)
    PatchSubDir(f"board_{BOARD}", "board"),        # "board_firefly-rk3399" (does not exist)
    PatchSubDir("", "common"),                     # "" (root — exists)
]
```

### Root × Sub cross product

Each root directory is crossed with each sub directory:

1. `userpatches/u-boot/u-boot-rockchip64/target_/` — N/A
2. `userpatches/u-boot/u-boot-rockchip64/board_firefly-rk3399/` — N/A
3. `userpatches/u-boot/u-boot-rockchip64/` — user overrides (N/A)
4. `patch/u-boot/u-boot-rockchip64/target_/` — N/A
5. `patch/u-boot/u-boot-rockchip64/board_firefly-rk3399/` — N/A
6. **`patch/u-boot/u-boot-rockchip64/`** — **APPLIED**

### File collection

`patching_utils.py:100-111` — scans **non-recursively** for `*.patch` files:

```python
for file in os.listdir(self.full_dir):
    if file.endswith(".patch"):
        self.patch_files.append(...)
```

### Deduplication & ordering

`patching.py:163-173` — patches deduplicated by filename (later directory wins), then sorted alphabetically and applied in order.

## Key Files

| File | Role |
|---|---|
| `config/boards/firefly-rk3399.csc` | Sets `BOARDFAMILY="rockchip64"` |
| `config/sources/families/rockchip64.conf` | Sources `rockchip64_common.inc` |
| `config/sources/families/include/rockchip64_common.inc` | Sets `BOOTPATCHDIR` |
| `lib/functions/configuration/main-config.sh` | Sources family config by name |
| `lib/functions/compilation/uboot-patching.sh` | Passes `BOOTPATCHDIR` to Python |
| `lib/tools/patching.py` | Constructs filesystem paths, builds patch list |
| `lib/tools/common/patching_utils.py` | `PatchDir`, `PatchRootDir`, file scanning |
