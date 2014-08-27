#! /bin/bash

if [[ -f /media/dynamicrun/dynamicrun.network ]];
then
	cp /media/dynamicrun/dynamicrun.network /etc/systemd/network/dynamicrun.network
	chmod -x /etc/systemd/network/dynamicrun.network
	systemctl restart systemd-networkd
fi