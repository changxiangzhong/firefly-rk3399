======================================================================
Boot order
======================================================================

Firefly-rk3288 board would prioritize emmc over sdcard. So if you want to boot from sdcard, make sure to wipe emmc completely


======================================================================
How to compile
======================================================================
make O=rk3288 firefly-rk3288_defconfig all


======================================================================
How to flash SD card
======================================================================
sudo dd if=idbloader.img of=/dev/mmcblk0 seek=64
sudo dd if=u-boot-dtb.img of=/dev/mmcblk0 seek=16384

