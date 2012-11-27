#!/bin/bash
# Copyright (C) 2012 Dave Vasilevsky <dave@vasilevsky.ca>
# Licensing: Simplified BSD License, see LICENSE file


# Nice terminal tools
b=$(tput bold)
n=$(tput sgr0)
header() { printf "\n${b}${1}${n}\n\n"; }

# Unmount on error
bind_mounts="dev dev/pts sys proc"
rm_mounts() {
	header "Cleaning up chroot"
	for mt in $(echo $bind_mounts | tac -s' ') build; do
		umount chroot/$mt || true
		sleep 0.5 # Give it time...
	done
}
trap 'header "Failed!!!"; exit 1' ERR


# Get the source
ij_version=3.00
ij_name="cnijfilter-common-$ij_version"
if [ "$1" != "ROOT" ]; then
	# Available here: http://support-au.canon.com.au/contents/AU/EN/0100160604.html
	ij_src="$ij_name-1.tar.gz"
	ij_uri="http://gdlp01.c-wss.com/gds/6/0100001606/01/$ij_src"
	if [ ! -f $ij_src ]; then
		header "Downloading IJ driver source"
		wget $ij_uri
	fi
	if [ ! -d $ij_name ]; then
		header "Extracting driver source"
		tar xf $ij_src
		
		header "Patching driver"
		for patch in patch/*; do
			echo Applying $(basename $patch)
			patch -d $ij_name -p1 < $patch
		done
	fi
fi


# Run as root
if [ $UID != 0 ]; then
	header "Becoming root, to build/install packages"
	exec sudo $0 ROOT
fi


# Create a chroot
if ! ls *.deb >& /dev/null; then
	if [ ! -d "chroot" ]; then
		if ! which debootstrap >&/dev/null; then
			header "Installing debootstrap"
			apt-get -y install debootstrap
			apt-mark auto debootstrap # autoremovable
		fi
		suite=$(lsb_release -sc)
		header "Creating chroot"
		debootstrap --verbose --variant=buildd --arch=i386 $suite \
			./chroot $debootstrap_mirror \
			|| (sudo rm -rf chroot; false EndWithError)
	fi

	header "Configuring chroot"
	cp /etc/hosts /etc/resolv.conf chroot/etc/
	# Don't install extra packages
	cat > chroot/etc/apt/apt.conf.d/recommends <<EOF
APT::Install-Recommends "0";
APT::Install-Suggests "0";
EOF

	trap 'rm_mounts' EXIT
	for mt in $bind_mounts; do
		mount -o bind /$mt chroot/$mt
	done
	mkdir -p chroot/build
	mount -o bind $ij_name chroot/build # Make source available in chroot

	old_locale=$LC_ALL
	export LC_ALL=C # no locale errors


	header "Installing build dependencies"
	ij_bdeps="build-essential debhelper automake libtool libcups2-dev libpopt-dev libtiff5-dev libpng12-dev libgtk2.0-dev libxml2-dev"
	chroot chroot apt-get -y install $ij_bdeps

	header "Building driver package"
	chroot chroot sh -c "cd /build && dpkg-buildpackage -b"
	ln --target-directory=. chroot/*.deb
	
	trap - EXIT
	rm_mounts
fi

check_pkg() {
	dpkg-query -Wf '${db:Status-Abbrev}' $1 2>/dev/null | grep -q ii
}

# Install packages
header "Installing driver package"
pkg=cnijfilter-mp630series
if ! check_pkg $pkg; then
	if ! ls *.deb >& /dev/null; then
		echo "No packages were built!"; false
	fi
	if ! dpkg -i *.deb >&/dev/null; then
		apt-get -fy install
	fi
fi

if ! check_pkg cups-bjnp; then
	header "Installing network protocol support from PPA"
	apt-add-repository -y ppa:robbiew/cups-bjnp
	apt-get update
	apt-get install -y cups-bjnp
fi


header "Success!"

echo "You may now setup your printer. The printer may take a minute to show up in the Add Printer dialog."
if which system-config-printer >&/dev/null; then
	system-config-printer
fi

echo
echo "Now that your driver is installed, feel free to delete this directory."

