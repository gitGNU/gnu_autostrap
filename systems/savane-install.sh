#!/bin/bash
# Unattended Savane test install
# 
# Copyright (C) 2007, 2008, 2010  Sylvain Beucler
# 
# This file is part of Savane.
# 
# Savane is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation, either version 3 of the
# License, or (at your option) any later version.
# 
# Savane is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
# 
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

## SSH issues
export LANG=C

## Base system
aptitude update # we may have modified sources.list in the clean-up phase

# aptitude: Do not treat Recommended packages as dependencies:
echo 'Aptitude::Recommends-Important "false";' >> /etc/apt/apt.conf.d/00aptitude  # etch
echo 'APT::Install-Recommends "false";' >> /etc/apt/apt.conf.d/00recommends  # lenny


# GNU logo on startup
aptitude --assume-yes install grub-splashimages 

wget http://ruslug.rutgers.edu/~mcgrof/grub-images/images/working-splashimages/debian-gnu.xpm.gz -P /boot/grub/splashimages/
ln -sf /boot/grub/splashimages/debian-gnu.xpm.gz /boot/grub/splash.xpm.gz
update-grub

# VServer test:
#aptitude --assume-yes install util-vserver
#vserver test build -m debootstrap -- -d lenny -m http://10.0.2.2/mirrors/debian
#echo 101 > /etc/vservers/test/context


## Mail server for Aleix
DEBIAN_FRONTEND=noninteractive aptitude install --assume-yes postfix

## Additional SCMs
echo "deb http://www.backports.org/debian lenny-backports main" > /etc/apt/sources.list.d/backports.org.list
wget -O - http://backports.org/debian/archive.key | apt-key add -
aptitude update
# First install with Stable dependencies
aptitude --assume-yes install cvs subversion git-core mercurial
# Then upgrade with Backports.org versions
aptitude --assume-yes install -t lenny-backports git-core mercurial


## Savane
cd /usr/src
git clone git://git.sv.gnu.org/savane-cleanup.git savane
cd savane
aptitude --assume-yes install autoconf automake make \
  mysql-client imagemagick gettext rsync
./bootstrap
./configure.sh
make
make install

# Savane frontend
# Skip networking, so it doesn't attach to 127.0.0.1:3306, and thus
# can be used in a chroot when the host already has another mysqld
# running
mkdir -p /etc/mysql/conf.d
cat <<EOF > /etc/mysql/conf.d/skip-networking.cnf
[mysqld]
skip-networking
EOF
aptitude --assume-yes install apache2 libapache2-mod-php5 mysql-server php5-mysql
make database
ln -s /usr/src/savane/frontend/php /var/www/savane
cat <<EOF > /etc/apache2/conf.d/savane.conf
<Directory "/var/www/savane/">
  AllowOverride All
</Directory>
EOF
# Remove default homepage
rm /var/www/index.html
invoke-rc.d apache restart

# Savane backend
aptitude --assume-yes install libmailtools-perl libdbd-mysql-perl \
  libxml-writer-perl libfile-find-rule-perl libterm-readkey-perl \
  libdate-calc-perl libstring-random-perl
cat <<'EOF' > /etc/savane/savane.conf.pl
our $sys_dbhost="localhost";
our $sys_dbname="savane";
our $sys_cron_users="yes";
our $sys_cron_groups="yes";
our $sys_homedir="/home";
EOF
cat <<'EOF' > /etc/savane/.savane.conf.php
// Empty file, using default configuration.
EOF
cat <<'EOF' > /etc/cron.d/savane
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * *      root    sv_groups --cron && sv_users --cron
EOF
mkdir /srv/cvs /srv/svn /srv/git /srv/hg

# Hacking
aptitude install php-elisp
