# Device Tree Q&A

## Q1: SDHCI is a controller chip I guess. It's connected to a emmc chip on this board, is that so?

Yes, exactly. SDHCI is the controller IP block inside the RK3399 SoC, and on this board it's hard-wired via the `emmc_phy` to the onboard eMMC flash chip. The PHY handles the physical signaling between the SoC and the eMMC IC.

---

## Q2: Explain to me the syntax `mmc@fe330000`. What is `mmc`?

In `mmc@fe330000`:

- **`mmc`** is the **node name** — a generic class name describing what kind of device this is. It follows the Device Tree spec's recommended generic names (from section 2.2.2 of the spec). Common ones: `mmc`, `serial`, `i2c`, `spi`, `ethernet`, `memory`, `cpu`, `pci`. The name carries no functional meaning — it's just human-readable documentation and helps generic code find "all mmc nodes" by name if needed.

- **`@fe330000`** is the **unit address** — must match the first entry in the node's `reg` property (`reg = <0x0 0xfe330000 ...>`). It disambiguates nodes of the same type. Since the RK3399 has three MMC controllers, you get:
  ```
  mmc@fe310000   ← sdio0 (WiFi)
  mmc@fe320000   ← sdmmc  (SD card)
  mmc@fe330000   ← sdhci  (eMMC)
  ```

The label `sdhci:` is separate — it's just a shortcut alias. The label name is arbitrary. They could have called it `emmc:` and it would work identically. The convention on RK3399 is to name labels after the pin-function names from the TRM (`sdhci`, `sdmmc`, `sdio0`), but those are developer-chosen labels, not part of the node name syntax.

---

## Q3: Explain to me this part

```dts
sdhci: mmc@fe330000 {
        compatible = "rockchip,rk3399-sdhci-5.1", "arasan,sdhci-5.1";
        reg = <0x0 0xfe330000 0x0 0x10000>;
        interrupts = <GIC_SPI 11 IRQ_TYPE_LEVEL_HIGH 0>;
        arasan,soc-ctl-syscon = <&grf>;
        assigned-clocks = <&cru SCLK_EMMC>;
        assigned-clock-rates = <200000000>;
        clocks = <&cru SCLK_EMMC>, <&cru ACLK_EMMC>;
        clock-names = "clk_xin", "clk_ahb";
        clock-output-names = "emmc_cardclock";
        #clock-cells = <0>;
        phys = <&emmc_phy>;
        phy-names = "phy_arasan";
        power-domains = <&power RK3399_PD_EMMC>;
        disable-cqe-dcmd;
        status = "disabled";
    };
```

What is `compatible`, `reg` and `phys`?

### `compatible` — Which driver handles this hardware

```
compatible = "rockchip,rk3399-sdhci-5.1", "arasan,sdhci-5.1";
```

Tells U-Boot (and Linux): "this device is an Arasan SDHCI 5.1 controller, with Rockchip-specific integration." The driver matching follows a fallback chain:

1. First, try to find a driver that matches `"rockchip,rk3399-sdhci-5.1"` — this is the Rockchip-specific wrapper driver that handles RK3399 quirks (eMMC PHY power cycling, HS400 enhanced strobe, etc.)
2. If not found, fall back to a driver matching `"arasan,sdhci-5.1"` — the generic Arasan SDHCI driver

In U-Boot, `drivers/mmc/rockchip_sdhci.c` registers itself with:
```c
{ .compatible = "arasan,sdhci-5.1" }
```
That's how the driver knows it should take control of this node at probe time. When you `make menuconfig` and see `CONFIG_MMC_SDHCI_ROCKCHIP`, that's what compiles this driver in.

### `reg` — Where the hardware lives in memory

```
reg = <0x0 0xfe330000 0x0 0x10000>;
```

This is the memory-mapped I/O region. Think of it as the device's "mailbox": the CPU talks to the controller by reading/writing to address `fe330000` through `fe33ffff` (that's `0x10000` = 64KB of registers).

The `<0x0 0xfe330000 0x0 0x10000>` syntax is pairs of `(address size)`:
- Address on 64-bit platforms: `<high32 low32 size_high32 size_low32>`
- For `fe330000` (a 32-bit value in 64-bit form): `0x0 0xfe330000` — address `0x0_00000000_fe330000`
- Size: `0x0 0x10000` — 64KB

This is why the node is named `mmc@fe330000` — the `@fe330000` must match the first address in `reg`.

### `phys` — The electrical PHY

```
phys = <&emmc_phy>;
phy-names = "phy_arasan";
```

A **PHY** (physical layer) handles the actual electrical signals — voltage levels, drive strength, impedance matching, clock signal conditioning on the physical wires between the SoC pad and the eMMC chip.

`&emmc_phy` is a phandle reference to another node (the `emmc_phy: phy@f780` node) that controls these electrical parameters. The driver calls generic PHY API functions to:
1. Power on the PHY before talking to eMMC
2. Configure drive impedance (set to 50 ohms in the PHY node)
3. Cycle power when switching between HS200/HS400 speed modes

Without the PHY, the controller's digital signals can't reliably reach the eMMC chip. The `phy-names` string `"phy_arasan"` is just a lookup key so the driver can fetch the right PHY by name (some devices have multiple PHYs, e.g., one for TX and one for RX).
