#!/bin/bash
# 'sudo' with User-Mode Linux flavor
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

# Run the command as root using UML.
# Similar to sudo, but in user mode.
# e.g.: useful to loop-mount disk images w/o root access

# Note: your environment&mounts are _not_ saved between successive
# invokations. We might do that by saving /proc/mounts before killing
# UML, or by letting an initial UML run in background, connected via a
# Unix socket or SSH to accept and execute successive commands (+
# might be more efficient).

# DON'T RUN AS ROOT - it will among others mess with your /etc/mtab

# Dependencies: slirp (fullbolt version), xterm, /dev/console

# Debian paths in 'user-mode-linux' package:
UML=linux.uml # in /usr/bin
if ! which $UML > /dev/null; then
    echo "linux.uml cannot be found in PATH"
    exit 1
fi
MOD_PATH=/usr/lib/uml/modules/`$UML --version`/

#UML=/usr/src/linux-2.6.21.5-um/linux
#MOD_PATH=/usr/src/linux-2.6.21.5-um/uml-modules/lib/modules/`$UML --version`/

SLIRP=/usr/bin/slirp-fullbolt

verbose=0
debug=0

# Add */sbin paths before the */bin ones
function add_sbin_path {
    PATH=`echo $PATH | sed \
      -e 's,\(^\|:\)/bin\(:\|$\),\1/sbin:/bin\2,' \
      -e 's,\(^\|:\)/usr/bin\(:\|$\),\1/usr/sbin:/usr/bin\2,' \
      -e 's,\(^\|:\)/usr/local/bin\(:\|$\),\1/usr/local/sbin:/usr/local/bin\2,'`
}

init=`mktemp` || exit 1
rc=`mktemp` || exit 1
quiet_slirp=`mktemp` || exit 1
ret_val_dump=`mktemp` || exit 1
chmod 755 $init $rc $quiet_slirp
add_sbin_path;


# Use getty to get Ctrl+C support (?)

# Apparently /dev/console intercepts signals like 'intr' (maybe so
# that init cannot be killed from the keyboard), we need to switch to
# /dev/tty0 (or tty1 if we're in non-verbose mode). We can check which
# tty is used using the 'tty' command in a UML'd bash.

if [ $verbose -eq 1 ]; then
    echo '#!/bin/sh -x' > $init
else
    echo '#!/bin/sh' > $init
fi
# Previous working attempt with getty
#echo "exec /sbin/getty -inl $init_script2 38400 tty0" >> $init
# (Now we just need to use setsid.)

# setsid is somehow necessary to really attach the terminal to ttyX in
# $rc (otherwise, no C-c, C-\, etc.); this is probably related to the
# concept of controlling terminal.  Don't exec, otherwise setsid will
# need to fork first (pgrp==pid) and init/UML will finish.
echo "setsid $rc" >> $init

# 'exit $?' doesn't seem to work, the UML return code is whether init
# just ended or called shutdown, not related to the init return
# value. So we send it to a file.
echo "echo \$? >$ret_val_dump" >> $init

# Quiet halt - shut down UML w/o ugly kernel trace. 
# Note: unfortunately 'halt' takes ~2s.
# Isn't there a way to suppress kernel ending messages ("Kernel panic
# - not syncing: Attempted to kill init!" and "System halted.")?
# --> Actually not necessary since con0=null, disabled.
# Only, UML exits 1 when init ends, and 0 when properly shutdown
cat <<EOF >> $rc
#echo "Halting system..."
#halt -d -f # as in /etc/init.d/halt
EOF

# $init ends here, UML gets a kernel panic because of that - but we
# don't care, UML exists faster that way.



## Generate a script that mimics the current user's environment and
## launch the command specified as parameter
if [ $verbose -eq 1 ]; then
    echo '#!/bin/sh -x' > $rc
else
    echo '#!/bin/sh' > $rc
fi
# Attach to ttyX because /dev/console is blocking signals (C-c, etc.):
# /!\ bash analyses std*err* to find the controlling terminal,
# so essentially stdin and stderr need to use the same tty,
# otherwise this will break job control %-)
# Alternatively we could, as ssh, avoid splitting stdout and stderr
# for interactive shells.
if [ $verbose -eq 1 ]; then
    echo "exec </dev/tty0 2>/dev/tty0 >/dev/tty2" >> $rc
else
# we quiet UML some more with con0=null, so we use tty1 instead of tty0
    echo "exec </dev/tty1 2>/dev/tty1 >/dev/tty2" >> $rc
fi

# Forward environment
# TODO: escape <'> in the variable values
# Note: default env is HOME=/,TERM=linux (not even PATH is set/exported)
env | sed -e "s/^/export /" -e "s/=/='/" -e "s/\$/'/" >> $rc

# X11: distros usually configure X to listen on a socket such as
# /tmp/.X11-unix/X0, with networking (localhost:6000)
# disabled. Unfortunately UML does not share sockets with the host.
# What we need is something like SSH's ForwardX11, with a process
# listening on uml:6000 and forward packers to the host's X11 socket.

# Pseudo filesystems
cat <<EOF >> $rc
mount procfs -t proc /proc
mount devptsfs -t devpts /dev/pts # devpts requires proc, apparently (screen)
EOF

# Note: I tried:
#mount -o bind -n /proc/mounts /etc/mtab
# but since /proc/mounts (or /proc/self/mounts) is a special file, I just get:
#cat: /etc/mtab: Invalid argument
# Plus mount(8) doesn't really recommend it, only when efficiency is necessary.

