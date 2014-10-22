coreos-hyperv
=============

Bootstrap a coreos cluster on Hyper-V.

### Prerequisites ###
Windows 8.1 or Windows Server 2012 R2 and Hyper-V turned on. Windows 8 and Windows Server 2012 should also work.  
Internet Connection.  
At least one virtual switch created in hyper-v.  

## Installation ##
There are two options for installing the module and Importing it.

### Clone anywhere ###
From powershell run the following:

```
git clone https://github.com/paulshir/coreos-hyperv
Import-Module .\coreos-hyperv\coreos-hyperv.psd1
```

### Clone to PSModule Path ###
From powershell run the following:

```
git clone https://github.com/paulshir/coreos-hyperv "$($env:home)\Documents\WindowsPowershell\Modules\coreos-hyperv"
Import-Module coreos-hyperv
```

## Create a basic cluster with a static network configuration ##
To create a basic cluster with a static network configuration we can do the following. First we create the network config. The following is all run from an administrator powershell prompt.

```
$DNSServers = @('8.8.8.8', '8.8.4.4')
$NetworkConfig = New-CoreosNetworkConfig -SwitchName 'External Virtual Switch 1' -Gateway '192.168.1.1' -SubnetBits 24 -RangeStartIP '192.168.1.200' -DNSServers $DNSServers
```

This creates a powershell variable with all the network info required to modify the configuration files with.

The next thing you need to do is to add your ssh public key to the configuration. For this example we will be using the config/basiccluster_staticnetwork.yaml file. You can generate a key with puttygen and insert the public key into the config (line 5). Now with the network config and the config file ready we can create the cluster.

```
New-CoreosCluster -Name coreos-basiccluster0 -Count 3 -NetworkConfigs $network -Config .\coreos-hyperv\configs\basiccluster_staticnetwork.yaml | Start-CoreosCluster
```

All going well your cluster should now be up and running. It takes around 5 minutes to set up. I have found however that the network config doesn't always work on the first boot so you might need to restart the VMs. To do this you can run the following commands.

```
$cluster = Get-CoreosCluster -ClusterName coreos-basiccluster0
$cluster | Stop-CoreosCluster
$cluster | Start-CoreosCluster
```

It is also good to ssh into the VMs and check if the cluster vms are talking to each other. You can test this by running the command `etcdctl set /foo bar`. This command should fail if the cluster isn't working properly but if it works you can ssh into another VM and run `etcdctl get /foo` to see if it has propegated. The result should be `bar`

## Configuration ##
### General Configuration ###
Included in the script are some basic template replacement handles to ease the generation of config files. This should make it easier to create configurations that can be used serveral times without having to make changes to the config file everytime.

The Handles that are available are listed here.

`{{VM_NAME}}` The name of the vm.
`{{VM_NUMBER}}` The number of the VM in the cluster
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

## Limitations ##
### Tracking the install ###
The coreos iso doesn't have hyper-v integration services installed so it is currently not possible to track the installation progress of the installation or retrieve the IP address assigned by dhcp to the VM(This is why acutally why I ended up writing this script and not using a Vagrant File witht the hyper-v provider for Vagrant).

To ensure that the installation is running smoothly you can take the following steps.

1. Open Hyper-V Manager.
2. Connect to one of the created VMs.
3. Enter the command `systemctl status dynamicrun-install.service`.

This will show the status of the install process. If it hasn't run or failed it should be apparent.

You can also see the network status with `ifconfig`

### The auto install process ###
The auto install process is a bit hacky. It works as following.

1. Creates a VM and a VHD for installing coreos onto.
2. Downloads and attaches the coreos iso as the boot device.
3. Attaches a VHDX file that is created in the install process that has an installation script and the cloud-config for the installation available on it.
4. Attaches an ISO labeled config2. Coreos automatically detects and runs this. This ISO is configured to call the installation script on the VHDX.

## Troubleshooting ##
### Issues with install ###
If you run into any difficulty with the installed vms you can connect to the VMs and log into the vms by doing the following.

1. Turn off the VM if it is already on.
2. Open the Connect to window of the VM and turn on the VM.
3. Press any key a few times to interupt the boot process.
4. Type the command `boot_kernel coreos.autologin`

This will boot the VM and will auto login so you can troubleshoot and debug the installation.

### Networking ###
I've found the easiest way for networking is to set up a seperate VM to act as a NAT. To do this you can use something like Windows Server or ClearOS. This way you have more control over what ip addresses your VMS are assigned etc. This means that even if you are on different networks (i.e. when you are on a laptop) the connections and cluster will remain working.

The installation script requires DHCP to work during installation. Coreos needs a network connection to download the image. It doesn't just install it from disk. However once coreos is installed static networks defined in the config will be used.

There seems to be sometimes an issue on first boot of the static network config not being applied. Usually a reboot of the VMS fixes this.

### Modules Functions ###
To see the functions of this powershell modules you can use the `Show-Command` powershell function. You can also find out how to use the functions using `Get-Help <Function Name>`. This will give you examples of how to use the functions.