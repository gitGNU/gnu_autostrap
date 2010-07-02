#!/bin/bash
#aptitude install bridge-utils uml-utilities
#qemu debian.img -kernel-kqemu -net nic -net tap,ifname=tap0,script=no

function setup_tap {
    tap=$1
    tunctl -u sylvain -t $tap
    ifconfig $tap promisc up
    brctl addif br0 $tap
}

tunctl -d tap0
tunctl -d tap1
tunctl -d tap2
ifconfig br0 down
brctl delbr br0

brctl addbr br0
brctl setfd br0 0
brctl sethello br0 0 #?
ifconfig eth0 promisc up
brctl addif br0 eth0
setup_tap tap0
setup_tap tap1
setup_tap tap2
dhclient br0
brctl show
