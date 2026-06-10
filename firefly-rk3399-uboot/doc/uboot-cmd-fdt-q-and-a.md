# U-Boot CLI: fdt & MMC Q&A

## Q1: I'm in U-Boot CLI. Can I use `fdt` to probe my eMMC `mmc@fe330000`?

Not directly. `fdt` only inspects/modifies the flat device tree blob in memory — it doesn't trigger driver probing. But you can use it together with other commands:

### Inspect the node

```
fdt list /mmc@fe330000           # show all properties
fdt get value /mmc@fe330000 status   # check if "okay" or "disabled"
```

### Force probe attempt

```
mmc list          # show what MMC devices are already probed
mmc dev 0         # try to probe mmc0 (which was &sdhci before our changes)
mmc dev 1         # try mmc1 (&sdmmc - SD card)
mmc info          # show details of current device
```

### Driver model view

```
dm tree           # show all devices, "probed" or not. Look for sdhci@fe330000
dm status         # device stats (probed count, fails)
```

### If you want to test eMMC with an already-booted U-Boot

If you're running the **old** U-Boot (before our DTS changes), eMMC is already enabled. Try:

```
mmc dev 0 && mmc info
```

If it hangs, the broken eMMC is causing trouble.

If you're running the **new** U-Boot (with our DTS changes), `&sdhci` is `status = "disabled"`, so `mmc dev 0` maps to the SD card (since we repointed `mmc0 = &sdmmc`). The eMMC controller won't even appear in `dm tree`.

---

## Q2: `fdt list mmc@fe330000` gives "No FDT memory address configured"

```
=> fdt list mmc@fe330000
No FDT memory address configured. Please configure
the FDT address via "fdt addr <address>" command.
Aborting!
```

You need to tell `fdt` where the device tree blob lives in memory. Try:

```
fdt addr ${fdtcontroladdr}
```

Or find it first:

```
fdt addr                          # shows current address (none set yet)
bdinfo                            # look for "fdt_blob" or "fdtcontroladdr" in output
echo ${fdtcontroladdr}            # may already be set as an env var
```

Then:

```
fdt list /mmc@fe330000
```

Note: `fdt` requires an absolute path starting with `/`, so `/mmc@fe330000`, not `mmc@fe330000`.

---

## Q3: What is `bdinfo`?

`bdinfo` (Board Info) prints low-level board data known to U-Boot: DRAM layout, flash banks, boot params, relocation offset, and crucially the FDT blob address. You run it at the U-Boot CLI:

```
=> bdinfo
```

In the output, look for lines like `fdt_blob`, `fdtcontroladdr`, or similar — that's the RAM address of the device tree that U-Boot is currently using. You can then feed that to `fdt addr`.

Alternatively, `fdtcontroladdr` is usually an environment variable holding that address:

```
=> echo ${fdtcontroladdr}
```

If it prints a hex value, just do:

```
=> fdt addr ${fdtcontroladdr}
=> fdt list /mmc@fe330000
```

---

## Q4: I've enabled `fdt set /mmc@fe330000 status okay` and `fdt set /syscon@ff770000/phy@f780 status okay`. How to examine my eMMC?

Two things to know:

### 1. `fdt set` only changes the in-memory blob — it does **not** trigger driver probing

U-Boot's driver model binds devices from the device tree at boot time. Changing the status after boot won't make the MMC driver probe the controller automatically.

### 2. To probe it, you need to bind the driver manually

Try:

```
bind /mmc@fe330000 arasan,sdhci-5.1        # bind driver to the node
mmc list                                      # see if it appears
mmc dev <n> && mmc info                       # probe and inspect
```

**Warning:** If the eMMC chip is truly broken, this will likely hang the board and you'll need to reset.

### If that doesn't work, check the DM tree first

```
dm tree | grep sdhci
```

If the node is already bound but just not probed, then a simple `mmc list` / `mmc dev` should be enough — the `mmc` command triggers lazy probing.
