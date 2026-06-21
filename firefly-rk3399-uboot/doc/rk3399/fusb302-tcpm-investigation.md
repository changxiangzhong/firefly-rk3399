# Thorough Investigation Report: U-Boot FUSB302 Driver & TCPM Framework for RK3399

## 1. FUSB302 Driver (`drivers/usb/tcpm/fusb302.c`) -- Core Analysis

### Data-Role Handling
- **Yes, it handles data-role**, but only at the PD header register level. The function `fusb302_set_roles()` (lines 590-614) receives both `pwr` (power role) and `data` (data role) parameters and writes them to the `FUSB_REG_SWITCHES1` register via the `POWERROLE` and `DATAROLE` bit fields. These are PD message header bits the chip inserts into outgoing PD packets.
- However, the **decision** of what data-role to use is **not** made by the FUSB302 driver. It's dictated by the TCPM state machine.

### Probe/Bind
- The FUSB302 driver has **NO `.probe` function** in its `U_BOOT_DRIVER` struct (lines 1317-1323). It only registers `.ops`, `.id = UCLASS_TCPM`, `.of_match`, and `.priv_auto`.
- Actual initialization flows through the **TCPM uclass** framework:
  - `tcpm_post_bind()` (in `tcpm-uclass.c`) is called after binding. It conditionally sets `DM_FLAG_PROBE_AFTER_BIND` (only for non-self-powered, sink-only configurations).
  - After probe, `tcpm_post_probe()` runs, which calls `tcpm_port_init()` -> `tcpm_init()` -> `fusb302_init()`.
- So binding/registration does work, but the auto-probe is **very restricted**.

### Production-Ready vs Stub?
The driver is **partially functional with critical stubs**:

| Function | Status |
|----------|--------|
| CC toggling (DRP/SRC/SNK) | Fully implemented -- sets MODE bits, starts TOGGLE bit |
| CC detection (Rd/Ra detection, BC_LVL measurement) | Fully implemented -- reads comparator, uses MDAC for thresholds |
| CC polarity detection | Fully implemented -- `fusb302_set_cc_polarity_and_pull()` |
| VCONN control | Fully implemented |
| PD message TX/RX | Fully implemented -- token-based FIFO, GoodCRC auto-reply |
| PD Hard Reset | Fully implemented |
| Interrupt polling | Fully implemented -- `fusb302_interrupt_handle()` processes all IRQs |
| **VBUS control** | **STUB** -- `fusb302_set_vbus()` returns 0 doing **nothing** (lines 507-510) |
| IRQ-based operation | No -- polling only (`fusb302_poll_event()`) |
| Low power mode | Implemented |

The VBUS stub is critical: the driver cannot actually enable/disable VBUS, so the Type-C power contract is **incomplete**.

---

## 2. TCPM Framework (`drivers/usb/tcpm/tcpm.c`) -- What It Does

### DT Parsing (`tcpm_fw_get_caps()`, lines 2131-2209)
The TCPM framework reads the following from the `connector` subnode of the TCPC device:
- `power-role` (string: "dual", "source", "sink") -- maps to `port->typec_type`
- `source-pdos` (u32 array) -- source power data objects
- `sink-pdos` (u32 array) -- sink power data objects
- `try-power-role` (string: "sink", "source") -- preferred role for DRP
- `op-sink-microwatt` (u32) -- operating sink power
- `self-powered` (bool) -- self-powered flag

**Critically: `data-role` is NOT parsed from DT.** Despite many DTS files specifying `data-role = "dual"` or `data-role = "device"` in the connector node, the TCPM framework **ignores** this property entirely.

Instead, data-role is **hardcoded** based on power role in the state machine:
- `tcpm_src_attach()` (line 1291): sets `data = TYPEC_HOST` -- source always becomes USB host
- `tcpm_snk_attach()` (line 1399): sets `data = TYPEC_DEVICE` -- sink always becomes USB device

This means **DR_SWAP** (data role swap via PD) is only supported when the partner initiates it.

