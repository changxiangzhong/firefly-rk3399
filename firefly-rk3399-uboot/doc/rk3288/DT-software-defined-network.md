# USB Q&A

## Q1: What is a USB hub vs Ethernet hub?

A **hub** is a device that takes **one upstream port** and fans it out to **multiple downstream ports**. It broadcasts incoming traffic to all downstream ports — the devices themselves decide whether to respond.

| | **USB Hub** | **Ethernet Hub** |
|---|---|---|
| Layer | USB protocol | Ethernet (Layer 1) |
| Upstream | 1 port to the host (SoC) | 1 port to the router/switch |
| Downstream | 4+ USB ports | 4+ RJ45 ports |
| Traffic | All downstream ports see all packets; devices filter by address | All ports see all packets; NICs filter by MAC |
| Power | Usually self-powered or bus-powered | Wall-powered |
| Modern replacement | Still common (USB hubs everywhere) | Obsolete — switches replaced them (switches learn MACs, don't broadcast) |

In your RK3288 board:

```
RK3288 SoC
   │
usb_host1 (DWC2) ── 1 upstream USB 2.0
   │
   ▼
USB hub chip (on the board) ── 4 USB Type-A ports (downstream)
```

Without the hub, `usb_host1` gives you just **one** USB port. The hub chip splits it into **four** — that's all it does. The SoC sees all four devices through the same `usb_host1` controller.

---

## Q2: How do we identify a USB host/port? What's the address like?

USB uses a **tree** topology, not a bus like Ethernet.

```
                     Host (SoC)
                        │
                  [Root Hub]          ← built into the host controller
                   /      \
              Device 1    Hub 2       ← each gets a 7-bit address (1-127)
                          /  |  \
                     Dev 3  D4  Hub 5
                                 |
                               Dev 6
```

### Addressing

| Aspect | Ethernet | USB |
|--------|----------|-----|
| Address type | 48-bit MAC (burned into NIC) | 7-bit address (assigned dynamically by host) |
| Who assigns | Manufacturer | Host, at enumeration time |
| Scope | Globally unique | Unique only on this USB tree |
| Range | 00:1A:2B:... | 1–127 (address 0 = unconfigured device) |
| Persists? | Yes, permanent | No, reassigned every power-on / reset |

When you plug in a USB device, it starts at address **0**. The host assigns it a unique address (e.g., 7). Downstream hubs route packets to the correct device by address.

### How hubs route (not broadcast)

Unlike old Ethernet hubs, **USB hubs do NOT broadcast**. A USB hub has a **transaction translator** that forwards packets ONLY to the addressed device:

```
Host sends: "read block 0 from device 7"
    → Root Hub: device 7 is on port 2
        → Hub 2: device 7 is on port 1
            → Device 7 receives the packet
```

Other devices on Hub 2 never see it. This is more like an Ethernet **switch** than a hub — USB "hub" is a misnomer in modern terms.

### How the host identifies which port is which

USB doesn't use port numbers directly in data packets. Instead:

1. The host queries the **hub descriptor** — each hub reports how many ports it has
2. On plug-in, the hub fires an interrupt saying "something changed on port N"
3. The host sends a `port reset` command to that specific port
4. The new device shows up at address 0, gets assigned a real address
5. From then on, the device is referenced by its **address**, not its port

So the addressing is `bus.device` in USB topology (e.g., `1-2.3` = bus 1, hub port 2, device on port 3). But the actual packets only carry the device address — the host remembers the topology.

### The root hub

The host controller itself exposes a **root hub** with its own downstream ports. On RK3288:

- `usb_host1` (DWC2) exposes a root hub with **1 port** → that single port goes to the external USB hub chip, which fans out to 4
- `usb_otg` (DWC2, in host mode) also exposes a root hub with 1 port → goes to the Micro-USB connector

---

## Q3: Why `ums 2 mmc 0`? How to determine the USB controller index?

The index has nothing to do with DTS — it's a U-Boot driver model sequence number.

### How it works

`ums 2 mmc 0` → the `2` goes into `udc_device_get_by_index(2, ...)` (`drivers/usb/gadget/udc/udc-uclass.c:34`):

```c
// Step 1: try to find device with seq == index
uclass_get_device_by_seq(UCLASS_USB_GADGET_GENERIC, index, &dev);

// Step 2: if that fails, just grab the index-th device in the uclass
uclass_get_device(UCLASS_USB_GADGET_GENERIC, index, &dev);
```

The `seq` number is **auto-assigned** by U-Boot at probe time — it's just the order devices are discovered, unless there's an **alias** in the DTS (there isn't one for USB gadget on RK3288).

### How to find the right index

If your U-Boot supports `dm` commands:

```
=> dm tree | grep gadget
```

Otherwise, just trial:

```
=> ums 0 mmc 0
```

If it prints `"No USB device found"`, try 1, then 2. There are typically only 1-2 UDC devices on a board.

For RK3399 mainline U-Boot: the Type-C port (`usbdrd_dwc3_0`) should be index **0** — it's the only controller with `dr_mode = "peripheral"` that binds as a gadget UDC.

---

## Q4: Purpose of Device Tree — the patch panel analogy

Device Tree describes *non-discoverable* hardware to the OS/bootloader. USB devices plugged in are auto-discovered; the SoC's internal USB blocks are not — they need DTS to tell software "there's a DWC2 controller at address 0xff580000, it uses usbphy0, and its reset line is SRST_USBOTG_PHY."

### SoC internal routing is reconfigurable; PCB is fixed

```
   SoC internals (reconfigurable)            PCB (fixed copper)
  ┌─────────────────────────────┐         ┌──────────────────┐
  │                             │         │                  │
  │  usb_otg (DWC2) ──┐        │         │                  │
  │                   │        │         │                  │
  │  usb_host1 ───────┼──┐     │         │                  │
  │                   │  │     │         │                  │
  │  ehci      ───────┼──┼──┐  │         │                  │
  │                   │  │  │  │         │                  │
  │              ┌────┘  │  │  │         │                  │
  │              │  ┌────┘  │  │  pins   │                  │
  │  usbphy0 ◄───┤  │       │  │─────────┤  Micro-USB       │
  │  usbphy1 ◄───┼──┤       │  │─────────┤  (unused)        │
  │  usbphy2 ◄───┼──┼───────┘  │─────────┤  USB hub → 4x A  │
  │              │  │          │         │                  │
  └──────────────┼──┼──────────┘         └──────────────────┘
                 │  │
                 │  └── phys = <&usbphy2>;   ← DT patch cable
                 └───── phys = <&usbphy0>;   ← DT patch cable
```

The DTS `phys` properties are the **patch cables** inside the patch panel. The PCB traces are the **fixed cables** running out to the board connectors. You can't re-solder the PCB, but you can re-wire the SoC's internal routing through DT.

### GPIO reset for USB hub — same patch panel principle

The USB hub chip (FE1_QFP48) has a reset pin `nXRSTJ` wired to RK3288's GPIO8_A3. The DTS configures this:

```dts
/* rk3288-firefly.dtsi */
usb_host {
    usbhub_rst: usbhub-rst {
        rockchip,pins = <8 RK_PA3 RK_FUNC_GPIO &pcfg_output_high>;
        //                 │    │        │           │
        //                 │    │        │           └── drive HIGH (hub out of reset)
        //                 │    │        └── route as GPIO (not UART, not SPI)
        //                 │    └── pin A3
        //                 └── GPIO bank 8
    };
};

&usb_host1 {
    pinctrl-0 = <&usbhub_rst>;  // hand this GPIO to the DWC2 driver
};
```

```
   SoC internal routing                    PCB (fixed copper)
  ┌─────────────────────────────┐         ┌──────────────────┐
  │                             │         │                  │
  │  GPIO8_A3 pin ─────────────┐│         │                  │
  │   can be:                  ││         │                  │
  │   - UART1_TX  (func 1)     ││ PCB     │                  │
  │   - SPI0_CLK  (func 2)     ││ trace   │   FE1_QFP48      │
  │   - GPIO      (func 0) ◄───┼┼─────────┼── nXRSTJ         │
  │                             │         │                  │
  │  The DT says:               │         │                  │
  │  RK_PA3 + RK_FUNC_GPIO      │         │                  │
  │  → route this pin as GPIO   │         │                  │
  │                             │         │                  │
  │  pinctrl-0 = <&usbhub_rst>  │         │                  │
  │  → attach this GPIO to      │         │                  │
  │    usb_host1 driver         │         │                  │
  └─────────────────────────────┘         └──────────────────┘
```

Two layers of software routing in one line:

| Field | What it does |
|-------|-------------|
| `8` + `RK_PA3` | Which physical pin (GPIO8 bank, pin A3) |
| `RK_FUNC_GPIO` | Route it as GPIO (not UART, not SPI...) — **SoC internal mux** |
| `&pcfg_output_high` | Drive it HIGH (hub out of reset) — **pad config** |
| `pinctrl-0 = <&usbhub_rst>` | Hand this pin to the usb_host1 driver — **consumer binding** |

The PCB designer chose THIS specific GPIO pin because it was physically close to the hub chip and unused. The DTS just documents that choice in software. Same principle as `phys = <&usbphy2>` — just routing signals inside the patch panel.
