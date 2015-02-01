############################
##### Public Functions #####
############################
<#
.SYNOPSIS
    Creates a config file with the coreos settings.
.DESCRIPTION
    Outputs a config file with the specified settings based on a template config.
.PARAMETER Path
    The path to the config file.
.PARAMETER Destination
    The path to output the config file to.
.PARAMETER VMName
    The name of the VM the config should have.
    {{VM_NAME}} will be replaced in the template config file with this value.
.PARAMETER VMNumber
    The number of the VM in the Cluster (Starting at 0).
    {{VM_NUMBER}} will be replaced in the template config file with this value.
    This value will also be used in the assigning of IP Addresses for network config.
.PARAMETER Channel
    The channel (e.g. alpha, beta, stable or master) to use.
    {{CHANNEL}} will be replaced in the template config with the lowercase version of this value.
.PARAMETER EtcdDiscoveryToken
    The etcd discovery used so that machines can all join the same cluster.
    {{ETCD_DISCOVERY_TOKEN}} will be replaced in the template config with this value.
.PARAMETER ClusterName
    The name of the cluster the virtual machine is in.
    {{CLUSTER_NAME}} will be replaced in the template config with this value.
.PARAMETER NetworkConfigs
    This in an array of Network Config Objects. For each network config certain values will be
    replaced in the template config.
    {{IP_ADDRESS[NET_0]}} will be replaced with the calculated IP address from the VM Number and the
    starting IP address of NetworkConfig[0]
    {{GATEWAY[NET_0]}} will be replaced in the template config with the gateway for the first network config.
    {{DNS_SERVER_0[NET_0]}} will be replaced in the template config with the first DNS Server in the first network config.
    Multiple DNS Servers can be added as needed.
    {{SUBNET_BITS[NET_0]}} will be replaced in the template config with the number of bits in the subnet for the first network.
.OUTPUTS
    The path that the destination file was saved to.
#>
Function New-CoreosConfig {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $Path,

        [Parameter (Mandatory=$true)]
        [String] $Destination,

        [Parameter (Mandatory=$true)]
        [Alias("Name")]
        [String] $VMName,

        [Parameter (Mandatory=$false)]
        [int] $VMNumber,

        [Parameter (Mandatory=$false)]
        [ValidateSet("Alpha","Beta","Stable","Master")]
        [String] $Channel,

        [Parameter (Mandatory=$false)]
        [String] $EtcdDiscoveryToken,

        [Parameter (Mandatory=$false)]
        [String] $ClusterName,

        [Parameter (Mandatory=$false)]
        [PSObject[]] $NetworkConfigs
    )

    PROCESS {
        if (!(Test-Path $Path)) {
            throw "Config doesn't exist"
        }

        if (Test-Path $Destination) {
            Move-Item -Path $Destination -Destination "$Destination.$(Get-DateTimeStamp)_bak"
        }

        $vmnumber00 = $VMNumber.ToString("00")

        $cfg = Get-Content $Path | foreach { $_ -replace '{{VM_NAME}}', $VMName }
        if ($VMNumber -or $VMNumber -eq 0) { $cfg = $cfg | foreach { $_ -replace '{{VM_NUMBER}}', $VMNumber.ToString() } | foreach { $_ -replace '{{VM_NUMBER_00}}', $vmnumber00 } }
        if ($EtcdDiscoveryToken) { $cfg = $cfg | foreach { $_ -replace '{{ETCD_DISCOVERY_TOKEN}}', $EtcdDiscoveryToken } }
        if ($ClusterName) { $cfg = $cfg | foreach { $_ -replace '{{CLUSTER_NAME}}', $ClusterName } }
        if ($Channel) { $cfg = $cfg | foreach { $_ -replace '{{CHANNEL}}', $Channel.ToLower()}}

        for ($i=0; $i -lt $NetworkConfigs.Length; $i++) {
            $Network = $NetworkConfigs[$i]

            if ($Network.RangeStartIP) {
                $OffsetIP = Get-OffsetIPAddress -RangeStartIP $Network.RangeStartIP -Count $VMNumber
                $ReplaceText = "{{IP_ADDRESS\[NET_$($i)]}}"
                $cfg = $cfg | foreach { $_ -replace $ReplaceText, $OffsetIP }
            }

            if ($Network.Gateway) {
                $ReplaceText = "{{GATEWAY\[NET_$($i)]}}"
                $cfg = $cfg | foreach { $_ -replace $ReplaceText, $Network.Gateway }
            }

            if ($Network.DNSServers) {
                for ($j=0; $j -lt $Network.DNSServers.Length; $j++) {
                    $ReplaceText = "{{DNS_SERVER_$($j)\[NET_$($i)]}}"
                    $cfg = $cfg | foreach { $_ -replace $ReplaceText, $Network.DNSServers[$j] }
                }
            }

            if ($Network.SubnetBits) {
                $ReplaceText = "{{SUBNET_BITS\[NET_$($i)]}}"
                $cfg = $cfg | foreach { $_ -replace $ReplaceText, $Network.SubnetBits }
            }
        }

        $cfg | Out-File $Destination -Encoding ascii

        Get-Item $Destination
    }
}

