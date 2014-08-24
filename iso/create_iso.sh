#! /bin/bash
#
#Create a cloud config iso

if [[ -f config2.iso ]];
then
	rm config2.iso
fi

mkdir -p /tmp/config2/openstack/latest
cp user_data /tmp/config2/openstack/latest/user_data
mkisofs -R -V config-2 -o config2.iso /tmp/config2
rm -r /tmp/config2
