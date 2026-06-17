# Q&A: How to pack kernel for bootable SD card on firefly-rk3399

## Question

Suppose I've compiled kernel with `make firefly-rk3399_defconfig` and `make`. How can I pack the vmlinux file to a .img file? I need .img file dd to a tf card right?

## Answer

You don't pack `vmlinux` — it's the raw ELF, not bootable. For RK3399/arm64 you use `arch/arm64/boot/Image`, which U-Boot loads directly via `booti` (no `mkimage` wrapping needed).

**For a bootable SD card, you need:**

1. **Kernel:** `arch/arm64/boot/Image` (raw binary, no conversion)
2. **DTB:** `arch/arm64/boot/dts/rockchip/rk3399-firefly.dtb`
3. **U-Boot blobs:** from your earlier build — `idbloader.bin`, `uboot.img`, `trust.bin`
4. **Root filesystem** (ext4 tarball or equivalent)

**SD card layout (for RK3399):**

```
Sector 64:    idbloader.bin      (SPL + DDR init)
Sector 16384: uboot.img          (U-Boot proper)
Sector 24576: trust.bin          (ATF/TrustZone)
Sector 32768: ext4 root partition
  /boot/Image              → your kernel
  /boot/dtb/rockchip/rk3399-firefly.dtb  → device tree
  /boot/extlinux/extlinux.conf → boot config
```

**To write a working SD card manually:**

```bash
# Partition SD card (e.g., /dev/sdb) — one partition at 16MiB
sfdisk /dev/sdb << EOF
start=32768, type=L
EOF

# Write U-Boot blobs
dd if=idbloader.bin of=/dev/sdb seek=64
dd if=uboot.img    of=/dev/sdb seek=16384
dd if=trust.bin    of=/dev/sdb seek=24576

# Format root partition, copy everything
mkfs.ext4 /dev/sdb1
mount /dev/sdb1 /mnt
mkdir -p /mnt/boot/dtb/rockchip /mnt/boot/extlinux
cp arch/arm64/boot/Image /mnt/boot/
cp arch/arm64/boot/dts/rockchip/rk3399-firefly.dtb /mnt/boot/dtb/rockchip/

# extlinux.conf (for U-Boot distro boot):
cat > /mnt/boot/extlinux/extlinux.conf << EOF
label Armbian
  kernel /boot/Image
  fdt /boot/dtb/rockchip/rk3399-firefly.dtb
  append root=/dev/mmcblk1p1 rw console=ttyS2,1500000
EOF
```

The kernel is used as-is — just copy `Image` to `/boot/Image`. No `.img` packing step exists for ARM64 mainline boot. The only thing Armbian wraps with `mkimage` is the initrd (→ `uInitrd`), which is optional.