### State Machine
The TCPM implements a **full USB PD state machine** with ~35 states including:
- SRC states: UNATTACHED, ATTACH_WAIT, ATTACHED, STARTUP, SEND_CAPABILITIES, NEGOTIATE_CAPABILITIES, READY
- SNK states: UNATTACHED, ATTACH_WAIT, DEBOUNCED, ATTACHED, DISCOVERY, WAIT_CAPABILITIES, NEGOTIATE, READY
- Hard/Soft Reset, DR_SWAP, Error Recovery, Port Reset

### Auto-Probe Logic (`tcpm_post_bind()`, lines 83-141)
The framework will **only auto-probe** when ALL of these are true:
1. Device is **not** `self-powered`
2. `power-role` is exactly `"sink"` (NOT "dual" or "source")
3. `pd-disable` is **not** set

For firefly-rk3399 (power-role = "dual"), the TCPM will **NOT auto-probe**. For rock5b-rk3588 (power-role = "sink"), it **will** auto-probe.

---

## 3. DM Class for TCPM (`UCLASS_TCPM`)

**Yes, there is a `UCLASS_TCPM` driver class.**

Defined in:
- **Header:** `include/dm/uclass-id.h` line 142
- **Implementation:** `drivers/usb/tcpm/tcpm-uclass.c`

The uclass provides these API functions:
- `tcpm_get()`, `tcpm_get_voltage()`, `tcpm_get_current()`, `tcpm_get_orientation()`, `tcpm_get_state()`, `tcpm_get_pd_rev()`, `tcpm_get_pwr_role()`, `tcpm_get_data_role()`, `tcpm_is_connected()`

There is also a `tcpm` CLI command in `cmd/tcpm.c` with `list`, `dev`, and `info` subcommands.

---

## 4. `g_dnl_board_usb_cable_connected()` for RK3399/Rockchip

**There is NO Rockchip-specific implementation.** The weak default in `drivers/usb/gadget/g_dnl.c` (line 180):

```c
__weak int g_dnl_board_usb_cable_connected(void)
{
    return -EOPNOTSUPP;
}
```

**Important behavioral note:** The UMS command (`cmd/usb_mass_storage.c`, line 188) checks:
```c
if (!g_dnl_board_usb_cable_connected()) {
    // wait for cable...
}
```
Since `-EOPNOTSUPP` evaluates to truthy (non-zero), `!(-EOPNOTSUPP)` is `0` (false), so the cable-wait loop is **skipped entirely**. UMS starts immediately without checking whether a Type-C cable is connected.

Boards that DO implement this function (none are Rockchip):
- `board/sunxi/board.c` -- checks USB PHY status
- `board/st/stm32mp1/stm32mp1.c` -- GPIO-based detection
- `board/samsung/trats/trats.c`, `trats2/trats2.c` -- PMIC/GPIO
- `board/dhelectronics/dh_stm32mp1/board.c` -- GPIO
- `drivers/usb/gadget/max3420_udc.c` -- always returns 1 (always connected)

**None of these use TCPM.** There is zero integration between the TCPM framework and the USB gadget download layer.

---

## 5. Boards Using TYPEC_TCPM + TYPEC_FUSB302

| Defconfig | Has TYPEC_TCPM | Has TYPEC_FUSB302 |
|-----------|:---:|:---:|
| `firefly-rk3399_defconfig` | Yes | Yes |
| `rock5b-rk3588_defconfig` | Yes | Yes |
| `khadas-edge2-rk3588s_defconfig` | Yes | Yes |
| `rock960-rk3399_defconfig` | No | No |

DTS files with `fcs,fusb302` compatible:
- **RK3399:** firefly, rockpro64, roc-pc, orangepi, pinebook-pro, nanopi4, eaidk-610, hugsun-x99
- **RK3588:** orangepi-5, indiedroid-nova, evb1, odroid-m2, rock-5-itx, nanopc-t6, friendlyelec-cm3588-nas, rock-5b (via u-boot.dtsi)
- **Other SoCs:** amlogic meson-gxm, aspeed bmc bletchley

---

## 6. How UMS Works on rock960-rk3399 WITHOUT TCPM/FUSB302

