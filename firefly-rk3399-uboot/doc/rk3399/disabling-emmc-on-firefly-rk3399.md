# Disabling eMMC on Firefly RK3399

## Background

The onboard eMMC chip on my Firefly RK3399 board is malfunctioning.
When U-Boot tries to probe it, the board hangs.
The goal is to completely disable eMMC so U-Boot ignores it and boots from the SD/TF card instead.

## What is a Device Tree? (for beginners)

A **Device Tree** is a data structure that describes the hardware of a board to the
bootloader and operating system. Instead of hardcoding hardware details in C code,
the device tree provides a human-readable, editable description.

### How it flows

```
.dts / .dtsi source files           (text, written by developers)
        │
        ▼  compiled by dtc
      .dtb blob                       (binary, loaded at boot)
        │
        ▼  parsed by U-Boot / Linux at runtime
    drivers probe devices              (hardware gets initialized)
```

### Key concepts

| Concept | Meaning | Example |
|---------|---------|---------|
| **Node** | A hardware device or subsystem | `mmc@fe330000 { ... };` |
| **Label** | A shortcut name for a node | `sdhci: mmc@fe330000 { ... };` |
| **`&label`** | Reference a node elsewhere (overlay/extend) | `&sdhci { status = "okay"; };` |
| **`status`** | Controls whether the node is active | `"okay"` = enabled, `"disabled"` = ignored |
| **Phandle** | A pointer to another node | `phys = <&emmc_phy>;` |
| **Property** | A key-value pair inside a node | `bus-width = <8>;` |

### Why use device tree instead of defconfig?

The defconfig (`CONFIG_MMC_SDHCI=n`) disables an entire **driver class** — it
would remove support for ALL controllers using that driver.  The device tree
lets you disable **one specific controller instance** while keeping others
active.

On the RK3399, the eMMC and SD card use different controller nodes (`&sdhci` vs
`&sdmmc`). Disabling in the device tree surgically removes only the eMMC while
leaving the SD card fully functional.

## RK3399 MMC Hardware Layout

The RK3399 SoC has three MMC controllers:

| Label | Address | Controller IP | Connected to |
|-------|---------|---------------|--------------|
| `&sdhci` | `fe330000` | Arasan SDHCI 5.1 | **Onboard eMMC chip** (via `&emmc_phy`) |
| `&sdmmc` | `fe320000` | DesignWare MMC | **TF/SD card slot** |
| `&sdio0` | `fe310000` | DesignWare MMC | WiFi / Bluetooth module |

Despite the generic name "sdhci" (which stands for SD Host Controller
Interface), on this board `&sdhci` is hard-wired to the eMMC flash. The PHY
(`&emmc_phy`) handles the physical electrical signaling between the SoC
controller and the eMMC chip.

## File Structure: Two Layers of Device Tree

Firefly RK3399 U-Boot uses device tree files from two directories that get
merged during the build:

### Layer 1: Hardware Description (`dts/upstream/src/arm64/rockchip/`)

These are synced from the Linux kernel. They describe the **pure hardware** —
what components exist on the board, how they're wired, voltages, pin muxing,
etc.

```
rk3399-firefly.dts        ← board-level: enables controllers, sets voltages, pins
  ├── includes rk3399.dtsi          ← SoC-level: CPU cores, IRQ, memory map
  ├── includes rk3399-base.dtsi     ← defines all SoC controller nodes (default disabled)
  └── etc.
```

In `rk3399-base.dtsi`, the eMMC controller node is defined but default-disabled:

```dts
sdhci: mmc@fe330000 {          /* defined, but... */
    status = "disabled";       /* ...not active by default */
};
```

The board file `rk3399-firefly.dts` then enables it because the board has eMMC:

```dts
&sdhci {
    bus-width = <8>;           /* 8 data lines */
    mmc-hs400-1_8v;            /* support HS400 mode */
    non-removable;             /* eMMC is soldered down */
    status = "okay";           /* turn it ON */
};
```

### Layer 2: U-Boot Bootloader Overlay (`arch/arm/dts/`)

These are bootloader-specific additions that are **not** present in the Linux
kernel device tree. They add U-Boot-only metadata:

| Property | Meaning |
|----------|---------|
| `bootph-pre-ram` | Node must be present in TPL / SPL (before DRAM init) |
| `bootph-some-ram` | Node must be present in SPL (after DRAM init) |
| `bootph-all` | Node must be present in all boot phases |
| `u-boot,spl-boot-order` | Which devices SPL tries to boot from, in order |
| `u-boot,spl-fifo-mode` | Workaround: use PIO instead of DMA in SPL (SRAM is too small) |

```
rk3399-firefly-u-boot.dtsi          ← board-specific U-Boot overlay
  ├── includes rk3399-u-boot.dtsi          ← shared across ALL rk3399 boards
  └── includes rk3399-sdram-ddr3-1600.dtsi  ← DDR memory timing config
```

### How they merge at build time