# I also tried to replace /etc/mtab by a writable copy:
#cat <<'EOF' >> $rc
#workdir=`mktemp -d`
#cp /etc/mtab $workdir/mtab
#mount -o bind -n $workdir/mtab /etc/mtab
#EOF
# But then we get:
#can't create lock file /etc/mtab~730:
#Permission denied (use -n flag to override)
# So let's forget about it.


# Load 'mount -o loop' support
cat <<EOF >> $rc
mount none -t tmpfs /lib/modules/
mkdir /lib/modules/\`uname -r\`/
mount -o bind $MOD_PATH /lib/modules/\`uname -r\`/
# Test if loop is already available (statically compiled?)
if losetup -f >/dev/null 2>/dev/null; then
:
else
  # built as module, try to load it
  modprobe loop
fi
EOF
#insmod $MOD_PATH/drivers/block/loop.ko
# What happens if the module is compiled statically?
# -> FATAL: Module loop not found.
# Does it still provide several /dev/loopX?
# -> Yes, no problem.


# Network
cat <<EOF >> $rc
ifconfig eth0 10.0.2.15
route add default eth0
# Optional:
ifconfig lo up
EOF

# We may want to redirect all traffic from localhost to 10.0.2.2
# though this will probably prevent from binding a temporary server;
# is there a way to redirect traffic to the host only if the guest
# didn't open it (overlay-style)?

# TESTME: Should we really set the UML host name?
echo "hostname `hostname`" >> $rc


# Working directory
echo "cd `pwd`" >> $rc

if [ $debug -eq 1 ]; then
    # Start a separate console for debugging if need be (eg. when the
    # main script is frozen).
    # TODO: C-c works for bash, but not for other programs (eg. 'cat'
    # and 'sleep')
# W/o C-c:
#    echo "setsid /bin/bash </dev/tty6 >/dev/tty6 2>/dev/tty6 &" >> $rc
# With C-c!!!
#    echo "(setsid /bin/bash </dev/tty6 >/dev/tty6 2>/dev/tty6)&" >> $rc
# With C-c (but blocking):
#    echo "setsid /bin/bash </dev/tty6 >/dev/tty6 2>/dev/tty6" >> $rc
#    echo "(setsid /bin/bash </dev/tty6 >/dev/tty6 2>/dev/tty6)" >> $rc
# W/o C-c:
#    echo "bash -c 'setsid /bin/bash </dev/tty6 >/dev/tty6 2>/dev/tty6&'" >> $rc
# With C-c:
#    echo "while true; do setsid /bin/bash < /dev/tty6 > /dev/tty6 2>/dev/tty6; done&" >> $rc
# With C-c:
    echo "while true; do (echo 'Debug Console:'; setsid /bin/bash) < /dev/tty6 > /dev/tty6 2>/dev/tty6; done&" >> $rc
fi

# Actual command
echo "$*" >> $rc
# Grab the return code
echo 'ret=$?' >> $rc

# Clean-up filesystems
cat <<EOF >> $rc
umount /lib/modules/\`uname -r\`/
umount /lib/modules/
umount /proc
umount /dev/pts
EOF

# Forward the command return code
echo 'exit $ret' >> $rc


# Make slirp less noisy on startup
echo '#!/bin/bash' > $quiet_slirp
echo "exec $SLIRP 2>/dev/null" >> $quiet_slirp


# What happens after the kernel is loaded:
# - kernel-parameters: a dot -> module.param notation -> not included in $*
# - kernel-parameters: $* contains params that the kernel did not recognized
# - Cf. /proc/cmdline for the complete command-line though
# - $PWD becomes /
# - init specifies the full path to an executable, either binary or script

# Backup terminal parameters in case UML breaks them
if tty -s; then # we're run from a terminal
  tty_config=`stty -g`
fi


#exec 3>&0 # backup stdin
exec 4>&1 # copy stdout
#exec 5>&2 # copy stderr
#exec 6>/dev/null

# Beware the fd madness, check the comment above about bash and
# stderr.  We give stderr on the main console, and divert stdout to
# be able to get it separately (as in umdo >stdout 2>stderr)
if [ $verbose -eq 1 ]; then
    options="eth0=slirp,,$SLIRP con0=fd:0,fd:2"
else
    options="quiet con=null con1=fd:0,fd:2 eth0=slirp,,$quiet_slirp";
fi

if [ $debug -eq 1 ]; then
    options="$options con6=xterm"
fi

$UML rootfstype=hostfs rw \
    init=$init \
    $options \
    con2=fd:4 \
    mem=256m \
    >/dev/null

# >/dev/null -> avoid initial uml messages
# con0=null to get rid of kernel messages
# mem=128m just in case (default 32m)

# We want stderr separately. With UML and the terminal emulation, the
# guest's fd 1 and 2 are both sent to the host's stdout. So we pass
# stderr via con2. However this breaks job control in bash :/

#exec 0>&3 # restore stdin
#exec 1>&4 # restore stdout
#exec 2>&5 # restore stderr
#exec 3>&- # close fd3
exec 4>&- # close fd4
#exec 5>&- # close fd5
#exec 6>&- # close fd6

# UML messes with my stdin?out?err? (no echo) when using both stdout
# and stderr
if tty -s; then # this is a terminal
    #reset -I
    stty $tty_config
fi

ret=`cat $ret_val_dump`

# Clean-up
rm $init $rc $quiet_slirp $ret_val_dump
#echo "Ran $init - $rc"

# Set out error code to the user command's.
exit $ret
