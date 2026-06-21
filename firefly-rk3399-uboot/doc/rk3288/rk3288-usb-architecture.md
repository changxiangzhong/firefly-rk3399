# RK3288 USB Architecture (vs RK3399)

## Why RK3288 is simpler

RK3288 is USB 2.0 only. No Type-C PHY, no USB 3.0 SuperSpeed lanes, no external FUSB302 chip. Everything is plain USB 2.0.

## Hardware Stack (same layers, simpler parts)

```
                       ┌────────────────────────────┐
                       │       RK3288 silicon        │
                       │                             │
  USB connector  ◄─────┤  PHY   ◄──  Controller  ◄── CPU
   (external)          │  (USB 2.0 only)             │
                       └────────────────────────────┘
```

## PHY Block

RK3288 has **one** PHY node containing **three** independent USB 2.0 PHYs. Each PHY serves exactly one controller — no sharing, no sub-ports serving multiple controllers like RK3399's `u2phy0`.

```dts
/* rk3288.dtsi */
usbphy: usbphy {
    compatible = "rockchip,rk3288-usb-phy";  /* single driver, 3 PHYs */

    usbphy0: usb-phy@320 {   /* offset 0x320 → serves usb_otg (DWC2) */
        clocks = <&cru SCLK_OTGPHY0>;
        resets = <&cru SRST_USBOTG_PHY>;
    };

    usbphy1: usb-phy@334 {   /* offset 0x334 → serves usb_host0_ehci/ohci */
        clocks = <&cru SCLK_OTGPHY1>;
        resets = <&cru SRST_USBHOST0_PHY>;
    };

    usbphy2: usb-phy@348 {   /* offset 0x348 → serves usb_host1 (DWC2) */
        clocks = <&cru SCLK_OTGPHY2>;
        resets = <&cru SRST_USBHOST1_PHY>;
    };
};
```

- All three PHYs are registers inside a single `usbphy` hardware block.
- Each has its own clock, reset, and register offset.
- `compatible = "rockchip,rk3288-usb-phy"` — one driver handles all three.

**vs RK3399:** RK3399 has 4 separate PHY blocks (`u2phy0`, `u2phy1`, `tcphy0`, `tcphy1`), each with sub-ports shared by multiple controllers.

## USB Controllers

RK3288 has four USB controllers (all USB 2.0, all inside the SoC):

### 1. usb_otg — DWC2 OTG (can be host OR device)

```dts
usb_otg: usb@ff580000 {
    compatible = "rockchip,rk3288-usb", "rockchip,rk3066-usb", "snps,dwc2";
    dr_mode = "otg";                       /* can switch host/device */
    phys = <&usbphy0>;
    g-np-tx-fifo-size = <16>;             /* gadget FIFO config */
    g-rx-fifo-size = <275>;
    g-tx-fifo-size = <256 128 128 64 64 32>;
};
```

- This is the **only** port that can act as a USB device (for `ums`).
- Uses DWC2 (DesignWare USB 2.0) — predecessor of DWC3.
- The `g-*` properties configure gadget-mode FIFO sizes.

**vs RK3399:** RK3399 uses DWC3 (`snps,dwc3`) with USB 3.0 + USB 2.0 fallback. RK3288 uses DWC2 (`snps,dwc2`), USB 2.0 only, and the PHY link is a single `usbphy0` (no separate USB3 PHY needed).

### 2. usb_host1 — DWC2 Host-only

```dts
usb_host1: usb@ff540000 {
    compatible = "rockchip,rk3288-usb", "rockchip,rk3066-usb", "snps,dwc2";
    dr_mode = "host";                      /* host only, no gadget */
    phys = <&usbphy2>;
};
```

- Another DWC2 controller, but hardwired to host mode.
- On Firefly-RK3288, this drives a USB hub chip (controlled via `usbhub_rst` GPIO pin).

### 3 & 4. usb_host0_ehci + usb_host0_ohci — Companion Pair

```dts
usb_host0_ehci: usb@ff500000 {
    compatible = "generic-ehci";
    phys = <&usbphy1>;
};

usb_host0_ohci: usb@ff520000 {
    compatible = "generic-ohci";           /* NOTE: broken on RK3288 */
    phys = <&usbphy1>;
};
```

- Both share `usbphy1` — the same companion pair pattern as RK3399.
- OHCI is noted as broken on original RK3288 (fixed on RK3288W).
- **Not enabled** on Firefly-RK3288.

### 5. usb_hsic — Internal HSIC

```dts
usb_hsic: usb@ff5c0000 {
    compatible = "generic-ehci";            /* no PHY */
};
```

- HSIC = High-Speed Inter-Chip. For connecting internal modems/WiFi modules.
- No external port, no PHY needed.

## Firefly-RK3288 Board Physical Port Mapping

```
Board ports            PHY           Controller      Mode
──────────────────────────────────────────────────────────
1x Micro-USB OTG  ── usbphy0  ── usb_otg (DWC2)    host/device  ← THIS is for ums
4x USB 2.0 Type-A ── usbphy2  ── usb_host1 (DWC2)  host only    ← through USB hub chip
(usb_host0 not used on this board)
```

The 4 Type-A ports come from a USB hub chip connected to `usb_host1`. The hub's reset is controlled by the `usbhub_rst` GPIO.

## Board DTS (what gets enabled)

```dts
/* rk3288-firefly.dtsi */
&usbphy    { status = "okay"; };    /* enable all 3 PHYs */
&usb_host1 { status = "okay"; };    /* enable DWC2 host port + hub */
&usb_otg   { status = "okay"; };    /* enable OTG port (for ums!) */
```

Only 2 of 4 controllers are used. That's simpler than RK3399 which enables all of them.

## RK3288 vs RK3399 Summary

| Aspect | RK3288 | RK3399 |
|--------|--------|--------|
| USB max speed | USB 2.0 (480 Mbps) | USB 3.0 (5 Gbps) |
| OTG controller | DWC2 (`snps,dwc2`) | DWC3 (`snps,dwc3`) |
| PHY blocks | 1 block, 3 simple USB2 PHYs | 4 blocks (2x USB2 + 2x Type-C) |
| PHY sharing | 1 PHY : 1 controller | 1 PHY serves 2 controllers (host + otg sub-ports) |
| Type-C | No | Yes (FUSB302 external chip) |
| DisplayPort alt-mode | No | Yes (via tcphy dp-port) |
| PHY driver | `rockchip,rk3288-usb-phy` | `rockchip,rk3399-usb2phy` + `rockchip,rk3399-typec-phy` |
| UMS port | USB OTG (micro-USB) | USB DRD (Type-C) |