```
┌─────────────────────────────────────────┐
│  rk3399-firefly.dts        (hardware)   │
│    rk3399.dtsi                          │
│    rk3399-base.dtsi     def: disabled ◄─┼──── &sdhci override: enabled
│      &sdhci { ... }                     │
│      &emmc_phy { ... }                  │
│    ...                                  │
│                                         │
│  + rk3399-firefly-u-boot.dtsi (U-Boot)  │
│      rk3399-u-boot.dtsi       shared ◄──┼──── bootph, boot-order, aliases
│        aliases { mmc0 = &sdhci; }       │
│        &sdhci { bootph-pre-ram; }       │
│        &emmc_phy { bootph-pre-ram; }    │
│    ...                                  │
│  = final merged .dtb                    │
└─────────────────────────────────────────┘
```

The build system uses `#include` to pull them together, and later overrides
same-named properties from earlier includes.

## Changes Made

Three files were modified. All are Firefly-board-specific; no shared files were touched.

### 1. `dts/upstream/src/arm64/rockchip/rk3399-firefly.dts`

**Before:**
```dts
&emmc_phy {
    status = "okay";
};

...

&sdhci {
    bus-width = <8>;
    mmc-hs400-1_8v;
    mmc-hs400-enhanced-strobe;
    non-removable;
    status = "okay";
};
```

**After:**
```dts
&emmc_phy {
    status = "disabled";
};

...

&sdhci {
    status = "disabled";
};
```

**Why:**
- `&sdhci` is the eMMC controller. Setting `status = "disabled"` tells U-Boot to skip probing it entirely — the driver's `probe()` function will never be called.
- `&emmc_phy` is the electrical PHY for eMMC signaling. Disabling it prevents the PHY init code from running.
- Removed properties like `bus-width`, `mmc-hs400-*`, `non-removable` — they're meaningless when the node is disabled.
- `&sdmmc` (SD card slot) and `&sdio0` (WiFi) are untouched.

### 2. `arch/arm/dts/rk3399-firefly-u-boot.dtsi`

**Before:**
```dts
#include "rk3399-u-boot.dtsi"
#include "rk3399-sdram-ddr3-1600.dtsi"

&vdd_log {
    regulator-init-microvolt = <950000>;
};
```

**After:**
```dts
#include "rk3399-u-boot.dtsi"
#include "rk3399-sdram-ddr3-1600.dtsi"

&{/aliases} {
    mmc0 = &sdmmc;
};

&{/chosen} {
    u-boot,spl-boot-order = "same-as-spl", &sdmmc;
};

&vdd_log {
    regulator-init-microvolt = <950000>;
};
```

**Why this works without modifying `rk3399-u-boot.dtsi`:**

The shared `rk3399-u-boot.dtsi` (used by all RK3399 boards) sets:
```dts
aliases { mmc0 = &sdhci; };
chosen { u-boot,spl-boot-order = "same-as-spl", &sdhci, &sdmmc; };
```

By placing our overrides **after** the `#include`, our values win. Device tree
syntax (`&{/aliases}` and `&{/chosen}`) references the root-level nodes by
their absolute paths, even though they were already defined in the included
file. Last definition takes precedence.

**What each override does:**

| Override | Before | After | Effect |
|----------|--------|-------|--------|
| `mmc0` alias | `&sdhci` (eMMC) | `&sdmmc` (SD card) | `mmc dev 0` now refers to SD card |
| `spl-boot-order` | eMMC first, then SD | SD card only | SPL won't try to boot from eMMC |

The `bootph-*` properties that `rk3399-u-boot.dtsi` adds to `&sdhci` are
harmless — since the node is disabled in the base DTS, U-Boot never processes them.

### 3. `configs/firefly-rk3399_defconfig`

**Before:**
```
CONFIG_ENV_OFFSET=0x3F8000
CONFIG_ENV_IS_IN_MMC=y
```

**After:**
```
# CONFIG_ENV_OFFSET is not set (eMMC disabled)
CONFIG_ENV_IS_NOWHERE=y
```

**Why:**
- `CONFIG_ENV_IS_IN_MMC=y` told U-Boot to read/write its environment (boot
  args, bootcmd, etc.) from a specific offset on the eMMC chip. Since eMMC is
  now gone, this needs to change.
- `CONFIG_ENV_IS_NOWHERE=y` tells U-Boot to use hard-coded defaults instead of
  persistent storage. No environment block is read or written.
- `CONFIG_ENV_OFFSET` was the sector offset on eMMC where the environment was
  stored — not relevant with `NOWHERE`, so it was commented out.
- None of the MMC/SDHCI driver configs (`CONFIG_MMC_DW`, `CONFIG_MMC_SDHCI`,
  etc.) were removed — they stay compiled in but only probe enabled DT nodes.

## Rebuilding

```bash
make firefly-rk3399_defconfig
make -j$(nproc)
```

This produces:
- `u-boot-rockchip.bin` — combined TPL+SPL+U-Boot proper image
- `u-boot-rockchip.img` when binman generates the FIT image

Flash to SD card and the board will boot without touching the broken eMMC.
