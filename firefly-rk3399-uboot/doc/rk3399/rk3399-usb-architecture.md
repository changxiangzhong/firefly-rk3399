# RK3399 USB Architecture

## Hardware Stack

Each USB port on RK3399 is served by three layers inside the SoC:

```
                       ┌────────────────────────────┐
                       │       RK3399 silicon        │
                       │                             │
  USB connector  ◄─────┤  PHY   ◄──  Controller  ◄── CPU
   (external)          │                             │
                       └────────────────────────────┘
```

| Layer | Role | Example |
|-------|------|---------|
| **PHY** | Electrical layer — converts digital to USB signals, handles plug/unplug detection | `u2phy0`, `tcphy0` |
| **Controller** | Protocol layer — speaks USB, manages packets, transfers, enumeration | `usbdrd_dwc3_0`, `usb_host0_ehci` |
| **PHY ↔ Controller link** | The `phys` property in DTS | `phys = <&u2phy0_otg>` |

## PHY Blocks

RK3399 has four PHY hardware blocks. Each has **multiple sub-ports** that can serve different controllers independently.

### USB 2.0 PHYs

```
u2phy0 @ 0xe450    u2phy1 @ 0xe460
───────────────    ───────────────
  host-port          host-port      → for EHCI/OHCI host controllers
  otg-port           otg-port       → for DWC3 DRD controllers
```

- `compatible = "rockchip,rk3399-usb2phy"`
- Each is a single hardware block that can drive **two physical USB ports simultaneously** — one via its `host` sub-port, one via its `otg` sub-port.
- Needs a reference clock from the CRU (`SCLK_USB2PHY0_REF` / `SCLK_USB2PHY1_REF`).
- Outputs a 480 MHz clock for high-speed timing.

### Type-C / USB 3.0 PHYs

```
tcphy0 @ 0xff7c0000    tcphy1 @ 0xff800000
──────────────────    ──────────────────
  dp-port                dp-port        → for DisplayPort alt-mode
  usb3-port              usb3-port      → for USB 3.0 SuperSpeed (5 Gbps)
```

- `compatible = "rockchip,rk3399-typec-phy"`
- Handles USB 3.0 SuperSpeed lanes (TX+/TX-, RX+/RX-).
- Also drives DisplayPort alternate mode over the same Type-C connector.
- Uses a 50 MHz core clock from the CRU.

## USB Controllers

RK3399 has three types of USB controllers inside the SoC:

### 1. EHCI (Enhanced Host Controller Interface)

- USB 2.0 host only, high-speed (480 Mbps).
- `usb_host0_ehci @ 0xfe380000` — uses `&u2phy0_host`
- `usb_host1_ehci @ 0xfe3c0000` — uses `&u2phy1_host`
- `compatible = "generic-ehci"`

### 2. OHCI (Open Host Controller Interface)

- USB 1.1 host only, full/low-speed (12 / 1.5 Mbps).
- `usb_host0_ohci @ 0xfe3a0000` — uses `&u2phy0_host`
- `usb_host1_ohci @ 0xfe3e0000` — uses `&u2phy1_host`
- `compatible = "generic-ohci"`

EHCI and OHCI form **companion pairs** — one physical USB 2.0 port is wired to both. The hardware auto-routes device traffic to EHCI (if high-speed) or OHCI (if full/low-speed).

```
USB 2.0 port ──► u2phyX_host ──┬── usb_hostX_ehci  (480 Mbps devices)
                               └── usb_hostX_ohci  (12 / 1.5 Mbps devices)
```

### 3. DWC3 (DesignWare USB 3.0 Controller)

- USB 3.0, can be host or device (DRD = Dual Role Device).
- `usbdrd_dwc3_0 @ 0xfe800000` — uses `&u2phy0_otg` (USB 2.0) + `&tcphy0_usb3` (USB 3.0)
- `usbdrd_dwc3_1 @ 0xfe900000` — uses `&u2phy1_otg` (USB 2.0) + `&tcphy1_usb3` (USB 3.0)
- `compatible = "snps,dwc3"`
- The `dr_mode` property controls role:
  - `"host"` — host only
  - `"peripheral"` — device only
  - `"otg"` — can switch (depends on ID pin or Type-C negotiation)

Each DWC3 sits inside a **DRD wrapper** node that provides SoC-level integration (clocks, resets, bus interface):

```
usbdrd3_0: usb@fe800000 {           ← DRD wrapper (RK3399 glue)
    compatible = "rockchip,rk3399-dwc3";
    clocks = <...>;
    resets = <...>;

    usbdrd_dwc3_0: usb@fe800000 {   ← DWC3 core (Synopsys IP)
        compatible = "snps,dwc3";
        phys = <&u2phy0_otg>, <&tcphy0_usb3>;
        dr_mode = "otg";
    };
};
```

The wrapper is compatible with `"rockchip,rk3399-dwc3"` (matched by U-Boot's `dwc3-generic.c`). The inner node is generic `"snps,dwc3"` — the same IP used across many SoC vendors.

## Firefly-RK3399 Board Physical Port Mapping

```
Board ports                   PHY              Controller(s)
────────────────────────────────────────────────────────────────────
1x USB Type-C        ── u2phy0_otg    ── usbdrd_dwc3_0  (DRD)
                     ── tcphy0_usb3

2x USB 2.0 Type-A    ── u2phy0_host   ── usb_host0_ehci + usb_host0_ohci
   (upper stack)

1x USB 3.0 Type-A    ── u2phy1_otg    ── usbdrd_dwc3_1  (DRD, host only)
                     ── tcphy1_usb3

2x USB 2.0 Type-A    ── u2phy1_host   ── usb_host1_ehci + usb_host1_ohci
   (lower stack)
```

The Type-C port additionally uses an external **FUSB302** chip (I2C4, address 0x22) for plug orientation detection and USB Power Delivery negotiation.

## Tracing Connections in DTS

The linkage between a controller and its PHY is through the `phys` property:

```dts
/* rk3399-base.dtsi */
usbdrd_dwc3_0: usb@fe800000 {
    phys = <&u2phy0_otg>, <&tcphy0_usb3>;
    phy-names = "usb2-phy", "usb3-phy";
};
```

- `&u2phy0_otg` references the `otg-port` sub-node of `u2phy0` (defined at `rk3399-base.dtsi:1637`)
- `&tcphy0_usb3` references the `usb3-port` sub-node of `tcphy0` (defined at `rk3399-base.dtsi:1716`)

The board DTS (`rk3399-firefly.dts`) then enables nodes and sets board-specific properties:

```dts
&u2phy0 {
    status = "okay";           /* enable the PHY */

    u2phy0_otg: otg-port {
        status = "okay";       /* enable the OTG sub-port */
    };

    u2phy0_host: host-port {
        phy-supply = <&vcc5v0_host>;  /* board-level power supply */
        status = "okay";
    };
};
```

## Key DTS Files

| File | Contents |
|------|----------|
| `rk3399-base.dtsi` | SoC-level definitions — all controllers, PHYs, their registers and clocks (all `status = "disabled"` by default) |
| `rk3399.dtsi` | OPP tables, includes `rk3399-base.dtsi` |
| `rk3399-firefly.dts` | Board-level — sets `status = "okay"`, adds board-specific regulators, connectors, pinmux |
