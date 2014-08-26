coreos-hyperv
=============

A repository with some basic scripts to set up coreos hypev clusters.

## How to use ##
### Prerequisites ###
Windows 8.1 and Hyper-V turned on.
Internet Connection
At least one virtual switch created in hyper-v

### Create a simple cluster with no config ###
From an Admin Powershell Window import the powershell module `Import-Module coreos-hyperv.psm1`

Run the command `New-CoreosCluster -Name:"Coreos-Cluster1" -NetworkSwitchNames:"External Virtual Switch 1" -Count:3 -InstallInParallel:$true` 

This will install 3 vms in a cluster. However without a config it isn't much use as you won't have set any credentials to actually use the machines. See some of the sample configs to get up and running with a useable cluster.

## Auto Install Process ##
The auto install process works by doing the following. I didn't have an easy way to create iso's with powershell so I created a generic one which calls a script on boot.
1. Creating a new vm with the following:
    a. coreos iso as boot device
    b. vhd for the installation
    c. dynamicrun iso with config-2 label
    d. dynamicrun vhdx with install script and cloud configs

## Limitations ##
### Unable to track install ###
Currently I have no way of tracking the progress of the installation from powershell. I've set a hard time out which works if the install script works.
It is advisable to check the install (when powershell starts the time remaining segement of the install.) by doing the following.

Open Hyper-V Manager
Connect to a VM
Enter the following command
```
systemctl status dynamicrun.service
```
If it has failed it will show the error messages in red. Otherwise it is installing. This command will show the output from the install.

You can check the status of the network with `ifconfig`

### Static Networking doesn't work for installing a cluster in parallel ###
If for some reason dhcp doesn't work in the install then you might need to configure a static network during the install. Currently there is no way to specify different IP addresses per vm in the cluster for the install so instead just run the cluster install not in parallel. This should prevent IP address clashes.

### Each install downloads the image ###
It doens't take long to download so not that big of an issue.