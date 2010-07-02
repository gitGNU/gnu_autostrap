#!/bin/bash
# Notes:
# - kernel-parameters: a dot -> module.param notation -> not included in $*
# - kernel-parameters: $* contains params that the kernel did not recognized
# - Cf. /proc/cmdline for the complete command-line though
# - $PWD becomes /
# - init specifies the full path to an executable, either binary or script
/usr/src/linux-2.6.20-um/linux rootfstype=hostfs rw eth0=slirp,,/usr/bin/slirp-fullbolt init=`pwd`/uml2.sh

## - Console control -
## No C-c C-\ C-z:
# /usr/src/linux-2.6.20-um/linux rw rootfstype=hostfs quiet init=/bin/bash
## getty supports C-c and C-\, but not C-z (and I don't have a clue why):
# /usr/src/linux-2.6.20-um/linux rw rootfstype=hostfs quiet init=/sbin/getty -inl /bin/bash 38400 tty0