<#
.SYNOPSIS
    Create a coreos network config.
.DESCRIPTION
    A method that makes it easy to create a network config that can be used in the creation of coreos clusters.
.PARAMETER SwitchName
    The Hyper-V virtual switch to use for this network config.
.PARAMETER RangeStartIP
    The starting IP address to be used in the cluster.
.PARAMETER Gateway
    The network gateway that can be assigned to clusters.
.PARAMETER SubnetBits
    The number of bits in the subnet mask for the configuration.
.PARAMETER DNSServers
    An array of DNS Servers to use for the config.
#>
Function New-CoreosNetworkConfig {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $SwitchName,

        [Parameter (Mandatory=$false)]
        [String] $RangeStartIP,

        [Parameter (Mandatory=$false)]
        [String] $Gateway,

        [Parameter (Mandatory=$false)]
        [Int] $SubnetBits,

        [Parameter (Mandatory=$false)]
        [String[]] $DNSServers
    )

    PROCESS {
        Get-VMSwitch -Name $SwitchName -ErrorAction:Stop | Out-Null
        $NetworkConfig = New-Object PSObject
        $NetworkConfig | Add-Member SwitchName $SwitchName
        if ($RangeStartIP) { $NetworkConfig | Add-Member RangeStartIP $RangeStartIP }
        if ($Gateway) { $NetworkConfig | Add-Member Gateway $Gateway }
        if ($SubnetBits) { $NetworkConfig | Add-Member SubnetBits $SubnetBits }
        if ($DNSServers) { $NetworkConfig | Add-Member DNSServers $DNSServers }

        Write-Output $NetworkConfig
    }
}

<#
.SYNOPSIS
    Get a discovery token for etcd.
.PARAMETER size
    Sets the number etcd instances to be used in the quorom. Machines added outside of this
    value will be proxy instances by default. See https://github.com/coreos/etcd for more information.
    Setting the default value to 3 to match the website.
#>
Function New-EtcdDiscoveryToken {
    Param(
        [Parameter (Mandatory=$false)]
        [Int] $Size = 3
    )

    if ($Size -gt 9) {
        $Size = 9
    }

    if ($Size -le 0) {
        $Size = 0
    }

    $wr = Invoke-WebRequest -Uri "https://discovery.etcd.io/new?size=$Size"
    Write-Output $wr.Content
}

############################
#### Protected Functions ###
############################
Function New-CoreosConfigDrive {
    Param(
        [Parameter (Mandatory=$true)]
        [String] $BaseConfigDrivePath,

        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
        [String] $ConfigPath
    )

    PROCESS {
        $vhdLocation = "$ConfigPath.vhdx"

        Copy-Item -Path:$BaseConfigDrivePath -Destination:$vhdLocation
        $vhd = Mount-VHD -Path $vhdLocation -ErrorAction:Stop -Passthru | Get-Disk | Get-Partition | Get-Volume
        Start-Sleep -s 1

        & cmd /C "IF NOT EXIST `"$($vhd.DriveLetter):\openstack\latest`" (mkdir $($vhd.DriveLetter):\openstack\latest)" | Out-Null
        & cmd /C "copy `"$configPath`" $($vhd.DriveLetter):\openstack\latest\user_data" | Out-Null

        Dismount-VHD $vhdLocation | Out-Null

        Write-Output $vhdLocation
    }
}

############################
#### Private Functions #####
############################
<#
.SYNOPSIS
    Gets an IP address offsetted from the original.
    Currently only works with the last octet.
#>
Function Get-OffsetIPAddress {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $RangeStartIP,

        [Parameter (Mandatory=$true, ValueFromPipeline="True")]
        [Int] $Count
    )

    PROCESS {
        $StartIP = $RangeStartIP.Split('.') | foreach { $_ -as [int] }
        $StartIP[3] += $Count
        $OffesetIP = $StartIP -join '.'

        Write-Output $OffesetIP
    }

}
