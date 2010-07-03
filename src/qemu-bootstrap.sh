#!/bin/bash -x
# Builds a Debian disk image suitable for QEMU or UML
# Copyright (C) 2007, 2009, 2010  Sylvain Beucler
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

# Dependencies: makedev, debootstrap

# Default values for command-line parameters
default_disk_image='debian.img'
default_disk_size=2048 # 2GB
default_debian_distro='lenny'
default_debian_mirror='http://ftp.fr.debian.org/debian/'
default_partition_fs='ext3' # can also be reiserfs
default_disk_style='disk' # or single_partition
default_disk_guest_device='hda' # or ubda for UML

if [ "$1" = '--help' -o "$1" = '-h' ]; then
    echo "Usage:   $0 disk_image disk_size \\
            debian_distro debian_mirror \\
            partition_fs [disk|single_partition] disk_guest_device";
    echo "Default: $0 $default_disk_image $default_disk_size \\
            $default_debian_distro $default_debian_mirror \\
            $default_partition_fs $default_disk_style $default_disk_guest_device";
    echo "UML:     $0 $default_disk_image $default_disk_size \\
            $default_debian_distro $default_debian_mirror \\
            $default_partition_fs single_partition ubda";
    exit;
fi

if [ "$1" = '--version' ]; then
    echo "bootstrapX v0
Copyright (C) 2007, 2009, 2010  Sylvain Beucler
This is free software.  You may redistribute copies of it under the terms of
the GNU General Public License <http://www.gnu.org/licenses/gpl.html>.
There is NO WARRANTY, to the extent permitted by law."
    exit;
fi

# Get parameters
disk_image=${1:-$default_disk_image}
disk_size=${2:-$default_disk_size}
debian_distro=${3:-$default_debian_distro}
debian_mirror=${4:-$default_debian_mirror}
partition_fs=${5:-$default_partition_fs}
disk_style=${6:-$default_disk_style}
disk_guest_device=${7:-$default_disk_guest_device}

echo "* Creating filesystem image"
# Mount directory
target=`mktemp -d -t $disk_image.XXXXXXXXXX`/mp || exit 1
mkdir $target

offset=0
if [ "$disk_style" = "disk" ]; then
    `dirname $0`/createdisk.sh $disk_image $disk_size $partition_fs
    # This doesn't have ext3 support :/
    # But fun :)
    # parted $disk_image check 1

    # Mount the first disk partition - skipping the first track
    # cf. createdisk.sh
    # alternate solution: lomount.sh
    BLOCKSIZE=512
    SECTORS=63
    offset=$(( $SECTORS * $BLOCKSIZE ))
else
    # Beware, bs has a 2GB limit; using seek instead:
    dd if=/dev/null of=$disk_image count=0 bs=1M seek=${disk_size}
    if [ "$partition_fs" = "reiserfs" ]; then
	mkfs.reiserfs -q $disk_image
    else
	mkfs.$partition_fs -F $disk_image
    fi
fi

mount -o loop,offset=$offset $disk_image $target/
if [ $? -ne 0 ]; then
    echo "* Unable to mount the disk image - stopping."
    exit 1
fi

echo "* Debootstrap"
debootstrap $debian_distro $target/ $debian_mirror
# Note: there's no need to trim the packages used by debootstrap
# anymore, it already uses a minimal number of packages. We could
# remove libsasl2 and libconsole manually but it doesn't worth the
# effort IMHO.

if [ $? -ne 0 ]; then
    echo "* debootstrap failed - stopping."
    exit 1
fi


# fake fstab so that filesystems are setup next boot (and df works)
device=$disk_guest_device
if [ "$disk_style" = "disk" ]; then
    device="$device"1 # hda1, udba1
fi
# else: only one partition mounted as full disk: hda, udba
cat <<EOF > $target/etc/fstab
proc		/proc	proc	defaults	0 0
/dev/$device	/	auto	defaults	0 1
EOF
# Only for ext3:
#/dev/$device	/	auto	defaults,errors=remount-ro 0 1


# Access to the host filesystem:
mkdir $target/root/host/

# if [ UML ]
cat <<'EOF' >> $target/etc/fstab
# Mount the host filesystem. Use the 'hostfs' switch to specify the
# root of the hostfs (eg: ./uml debian.img hostfs=/home/me/).
none	/root/host	hostfs	/
EOF

# if [ qemu ]
cat <<'EOF' >> $target/etc/fstab
# Access to the host via Samba when using 'qemu -smb /path ...':
# (Debian users, beware: http://bugs.debian.org/249873)
//10.0.2.4/qemu	/root/host	cifs	defaults,username=%,noauto
EOF

