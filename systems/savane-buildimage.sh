#!/bin/bash -xe
# Build a Savane test install qemu image automatically
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

function mount_image {
    image=$1
    target=`mktemp -d -t $image.XXXXXXXXXX`/mp || exit 1
    # mountpoint in a subdir of a 700 directory, so nobody can mess
    # with (say) /tmp while we work in it
    mkdir $target
    #<sudo>
    lomount.sh $image 1 $target || exit 1
    #</sudo>
    echo $target
}

function start_image {
    image=$1
    target=$(mount_image $image)
    #<sudo>
    # Temporary DNS for this script's apt-get - final version is installed
    # in the clean-up phase
    cp $target/etc/resolv.conf $target/etc/resolv.conf.bak
    cp /etc/resolv.conf $target/etc/resolv.conf
    
    # Clean-up environment
    unset DISPLAY LANGUAGE LC_ALL LANG
    
    mount proc -t proc $target/proc
    mount devpts -t devpts $target/dev/pts
    mount sysfs -t sysfs $target/sys

    chroot $target /etc/init.d/sysklogd start
    # Maybe too much:
    #for i in /etc/rc2.d/*; do $i start; done
    #</sudo>
}

function stop_image {
    #<sudo>
    # Restore resolv.conf
    cp $target/etc/resolv.conf.bak $target/etc/resolv.conf

    # Shutdown newly installed servers
    for i in `cd $target && ls etc/rc2.d/*`; do
	if [ -x $target/$i ]; then
	    chroot $target $i stop
	fi
    done
    chroot $target aptitude clean
    umount $target/sys
    umount $target/dev/pts
    umount $target/proc
    #</sudo>
    umount_image
}

function umount_image {
    #<sudo>
    umount $target
    #</sudo>
    rmdir $target
}

function copy_in {
    dest_dir=$1
    shift
    #<sudo>
    cp $* $target$dest_dir
    #</sudo>
}

image=savane.img

echo "* Initial image"
#<sudo>
#./qemu-bootstrap.sh $image 2048 lenny http://10.0.2.2/mirrors/debian/ ext3 disk hda
qemu-bootstrap.sh $image 2048 lenny http://network/mirrors/debian/ ext3 disk hda
# With a apt-proxy:
#./qemu-bootstrap.sh $image 2048 lenny http://10.0.2.2:9999/debian/ ext3 disk hda
#</sudo>

echo "* Mount image"
start_image $image

echo "* Copy installation files"
copy_in /root savane-install.sh

echo "* Start installation"
#<sudo>
chroot $target sh /root/savane-install.sh
#</sudo>
# Note: using umdo.sh for this task doesn't always work - sometimes
# the mysql installation gets stuck and I don't know why :(

echo "* Unmounting image"
stop_image

echo 'Now: ./savane.sh'
