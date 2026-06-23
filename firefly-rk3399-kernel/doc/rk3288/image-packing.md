==========================================================
arm32 requires /boot/zImage, not /boot/Image
==========================================================



chang@redmi-book:~/.../mainline-kernel$ cat /mnt/boot/extlinux/extlinux.conf 
label Armbian
  kernel /boot/zImage
  fdt /boot/dtb/rockchip/rk3288-firefly.dtb
  append root=/dev/mmcblk0p1 rw console=ttyS2,115200



==========================================================
Kernel build history
==========================================================
# Build
ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- O=output/rk3288 make rockchip_linux_defconfig
ARCH=arm CROSS_COMPILE=arm-linux-gnueabi- make  -j16

# Partition the disk
sudo sfdisk /dev/sda << EOF
start=32768, type=L
EOF

# Make file system
sudo mkfs.ext4 /dev/sda1

# Copy files
mount  /dev/sda1 /mnt
sudo mount  /dev/sda1 /mnt
sudo mkdir -p /mnt/boot/dtb/rockchip /mnt/boot/extlinux
cp arch/arm/boot/Image /mnt/boot/
cp arch/arm/boot/zImage /mnt/boot/
cp arch/arm/boot/dts/rockchip/rk3288-firefly.dtb /mnt/boot/dtb/rockchip/

# Edit config file
cat > /mnt/boot/extlinux/extlinux.conf << EOF
label Armbian
  kernel /boot/zImage
  fdt /boot/dtb/rockchip/rk3288-firefly.dtb
  append root=/dev/mmcblk0p1 rw console=ttyS2,115200
EOF


