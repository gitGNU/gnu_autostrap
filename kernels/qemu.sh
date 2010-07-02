#!/bin/bash -ex
# Autobuild a minimal kernel for the default QEMU/i386 VM
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

VERSION=2.6.21.5
if [ ! -e linux-$VERSION.tar.bz2 ]; then
    wget http://kernel.org/pub/linux/kernel/v2.6/linux-$VERSION.tar.bz2
fi
rm -rf linux-$VERSION-qemu
tar xjf linux-$VERSION.tar.bz2
mv linux-$VERSION linux-$VERSION-qemu

pushd linux-$VERSION-qemu

cp ../allno.config .
make allnoconfig
make
cp arch/i386/boot/bzImage ..

popd
