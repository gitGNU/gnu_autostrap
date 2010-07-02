#!/bin/sh
# Map a disk image's partition to /dev/loop (for fsck purposes)
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

FILE=$1
PART=$2

if [ "$#" -ne "2" ]; then
    echo "Usage: $0 image no_partition" >&2
    exit 1
fi

if ! fdisk -v > /dev/null 2>&1; then
    echo "Can't find the fdisk util. Are you root?" >&2
    exit 1
fi

UNITS=`fdisk -lu $FILE 2>/dev/null | grep $FILE$PART | tr -d '*' | tr -s ' ' | cut -f2 -d' '`
OFFSET=`expr 512 '*' $UNITS`

loop=`losetup -f` # dunno how I can avoid race condition here :/
losetup --offset $OFFSET $loop $FILE
echo $loop
echo "Remember to 'losetup -d $loop' after you're done."
