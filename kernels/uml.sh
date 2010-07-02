#!/bin/bash -e
# Autobuild a User-Mode Linux kernel with vital features enabled
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

#VERSION=2.6.21.5
VERSION=$(wget -q -O- http://kernel.org/pub/linux/kernel/v2.6/ \
  | grep LATEST-IS- \
  | sed -e 's/<[^>]\+>//g' -e 's/LATEST-IS-\([0-9.]\+\).*/\1/')
if [ ! -e linux-$VERSION.tar.bz2 ]; then
    wget http://kernel.org/pub/linux/kernel/v2.6/linux-$VERSION.tar.bz2
fi
rm -rf linux-$VERSION-um
tar xjf linux-$VERSION.tar.bz2
mv linux-$VERSION linux-$VERSION-um

pushd linux-$VERSION-um

export ARCH=um
sed -i -e 's/\(EXTRAVERSION = .*\)/\1-um/' Makefile
make defconfig

#make xconfig
for i in MAGIC_SYSRQ HOST_2G_2G HOSTFS X86_GENERIC; do
    sed -i -e "s/# CONFIG_$i is not set/CONFIG_$i=y/" .config
done

make
strip linux
make modules_install INSTALL_MOD_PATH=uml-modules/
unset ARCH # don't forget to clean-up environment!

popd
