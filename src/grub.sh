#!/bin/bash -x
# Manually install GRUB in a disk image's first sector
# Copyright (C) 2007  Sylvain Beucler
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301, USA.

# Note: this is obsolete, as there is actually a way to make GRUB
# install itself on a disk image. 'grub-install' does not support
# this, but base 'grub' with a custom device.map files does support
# it:
# 
#   echo "(hd0) /path/to/my/system.img" > device.map
#   echo -e "root (hd0,0)\nsetup (hd0)" | /usr/sbin/grub --device-map=device.map --batch


# In file $1, at offset $2, write $3 in format $4
function overwrite() {
  perl -e 'use IO::File;
    unshift(@ARGV, ""); # same indexes as shell
    sysopen(HANDLE, $ARGV[1], O_RDWR) or die "sysopen($ARGV[1]): $!";
    sysseek(HANDLE, $ARGV[2], SEEK_SET) or die "sysseek($ARGV[1]): $!";
    syswrite(HANDLE, pack($ARGV[4], $ARGV[3])) or die "syswrite($ARGV[1]): $!";
    close(HANDLE);' -- $1 $2 $3 $4
}

disk_image=$1
partition_fs=${2:-ext3}
grub_arch=${3:-i386-pc} # or x86_64-pc; maybe autodetect instead of default

if [ -z $disk_image ]; then
    echo "Usage: $0 disk_image.img [fs_type=ext3] [grub_arch=i386-pc]"
    exit 1
fi

if [ $partition_fs != "ext3" -a $partition_fs != "reiserfs" ]; then
    echo "Unsupported filesystem: $partition_fs"
    exit 1
fi

if [ ! -e /usr/lib/grub/$grub_arch ]; then
    echo "GRUB arch not present: /usr/lib/grub/$grub_arch"
    exit 1
fi

# Backup the partition table only
#dd if=hda.img of=fdisk.test bs=1 count=64 skip=446 seek=446 conv=notrunc

# -------

# Documentation:
# - node "Embedded data" in grub.info
# - stage1.S in GRUB source code
# - still, I had to compare vanilla and grub-installed boot sectors
#   with hexedit to determine which bytes needed change, so not
#   everything is documented

# Copy the initial stage1, needs to be parametered so as to launch
# e2fs_stage1_5 and (hd0,0)/boot/grub/stage2
dd if=/usr/lib/grub/$grub_arch/stage1 of=$disk_image bs=1 count=446 conv=notrunc > /dev/null

# Stage2 location. Default values (cf. stage1.S):
#   stage2_address: 0x8000 = 32k
#   stage2_sector:  1
#   stage2_segment: 0x0800 = 2k
# Apparemment le segment se (pré-)calcule à partir de l'adresse.
#dd if=hda.mbr.backup of=hda.img conv=notrunc skip=66 seek=66 count=10 bs=1
overwrite $disk_image $[0x42] $[0x2000] 'S'
overwrite $disk_image $[0x44] $[0x1] 'I'
overwrite $disk_image $[0x48] $[0x0200] 'S'

# Install stage2 in the space after the MBR and before the first
# partition (first disk track):
case $partition_fs in
    ext3)
	dd if=/usr/lib/grub/$grub_arch/e2fs_stage1_5 of=$disk_image bs=512 seek=1 conv=notrunc > /dev/null;;
    reiserfs)
	dd if=/usr/lib/grub/$grub_arch/reiserfs_stage1_5 of=$disk_image bs=512 seek=1 conv=notrunc > /dev/null;;
esac

# Data is in the 2nd sector of stage1_5/stage2
# Byte 0x419 must be set to 0 - else "Error 17" in reiserfs and <TODO> in ext3 (why?)
#dd if=/dev/zero of=hda.img bs=1 count=1 seek=1049 conv=notrunc
overwrite $disk_image $[0x419] $[0x0] 'C'

# Add a path to the configuration file (optional?)
# It's done by grub-install though.
#echo -n " /boot/grub/menu.lst" | dd of=hda.img bs=1 seek=1068 conv=notrunc

case $partition_fs in
    ext3) # 0x0E at byte 0x3FC? -> it works! (why?)
	overwrite $disk_image $[0x3FC] $[0x0E] 'C';;
    reiserfs) # 0x12 at byte 0x3FC? -> it works! (why?)
	overwrite $disk_image $[0x3FC] $[0x12] 'C';;
esac
