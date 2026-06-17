===============================================================
This tutorial only applies to TF card boot!!
===============================================================

Use uboot version:

v2022.04

Use Trusted-Firmware-A version:

v2.6

Follow the tutorial in 
${u-boot}/doc/board/rockchip/rockchip.rst

Key build scripts

========================================================================
Key scripts - Option 1: Package the image with Rockchip miniloader
========================================================================

cd trusted-firmware-a/
git checkout -b v2.6 tags/v2.6
make realclean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=rk3399   LDFLAGS="--no-warn-rwx-segments"

cd ../u-boot/
git checkout -b v2022.04 tags/v2022.04
export BL31=../trusted-firmware-a/build/rk3399/release/bl31/bl31.elf

make firefly-rk3399_defconfig
make CROSS_COMPILE=aarch64-linux-gnu-

find ./ -name u-boot-rockchip.bin
find ./ -name idbloader.img
find ./ -name u-boot-dtb.bin

./rkbin/tools/mkimage -n rk3399 -T rksd -d ./rkbin/bin/rk33/rk3399_ddr_933MHz_v1.30.bin ./u-boot/idbloader.img
cat rkbin/bin/rk33/rk3399_miniloader_v1.30.bin >> u-boot/idbloader.img
sudo dd if=u-boot/idbloader.img of=/dev/mmcblk0 seek=64

cd rkbin/
./tools/trust_merger RKTRUST/RK3399TRUST.ini
sudo dd if=trust.img of=/dev/mmcblk0 seek=24576

../rkbin/tools/loaderimage --pack --uboot u-boot-dtb.bin uboot.img 0x200000
sudo dd if=uboot.img of=/dev/mmcblk0 seek=16384


===============================================================
Key scripts - Option 3: Package the image with TPL:
===============================================================

cd trusted-firmware-a/
git checkout -b v2.6 tags/v2.6
make realclean
make CROSS_COMPILE=aarch64-linux-gnu- PLAT=rk3399   LDFLAGS="--no-warn-rwx-segments"

# Compile u-boot
export BL31=../trusted-firmware-a/build/rk3399/release/bl31/bl31.elf
make clean
make firefly-rk3399_defconfig
make -j 16

sudo dd if=idbloader.img of=/dev/sdb seek=64
sudo dd if=u-boot.itb of=/dev/sdb seek=16384



===============================================================
Terms in uboot & rockchip
===============================================================

+--------+----------------+----------+-------------+---------+
|Boot phase | Terminology | Program name | RK image name | Image location |
+--------+----------------+--------------+---------------+----------------+
| 1         | Primary     | ROM code     | BootRom       |                |
|           | Program     |              |               |                |
|           | Loader      |              |               |                |
|           |             |              |               |                |
| 2         | Secondary   | U-Boot       |idbloader.img  | 0x40           | pre-loader
|           | Program     | TPL/SPL      |               |                |
|           | Loader (SPL)|              |               |                |
|           |             |              |               |                |
| 3         | -           | U-Boot       | u-boot.itb    | 0x4000         | including u-boot and atf
|           |             |              | uboot.img     |                | only used with miniloader
|           |             |              |               |                |
|           |             | ATF/TEE      | trust.img     | 0x6000         | only used with miniloader
|           |             |              |               |                |
| 4         | -           | kernel       | boot.img      | 0x8000         |
|           |             |              |               |                |
| 5         | -           | rootfs       | rootfs.img    | 0x40000        |
+-----------+-------------+--------------+---------------+----------------+



===============================================================
Useful script
===============================================================

sudo dd if=idbloader.img of=/dev/mmcblk0 seek=64
sudo dd if=u-boot.itb of=/dev/mmcblk0 seek=16384

export BL31=../trusted-firmware-a/build/rk3399/release/bl31/bl31.elf


