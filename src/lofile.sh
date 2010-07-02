#!/bin/bash
# Detect the filesystem of a disk image partition
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

UNITS=`fdisk -lu $FILE 2>/dev/null | grep $FILE$PART | tr -d '*' | tr -s ' ' | cut -f2 -d' '`
# With less than 3*512 file cannot determine the filesystem type
magic=`dd if=$FILE skip=$UNITS bs=512 count=3 2>/dev/null | file -`

#/dev/stdin: Linux rev 1.0 ext2 filesystem data (large files)
#/dev/stdin: Linux rev 1.0 ext3 filesystem data (large files)
#/dev/stdin: ReiserFS V3.6 block size 4096 num blocks 792840 r5 hash
if echo $magic | grep -q 'ext2 filesystem'; then
    echo ext2
elif echo $magic | grep -q 'ext3 filesystem'; then
    echo ext3
elif echo $magic | grep -q 'ReiserFS'; then
    echo reiserfs
else
    echo UNKNOWN
    exit 1
fi
