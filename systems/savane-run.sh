#!/bin/bash
# Start Savane image
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

## The following command uses qemu's own IP stack ('user', based on
## slirp).

# This means the host is not visible from the outside, but can connect
# to the outside (except for ping which would require qemu to run as
# root). qemu provides a fake DHCP server for the guest system, no
# configuration is needed.

# The 2 port redirections allow you to connect from the outside to the
# SSH and HTTP services. To connect via SSH, you need to set a root
# password.
# $ mybrowser http://localhost:50080
# $ ssh root@localhost -p 2222

qemu savane.img -kernel-kqemu -redir tcp:2222::22 -redir tcp:50081::80 $*

# $* allow you to pass additional qemu options when calling ./savane.sh


## With tuntap, a bridge, and a real DHCP server

# This other configuration will require root access to setup the
# network. It will create a new virtual interface for your system, and
# connect it to your local network's real DHCP server. This requires
# the 'bridge-utils' package.

# Remember to disabled network-manager (if you use it).

# You just need to copy/paste the following. 

# Setup bridge
#brctl addbr br0
#brctl setfd br0 0
#brctl sethello br0 0 #?
#ifconfig eth0 promisc up
#brctl addif br0 eth0
# Setup tuntap
#tunctl -u YOUR_USERNAME -t tap0
#ifconfig tap0 promisc up
#brctl addif br0 tap0
# Configure the bridge via DHCP
#dhclient br0
#brctl show


#qemu savane.img -kernel-kqemu -net nic -net tap,ifname=tap0,script=no


# Watch the qemu screen to see what IP it got assigned, or login and
# type 'ifconfig eth0'.

# When you're done:
#tunctl -d tap0
#ifconfig br0 down
#brctl delbr br0



# More simple tuntap with manual configuration:
#qemu savane.img -kernel-kqemu -net nic -net tap,ifname=tap0,script=no


# Variants with no graphic screen (in the background):

#qemu `pwd`/savane.img -kernel-kqemu -daemonize -vnc :0 -k fr ...
#vncviewer localhost

#qemu `pwd`/savane.img -kernel-kqemu -daemonize -nographic ...



## With UML

# This image also works with User-Mode Linux:

#./linux ubda=savane.img root=/dev/ubda1 eth0=tuntap,,,10.0.0.2 con=null con0=fd:1 con1=xterm mem=64m

# Mimic slirp default configuration:
#uml$ ifconfig eth0 10.0.2.15
#uml$ route add default gw 10.0.2.2


## With VServer

#vserver savane build -m skeleton --interface eth0:192.168.1.120
#mount -o loop,offset=32256 savane.img /vservers/savane/
#vserver savane start


## With Xen

#losetup -o 32256 /dev/loop0 savane.img
#brctl addbr br0
#brctl addif br0 eth0
#dhclient br0
#cat <<EOF > /etc/xen/savane
#kernel = "/boot/vmlinuz-2.6.18-4-xen-686"
#ramdisk = "/boot/initrd.img-2.6.18-4-xen-686"
#vif = ['bridge=br0']
#disk = ['phy:/dev/loop0,hda1,w']
#root = "/dev/hda1 ro"
#EOF
#xm create savane
##aptitude install libc6-xen