The rock960-rk3399 config does **not** have `CONFIG_TYPEC_TCPM` or `CONFIG_TYPEC_FUSB302`. UMS works as follows:

1. User executes `ums` command
2. `g_dnl_board_usb_cable_connected()` returns `-EOPNOTSUPP` (weak default)
3. The cable-check loop is skipped (since `!(-EOPNOTSUPP) == false`)
4. UMS initializes immediately and starts serving
5. The Type-C physical layer is handled entirely by the **Rockchip Type-C PHY** (`CONFIG_PHY_ROCKCHIP_TYPEC=y`) -- a hardware block in the RK3399 SoC that handles CC detection, orientation, and muxing autonomously
6. For host mode (USB storage, keyboard), XHCI/EHCI controllers work through the same PHY

In essence: **RK3399 doesn't need the FUSB302 driver** because it has its own integrated Type-C PHY (`PHY_ROCKCHIP_TYPEC`). The FUSB302 is an *external* Type-C controller chip found on some boards (firefly, rockpro64, pinebook-pro, etc.) and on RK3588 boards.

---

## 7. What the FUSB302 Probe Actually Does (via TCPM)

When `fusb302_init()` is called (lines 217-245):
1. **SW reset** the chip (`FUSB_REG_RESET_SW_RESET`)
2. **Enable TX auto-retries** (3 retries for PD 2.0)
3. **Initialize interrupts** -- only VBUS_OK unmasked; all others masked
4. **Set power mode** to "all on" (`FUSB_REG_POWER_PWR_ALL`)
5. **Read VBUS status** from STATUS0 register
6. **Read and log** device ID

Then `tcpm_init()` (in tcpm.c, lines 2090-2129):
1. Calls the driver init (above)
2. Resets port state (disables PD RX, VBUS, VCONN)
3. Reads current VBUS presence
4. Gets initial CC status
5. Sets state machine to default state and runs it

**CC pins are NOT configured in init.** They are configured later through the state machine:
- `tcpm_src_attach()` or `tcpm_snk_attach()` or `tcpm_start_toggling()` -> `fusb302_start_toggling()` is called
- `fusb302_start_toggling()` sets the toggling mode (DRP/SRC/SNK), which configures CC pull-up/pull-down resistors through the CONTROL2 MODE bits
- When toggling completes, `fusb302_handle_togdone_src()` or `fusb302_handle_togdone_snk()` configures the final CC polarity and pull

---

## Summary Verdict

**These drivers are NOT production-ready for general use. They are functional prototypes/stubs.**

| Aspect | Verdict |
|--------|---------|
| CC detection/toggling | Working |
| PD message send/receive | Working |
| PD state machine | Sophisticated, largely complete |
| **VBUS control** | **STUB** (does nothing) -- critical gap |
| **data-role from DT** | **Not implemented** -- framework ignores `data-role` property |
| **IRQ support** | No -- polling only |
| **Integration with g_dnl/gadget** | None -- TCPM is completely isolated from USB gadget framework |
| **Auto-probe scope** | Very narrow -- only sink-only, non-self-powered devices auto-probe |
| **Coverage** | Only boards with external FUSB302 chip benefit; RK3399's internal Type-C PHY is sufficient without it |

**Other boards achieve UMS without TCPM by:**
1. Using the SoC's internal Type-C PHY (RK3399: `PHY_ROCKCHIP_TYPEC`)
2. Letting `g_dnl_board_usb_cable_connected()` return `-EOPNOTSUPP`, which skips cable detection entirely
3. Or implementing `g_dnl_board_usb_cable_connected()` with simple GPIO/PHY checks (sunxi, stm32mp1 boards)

The TCPM/fusb302 infrastructure appears to be a **work-in-progress port from Linux** (copyright 2024 Collabora), primarily targeting RK3588 boards (like rock5b) where the FUSB302 is the main Type-C controller, to enable basic PD sink negotiation so the board can receive power through USB-C during U-Boot. It is not designed for or integrated with USB gadget mode (UMS/fastboot).
