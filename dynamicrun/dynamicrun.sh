#! /bin/bash
#

if [[ -f /media/dynamicrun/static.network ]];
then
	cp /media/dynamicrun/static.network /etc/systemd/network/static.network
	systemctl restart systemd-networkd
fi

if [[ -f /media/dynamicrun/cloud-config.yaml ]];
then
	coreos-install -d /dev/sda -C alpha -c /media/dynamicrun/cloud-config.yaml
else
	coreos-install -d /dev/sda -C alpha
fi