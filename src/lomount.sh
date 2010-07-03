#!/bin/sh
# Mount partitions within a disk image file
# Copyright (C) 2005  Padraig Brady
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

# From "Various (GPL) scripts that I've created.":
# http://www.pixelbeat.org/scripts/
# http://www.pixelbeat.org/scripts/lomount.sh

# See also: http://wiki.osdev.org/Loopback_Device#Detach_our_disk_image_from_the_loopback_device.

# Author: P@adraigBrady.com

# V1.0      29 Jun 2005     Initial release
# V1.1      01 Dec 2005     Handle bootable (DOS) partitions

# Changes by Sylvain Beucler <beuc@beuc.net>
# V???      2007            Handle files that end with a number
# V???      2010            Output 'losetup -a' on failure; mention kpartx

# Note: see also 'kpartx', that can create /dev/mapper/loop0p1 .

if [ "$#" -ne "3" ]; then
    echo "Usage: `basename $0` <image_filename> <partition # (1,2,...)> <mount point>" >&2
    exit 1
fi

if ! fdisk -v > /dev/null 2>&1; then
    echo "Can't find the fdisk util. Are you root?" >&2
    exit 1
fi

FILE=$1
PART=$2
DEST=$3

# fdisk's output is not consistent depending on the filename:
# With disk.img:
#disk.img1              63     4194287     2097112+  83  Linux
# But with disk.img.2:
#disk.img.2p1              63     4194287     2097112+  83  Linux
if echo $FILE | grep '[0-9]$'; then
    PART=p$PART
fi
UNITS=`fdisk -lu $FILE 2>/dev/null | grep $FILE$PART | tr -d '*' | tr -s ' ' | cut -f2 -d' '`
OFFSET=`expr 512 '*' $UNITS`
mount -o loop,offset=$OFFSET $FILE $DEST \
  || losetup -a >&2  # debug info

# Normaly umount will take care of freeing the loopX device.  However
# if running in UML (2.6.26), it won't.  If that's a problem we may
# need to implement a -u option to manually free to loopX device.
# This is crucial when the host does not have the 'loop' module
# loaded, it only has a single loop0 special file.  We may need to
# replace and repopulate /dev in umdo.sh, but that particularly slow.
