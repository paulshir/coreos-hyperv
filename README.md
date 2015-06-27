coreos-hyperv
=============

These are some basic functions to help bootstrap a coreos cluster on Hyper-V.

## Prerequisites ##
Windows 8.1 or Windows Server 2012 R2 and Hyper-V turned on.   
Internet Connection.  
At least one virtual switch created in hyper-v.  
Bunzip. This is used to decompress the coreos images. There is a version of bunzip packaged with msysgit which is used if git is installed. Otherwise you can download [Bunzip for Windows](http://gnuwin32.sourceforge.net/packages/bzip2.htm) and add it to your path.  

(Although the script will work in Windows 8 and Windows Server 2012 I haven't been able to test coreos running on those platforms. Some users have had issues running in the past but this might have changed now that coreos provides images for Hyper-v.)

## Installation ##
### Clone to PSModule Path ###
From powershell run the following:

```
git clone https://github.com/paulshir/coreos-hyperv "$($env:home)\Documents\WindowsPowershell\Modules\coreos-hyperv"
Import-Module coreos-hyperv
```

## Create a basic cluster with a static network configuration ##
To create a basic cluster with a static network configuration we can do the following. First we create the network config. The following is all run from an administrator powershell prompt.

```
$NetworkConfig = New-CoreosNetworkConfig -SwitchName 'External Virtual Switch 1' -Gateway '192.168.1.1' -SubnetBits 24 -RangeStartIP '192.168.1.200' -DNSServers @('8.8.8.8', '8.8.4.4')
```

This creates a powershell variable with all the network info required to modify the configuration files with.

The next thing you need to do is to add your ssh public key to the configuration. For this example we will be using the config/basiccluster_staticnetwork.yaml file. You can generate a key with puttygen and insert the public key into the config (line 5). Now with the network config and the config file ready we can create the cluster.

```
New-CoreosCluster -Name coreos-basiccluster0 -Count 3 -NetworkConfigs $NetworkConfig -Channel Alpha -Config .\coreos-hyperv\configs\basiccluster_staticnetwork.yaml | Start-CoreosCluster
```

The following commands can now be used to stop and start a cluster.

```
$cluster = Get-CoreosCluster -ClusterName coreos-basiccluster0
$cluster | Stop-CoreosCluster
$cluster | Start-CoreosCluster
```

It is also good to ssh into the VMs and check if the cluster vms are talking to each other. You can test this by running the command `etcdctl set /foo bar`. This command should fail if the cluster isn't working properly but if it works you can ssh into another VM and run `etcdctl get /foo` to see if it has propagated. The result should be `bar`

## Configuration ##
### General Configuration ###
Included in the script are some basic template replacement handles to ease the generation of config files. This should make it easier to create configurations that can be used across multiple machines.

The Handles that are available are listed here.

`{{VM_NAME}}` The name of the vm.  
`{{VM_NUMBER}}` The number of the VM in the cluster.  
`{{VM_NUMBER_00}}` The number of the VM prefixed with a 0 if it is less that 10.  
`{{CLUSTER_NAME}}` The name of the cluster.  
`{{ETCD_DISCOVERY_TOKEN}}` Each coreos cluster generates a discovery token. This can be added to the config here.  

### Network configuration ###
In addition to the general configuration there is also the ability to configure network settings for multiple adapters.

The following handles can be used for configuring networks where X is replaced with the index of the network settings. For example for the first network configuration X would be replaced with 0 and for the second network configuration X would be replaced with 1.

`{{IP_ADDRESS[NET_X]}}` The IP Address for Network Config X. (IP Address is determined from the VM Number and the Start IP Address of the network config).  
`{{GATEWAY[NET_X]}}` The gateway for Network Config X.  
`{{DNS_SERVER_Y[NET_X]}}` The DNS Server Y for Network Config X. (Each DNS Server is represented by it's index Y).  
`{{SUBNET_BITS[NET_X]}}` The count of 1 bits in the subnet mask for Network Config X.  

## Troubleshooting ##
### Networking ###
I've found the easiest way for networking is to set up a seperate VM to act as a NAT. To do this you can use something like Windows Server or ClearOS. This way you have more control over what ip addresses your VMS are assigned etc. This also means that even if you are on different networks (i.e. when you are on a laptop in a different location) the connections and cluster will continue to work.

### Modules Functions ###
To see the functions of this powershell modules you can use the `Show-Command` powershell function. You can also find out how to use the functions using `Get-Help <Function Name>`. This will give you a description on all the parameters and options for the functions.
