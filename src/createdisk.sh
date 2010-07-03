#!/bin/bash
# Disk image creator with physical geometry simulation
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

# Create a complete disk image, with a partition table and one
# formatted ext3 partition. Tries to mimic a real hard drive geometry
# for use in an emulator.

function usage() {
    echo "Usage: $0 disk_image.img size_in_mb fs_type";
}

disk_image=$1
SIZE=$2 #MB
partition_fs=${3:-ext3}

if [ -z $disk_image -o -z $SIZE ]; then
    usage
    exit 1
fi

# Common values - try to respect the cylinder boundaries and get a
# clean virtual hard-disk

BLOCKSIZE=512 # or 1024/4096?
              # See http://www.kix.in/parted/gsg/concepts.html

# CHS - Cylinder/Head/Sector:
# Default qemu geometry is 16*63 (cf. ide.c:default_geometry)
# Though, QEMU says '255 heads' when fdisk -l /dev/empty_image_disk (why?)
# The code also says a bigger number of heads implies a BIOS LBA translation
HEADS=16   
SECTORS=63
# Number of cylinders, round
CYLINDERS=$(( $SIZE * 1024 * 1024 / ($HEADS * $SECTORS * $BLOCKSIZE) ))

# Fuzzy version:
#dd if=/dev/null of=hda.img bs=$BLOCKSIZE seek=$[ $SIZE*1024*1024 / $BLOCKSIZE ]
# Precise version:
echo -n > $disk_image # erase content but keep permissions
dd bs=$(($SECTORS * $BLOCKSIZE)) if=/dev/null of=$disk_image seek=$(($CYLINDERS * $HEADS))

# New partition table, new primary partition 1
cat <<EOF | fdisk -C $CYLINDERS -H $HEADS -S $SECTORS $disk_image
o
n
p
1


w
q
EOF

# parted would be cool to use, but is not very precise and get
# confused with missing CHS info
#parted $disk_image mklabel msdos mkpartfs primary ext2 0 ${CYLINDERS}cyl

# TODO: try with sfdisk - including building the initial partition
# table out of the void like fdisk just did.


# The entire first track is reserved for the partition table by fdisk
offset=$(( $SECTORS * $BLOCKSIZE ))

echo "* Formatting pseudo-partition 1"
loop=$(losetup -o $offset -f -v $disk_image | sed -n -e 's,Loop device is \(/dev/.*\),\1,p')
mkfs.$partition_fs -q $loop
losetup -d $loop
