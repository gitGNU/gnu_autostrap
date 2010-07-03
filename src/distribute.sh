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

image=$1

if [ -z $image ]; then
    echo "Usage: $0 image"
    exit 1
fi

# Rewrite the disk image, this file get rid of deleted files that
# weren't completely deleted and take space (eg. downloaded packages)
fstype=`lofile.sh $image 1`
UNITS=`fdisk -lu $image 2>/dev/null | grep ${image}1 | tr -d '*' | tr -s ' ' | cut -f2 -d' '`
offset=`expr 512 '*' $UNITS`

if [ "$fstype" == 'UNKNOWN' ]; then
    echo "Unknown file system"
    exit 1
fi
if [ "$fstype" == "ext3" -o "$fstype" == "ext2" ]; then
    # Oldish stuff:
    ## non-patched-grub-legacy doesn't like the default 256 inode size
    ## mkfs.ext3: "Warning: 256-byte inodes not usable on older systems"
    #loop=$(losetup -o $offset -f -v $image.2 | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
    #mkfs.$fstype -I 128 -q $loop
    #losetup -d $loop

    # Use zerofree (faster than copying all files to a new disk image)
    loop=$(losetup -o $offset -f -v $image | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
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
    lomount.sh $image 1 $mp1 || exit 1

    mp2=`mktemp -d`
    rm -f $image.2
    # Make an image with exactly the same size and filesystem type
    dd if=/dev/null of=$image.2 bs=1 seek=`ls -l $image | awk '{ print $5}'`
    # Copy first sector (bootsector + grub stage1.5)
    dd if=$image of=$image.2 count=1 bs=$offset conv=notrunc
    loop=$(losetup -o $offset -f -v $image.2 | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
    mkfs.$fstype -q $loop
    losetup -d $loop
    lomount.sh $image.2 1 $mp2 || exit 1

    cp -a $mp1/* $mp2/

    umount $mp1
    umount $mp2

    mv $image.2 $image
fi

# Use sparse blocks whenever possible:
# (not needed here, tar and qemu-img also take care of that)
#cp --sparse=always $image $image.sparse
#mv $image.sparse $image

# Compress sparse file (taking holes into account)
tar cSzf $image.tar.gz $image
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
#qemu-img convert -c $image -O qcow ${image%.img}.qcow
# qcow2 appears with QEMU 0.9:
qemu-img convert -c $image -O qcow2 ${image%.img}.qcow2
