How to build rootfs
 - Run build-rootfs.sh
 - Run blkid to determine the PARTUUID
 - chroot rootfs-debian 
 - copy rootfs-debian/ to /mnt
    sudo rsync -aHAX --numeric-ids ./rootfs-debian/ /mnt/
 - edit /mnt/etc/fstab
    PARTUUID=05e4f39d-01 / ext4 defaults,noatime 0 1
 - edit extlinux.conf
    root@redmi-book:/# cat /boot/extlinux/extlinux.conf 
    label Armbian
      kernel /boot/zImage
      fdt /boot/dtb/rockchip/rk3288-firefly.dtb
      append root=PARTUUID=05e4f39d-01 rw rootwait rootfstype=ext4 console=ttyS2,115200