echo "* Network configuration"
cat <<'EOF' > $target/etc/network/interfaces
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp

## UML cheat sheet
#iface eth0 inet static

## Tun/tap:
## ./uml ... eth0=tuntap,,,10.0.2.2
# address 10.0.2.15
# netmask 255.0.0.0
# gateway 10.0.2.2

## Slirp:
## ./uml ... eth0=slirp,,/usr/bin/slirp-fullbolt
# address 10.0.2.15
# netmask 255.0.0.0
# up route add default eth0
## requires 'resolvconf':
# dns-nameservers 10.0.2.3
EOF

# Host name
image_hostname=${disk_image%.img}
echo "$image_hostname" > $target/etc/hostname
# 'localhost' alias support
cat <<EOF > $target/etc/hosts
127.0.0.1       localhost.localdomain localhost $image_hostname
EOF

# Temporary DNS for this script's apt-get - final version is installed
# in the clean-up phase
cp /etc/resolv.conf $target/etc/resolv.conf

# Clean-up environment
unset DISPLAY LANGUAGE LC_ALL LANG

echo "* Additional components"
#automatically clean downloaded packages to save space
echo 'DSelect::Clean "always";' >> /etc/apt/apt.conf.d/00aptitude

#chroot $target aptitude -q update
chroot $target apt-get update
DEBIAN_FRONTEND=noninteractive chroot $target aptitude --assume-yes install \
    console-data console-common emacs21-nox less openssh-server
if [ $default_partition_fs = "reiserfs" ]; then
    DEBIAN_FRONTEND=noninteractive chroot $target aptitude --assume-yes install \
	reiserfsprogs
