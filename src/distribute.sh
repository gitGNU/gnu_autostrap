#!/bin/bash -e
# Prepare trimmed, compressed, distributable disk images
# Copyright (C) 2007, 2010  Sylvain Beucler
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

disk_image=$1

if [ -z $disk_image ]; then
    echo "Usage: $0 disk_image"
    exit 1
fi
image_name=${disk_image%.img}

# Rewrite the disk image, this file get rid of deleted files that
# weren't completely deleted and take space (eg. downloaded packages)
partition_fs=`lofile.sh $disk_image 1`
UNITS=`fdisk -lu $disk_image 2>/dev/null | grep ${disk_image}1 | tr -d '*' | tr -s ' ' | cut -f2 -d' '`
offset=`expr 512 '*' $UNITS`

if [ "$partition_fs" == 'UNKNOWN' ]; then
    echo "Unknown file system"
    exit 1
fi
if [ "$partition_fs" == "ext3" -o "$partition_fs" == "ext2" ]; then
    # Oldish stuff:
    ## non-patched-grub-legacy doesn't like the default 256 inode size
    ## mkfs.ext3: "Warning: 256-byte inodes not usable on older systems"
    #loop=$(losetup -o $offset -f -v $disk_image.2 | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
    #mkfs.$partition_fs -I 128 -q $loop
    #losetup -d $loop

    # Use zerofree: it is faster than re-copying all files to a new
    # disk image, and produces a slightly smaller image (though it's
    # slightly larger after conversion to qcow2)
    loop=$(losetup -o $offset -f -v $disk_image | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
    zerofree -v $loop
    losetup -d $loop

    # http://intgat.tigress.co.uk/rmy/uml/sparsify.html mentions the
    # 'sparsify.c' companion to 'zerofree', but it's just like 'cp
    # --sparse=always' (except that it works in-place), and it
    # requires working on the partition *containing* the disk image
    # (which requires real root access, and remounting it read-only),
    # so let's not use it.
else
    mp1=`mktemp -d`
    lomount.sh $disk_image 1 $mp1 || exit 1

    mp2=`mktemp -d`
    rm -f $disk_image.2
    # Make an image with exactly the same size and filesystem type
    dd if=/dev/null of=$disk_image.2 bs=1 seek=`ls -l $disk_image | awk '{ print $5}'`
    # Copy first sector (bootsector + grub stage1.5)
    dd if=$disk_image of=$disk_image.2 count=1 bs=$offset conv=notrunc
    loop=$(losetup -o $offset -f -v $disk_image.2 | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
    if [ "$partition_fs" = "reiserfs" ]; then
	mkfs.reiserfs --label $image_name -q $loop
    else
	mkfs.$partition_fs -L $image_name -q $loop
    fi
    losetup -d $loop
    lomount.sh $disk_image.2 1 $mp2 || exit 1

    cp -a --sparse=always $mp1/* $mp2/

    umount $mp1
    umount $mp2

    mv $disk_image.2 $disk_image
fi

# Use sparse blocks whenever possible:
# (not needed here, tar and qemu-img also take care of that)
#cp --sparse=always $disk_image $disk_image.sparse
#mv $disk_image.sparse $disk_image

# Compress sparse file (taking holes into account)
# Plain gzip would work too, but wouldn't respect the holes when
# decompressing, hence the 'tar'.
tar cSzf $disk_image.tar.gz $disk_image
# TODO: add several scripts in the archive, along with documentation
# - README ("normal extraction tar xzf", "500MB sparse / 2GB max image"...)
# - qemu.sh
# - qemu-tuntap.sh
# - uml.sh
# - uml-net.sh
# - vserver.sh
# ...

# Convert image to a compressed qcow2 image, directly usable by qemu
# (no prior extraction/uncompress is needed). It is probably less
# efficient than a raw image file.
# qcow (obsolete) appears with QEMU 0.6.1:
#qemu-img convert -c $disk_image -O qcow ${disk_image%.img}.qcow
# qcow2 appears with QEMU 0.9:
qemu-img convert -c $disk_image -O qcow2 ${disk_image%.img}.qcow2


# VirtualBox
# apt-get install virtualbox-ose
disk_image_vdi=${disk_image%.img}.vdi
VBoxManage convertfromraw $disk_image $disk_image_vdi
# The resulting file is still quite big, we'd need to compress it.
#gzip $disk_image_vdi
# But let's create a OVF file instead.
#VBoxManage createhd --filename $disk_image_vdi --size 1 --remember
mv -f $disk_image_vdi ~/.VirtualBox/HardDisks/
VBoxManage createvm --name $image_name --register
# Let's not use sata otherwise we'll get hda vs. sda conflicts, and
# we'd need to generate an initrd + use root=LABEL=savane.
VBoxManage storagectl $image_name --name hda --add ide --controller PIIX4
VBoxManage storageattach $image_name --storagectl hda --port 0 --device 0 --type hdd --medium $disk_image_vdi
VBoxManage modifyhd $disk_image_vdi --compact
VBoxManage modifyvm $image_name --nic1 nat --nictype1 82540EM
VBoxManage modifyvm $image_name --ostype Debian
VBoxManage export -o savane.ovf
# Clean-up
VBoxManage storagectl savane --name hda --remove
VBoxManage unregistervm savane --delete
rm -f ~/.VirtualBox/HardDisks/$disk_image_vdi

# The VM fails to boot if we do this???
# Configuration error: Failed to get the "MAC" value (VERR_CFGM_VALUE_NOT_FOUND).
# Unknown error creating VM (VERR_CFGM_VALUE_NOT_FOUND).
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/Apache/Protocol" TCP
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/Apache/GuestPort" 80
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/Apache/HostPort" 50081
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/SSH/Protocol" TCP
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/SSH/GuestPort" 22
#VBoxManage setextradata "$image_name" "VBoxInternal/Devices/pcnet/0/LUN#0/Config/SSH/HostPort" 2222
