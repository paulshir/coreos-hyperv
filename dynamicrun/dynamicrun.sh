#! /bin/bash
#

sleep 10

if [[ -f /media/dynamicrun/cloud-config.yaml ]];
then
	coreos-install -d /dev/sda -C alpha -c /media/dynamicrun/cloud-config.yaml
else
	coreos-install -d /dev/sda -C alpha
fi