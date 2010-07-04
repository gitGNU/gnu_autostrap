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

ln -sf debian-gnu.xpm.gz /boot/grub/splash.xpm.gz
sed -i -e 's:^### BEGIN AUTOMAGIC KERNELS LIST.*:&\nsplashimage=(hd0,0)/boot/grub/splash.xpm.gz:' /boot/grub/menu.lst
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
cd /usr/src/
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
# Use 'noninteractive' to avoid being prompted 4x for a MySQL password
DEBIAN_FRONTEND=noninteractive aptitude --assume-yes install apache2 libapache2-mod-php5 mysql-server php5-mysql
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
<?php
// Empty file, using default configuration.
EOF
cat <<'EOF' > /etc/cron.d/savane
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
* * * * *      root    sv_groups --cron && sv_users --cron
EOF
mkdir /srv/cvs /srv/svn /srv/git /srv/hg

# Hacking
aptitude install php-elisp


# Savane framework
cd /usr/src/
apt-get install python-mysqldb
git clone git://git.sv.gnu.org/savane-cleanup/framework.git
# Too big (87MB vs. 29MB extracted tarball)
#svn checkout http://code.djangoproject.com/svn/django/branches/releases/1.2.X django
wget http://www.djangoproject.com/download/1.2.1/tarball/
tar xzvf Django-1.2.1.tar.gz
# Linking to the current installation directly:
#python setup.py install
ln -s /usr/src/Django-1.2.1/django /usr/lib/python2.5/

cd framework/
mysql -e "CREATE DATABASE savane_framework DEFAULT CHARACTER SET utf8;"
echo 'from settings_default import *' > settings.py
cat <<EOF >> settings.py
DATABASES = {
    'default': {
        'NAME': 'savane_framework',
        'ENGINE': 'django.db.backends.mysql',
        'USER': 'root',
        'PASSWORD': '',
    }
}
EOF
./manage.py syncdb --noinput


cd /usr/src/
echo <<EOF > README
'savane' is the current PHP+Perl version.
'framework' is the next Python/Django implementation.
EOF
