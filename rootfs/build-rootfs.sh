#!/bin/bash
set -x

TARGET=./rootfs-debian
ARCH=armhf
RELEASE=trixie

mkdir -p $TARGET

debootstrap --foreign --arch=$ARCH $RELEASE $TARGET http://deb.debian.org/debian
# 为了在 x86 主机上 chroot 进入 arm64 文件系统，需要拷贝 QEMU
cp /usr/bin/qemu-arm-static $TARGET/usr/bin/
update-binfmts --enable qemu-arm
#
chroot $TARGET /debootstrap/debootstrap --second-stage