fi
# Enable indispensable Emacs options
cat <<EOF >> $target/root/.emacs
(custom-set-variables
  ;; custom-set-variables was added by Custom -- don't edit or cut/paste it!
  ;; Your init file should contain only one such instance.
 '(global-font-lock-mode t nil (font-lock))
 '(show-paren-mode t nil (paren))
 '(transient-mark-mode t))

;; Support accents
(set-terminal-coding-system 'utf-8)
(set-keyboard-coding-system 'utf-8)
(prefer-coding-system 'utf-8)
EOF
# Enable colors and aliases in bash
cat <<'EOF' > $target/root/.bashrc
# ~/.bashrc: executed by bash(1) for non-login shells.

export PS1='\h:\w\$ '
umask 022

# You may uncomment the following lines if you want `ls' to be colorized:
export LS_OPTIONS='--color=auto'
eval "`dircolors`"
alias ls='ls $LS_OPTIONS'
alias ll='ls $LS_OPTIONS -l'
alias l='ls $LS_OPTIONS -lA'
#
# Some more alias to avoid making mistakes:
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'
EOF


# Create a bootable disk
if [ $disk_style = 'disk' ]; then

    echo "* Kernel"
    # We install a custom kernel by default, because there's a number
    # of issues when installing the Debian kernel:
    # - It creates an initrd image, based on inspecting the
    #   installer's kernel/hardware configuration, rather than the -
    #   target configuration (typically QEMU)
    # - We can't skip the initrd image (kernel panic when mounting
    #   root fs) probably because the Debian kernel is very modular
    #   and needs to load module to access even the QEMU IDE disk.
    # - With all the virtual mounts, update-grub usually can't work
    #   and is pretty strict, so it will abort and make the package
    #   post-configuration fail
    cp bzImage $target/boot/
    rdev $target/boot/bzImage 03,01 # boot /dev/hda1 by default
    
    echo "* Boot loaders"
    DEBIAN_FRONTEND=noninteractive chroot $target aptitude --assume-yes install \
	lilo grub grub-splashimages
    
    # Using clocksource=pit as per qemu-doc.html §3.11.1:
    #"When using a 2.6 guest Linux kernel, you should add the option
    # clock=pit on the kernel command line because the 2.6 Linux
    # kernels make very strict real time clock checks by default that
    # QEMU cannot simulate exactly."

    # LILO
    cat > $target/etc/lilo.conf <<EOF
boot=/dev/hda
append="clocksource=pit"
prompt
timeout=50
bitmap=/boot/coffee.bmp
root=current

image=/boot/bzImage
  label=Debian_${debian_distro}
EOF
    # I can't install LILO from outside QEMU :'(
    # I'd need to forge a /boot/map...

    # Or, we could run the image, put it on the network, prepare SSH
    # access and install it from within the emulator. That doesn't
    # work with UML: both LILO and GRUB don't know how to handle
    # /dev/ubda, with and without the 'fake_ide' switch. Better try
    # with bare QEMU+SSH somehow.

    # Alternatively we could implement disk image support in a
    # bootloader.

    # Or, we can use GRUB and manually mess with the boot
    # sectors. Tough, but doable:
    cat > $target/boot/grub/menu.lst <<EOF
default 0
timeout 5
#color cyan/blue white/blue
### BEGIN AUTOMAGIC KERNELS LIST
### END DEBIAN AUTOMAGIC KERNELS LIST

title  ${disk_image%.img} - Debian GNU/Linux "$debian_distro"
root   (hd0,0)
kernel /boot/bzImage root=/dev/hda1 clocksource=pit
EOF
# Prepare for stock kernel installations:
cat <<EOF >> $target/etc/kernel-img.conf
postinst_hook = update-grub
postrm_hook   = update-grub
do_initrd     = yes
EOF
    #chroot $target cp /usr/lib/grub/i386-pc/stage2 /boot/grub/ \
    #	|| chroot $target cp /lib/grub/i386-pc/stage2 /boot/grub/
    grub_arch=i386-pc
    cp $target/usr/lib/grub/i386-pc/stage[12] $target/boot/grub
    cp $target/usr/lib/grub/i386-pc/*stage1_5 $target/boot/grub
    sync

    chroot $target ln -s splashimages/debsplash.xpm.gz /boot/grub/splash.xpm.gz 
    # It's a bit messy, but you'll perform a clean 'grub-install /dev/hda' later
    chroot $target update-grub

    # Real works begins...
    echo "* Forging GRUB installation on the MBR"
    # Obsolete: `dirname $0`/grub.sh $disk_image $partition_fs
    tmp_device_map=$(mktemp)
    echo "(hd0) $disk_image" > $tmp_device_map
    echo -e "root (hd0,0)\nsetup (hd0)" \
      | $target/usr/sbin/grub --device-map=$tmp_device_map --batch
    rm -f $tmp_device_map
fi



echo "* Populating /dev"
# -> because I lack /dev/hda after reboot with a Debian guest.
#    TODO: why was that an issue? Just to install the bootloader?
# Maybe installing udev would be better?
# Or restricting to hda/tty/other_basic_stuff only.
mount procfs -t proc $target/proc # needed by MAKEDEV
#chroot $target bash -c 'cd dev && ./MAKEDEV generic-i386'
#chroot $target bash -c 'cd dev && ./MAKEDEV std pty tty1..8' # rootstrap
chroot $target bash -c 'cd dev && MAKEDEV std console pty fd'
# For UML
chroot $target bash -c 'cd dev && MAKEDEV ubd'
# For QEMU
chroot $target bash -c 'cd dev && MAKEDEV fd0 hda hdc'

echo "* Clean-up"
chroot $target aptitude clean
# 10.0.2.2 is the host machine in QEMU -net user mode (i.e. slirp)
sed -i -e 's/localhost/10.0.2.2/' $target/etc/apt/sources.list

# Common-case resolv.conf - replace the current one that was just needed 
# Predefine DNS for slirp (useful in UML where there's no builtin DHCP)
# Use DNS redirection 10.0.2.3
cat <<'EOF' > $target/etc/resolv.conf
# Added by qemu-bootstrap. This is usually overwritten by dhclient.
nameserver 10.0.2.3
# Alternatively run your own bind in the guest:
# nameserver 127.0.0.1
EOF

# Shutdown newly installed servers
for i in `cd $target && ls etc/rc2.d/*`; do
    if [ -x $target/$i ]; then
	chroot $target $i stop
    fi
done

umount $target/proc
umount $target


# post-install:
# 'dpkg-reconfigure console-data' to select keymap!
#   - not needed for UML?
# 'tzconfig' to select timezone
# 'lilo' to install the boot loader and replace grub if you want

# 'dd if=/dev/null of=hda.img seek=2000000...000 bs=1024' grows the
# disk image, just restart the guest to take it into account and add
# new partitions.

# TODO: ideas from qemu-make-debian-root
# 
# - Copy files passed as parameter in the root (or maybe we'll rather
# want to provide a command for the user to do that himself whenever
# he wants)
# 
# - Useful? It alters an existing empty partition - doesn't create a new one:
## Repartition so one partition covers entire disk.
#echo '63,' | sfdisk -uS -H$HEADS -S$SECTORS -C$CYLINDERS $IMAGE
#
# - hostname=_dirname_(image)
#
# - Create /etc/shadow if needed: pwconv
#
# - trap cleanup EXIT / trap "" EXIT
#   (cleanup clear mounts)
