#!/bin/bash
insmod /usr/src/linux-2.6.20-um/drivers/block/loop.ko

# Optional:
#mount procfs -t proc /proc
#mount devptsfs -t devpts /dev/pts # devpts requires proc, apparently (screen)
#ifconfig lo up

ifconfig eth0 10.0.2.15
route add default eth0


# Technique to override a file:
#  workir=/tmp/uml$RANDOM
#  mkdir $workdir || exit 1
#  echo "nameserver 10.0.2.3" > $workdir/resolv.conf
#  mount -o bind $workdir/resolv.conf /etc/resolv.conf
# (/etc/resolv.conf doesn't need to be altered in this case though.)

export PATH # default sh $PATH, not exported by default
            # alternatively we could grab the host $PATH somehow
cd ~sylvain/Desktop/qemu
#./qemu-bootstrap.sh debian-img 2048 etch http://192.168.1.10/mirrors/debian

#./qemu-bootstrap.sh debian.img 2047 \
#            etch http://192.168.1.63/mirrors/debian \
#            ext3 single_partition ubda

./qemu-bootstrap.sh  debian.img 2048 \
    sarge http://network/mirrors/debian/ \
    ext3 single_partition ubda

# Graceful stop:
halt -d -f # as in /etc/init.d/halt
