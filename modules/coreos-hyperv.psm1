############################
# Manage Cluster Functions #
############################
<#
.SYNOPSIS
    Creates and installs coreos on a cluster of virtual machines.
#>
Function New-CoreosCluster {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [Alias("ClusterName")]
        [String] $Name,

        [Parameter (Mandatory=$true)]
        [Int] $Count,

        [Parameter (Mandatory=$true)]
        [PSObject[]] $NetworkConfigs,

        [Parameter (Mandatory=$false, ParameterSetName="SingleConfig")]
        [String] $Config,

        [Parameter (Mandatory=$false, ParameterSetName="MultipleConfigs")]
        [String[]] $Configs
    )

    PROCESS {
        if (!(Test-IsShellAdmin)) {
            throw "You must run as an administrator to run this script."
            return
        }

        $ClusterFilesDirectory = Get-CoreosClusterDirectory -ClusterName:$Name

        if (Test-Path $ClusterFilesDirectory) {
            throw "Cluster $Name already exists. Exiting."
            return
        }

        if ($Configs -and $Configs.length -ne $Count) { throw "Number of config files doesn't match the count in the cluster"; return }

        New-Item -Type Directory $ClusterFilesDirectory | Out-Null

        # Store the Cluster Config Info
        $ConfigInfo = New-Object PSObject
        $ConfigInfo | Add-Member Networks $NetworkConfigs
        $ConfigInfo | Add-Member EtcdDiscoveryToken $(New-EtcdDiscoveryToken)

        if ($Config) {
            if (Test-Path $Config) {
                $ConfigTemplate = "template.yaml"
                $ConfigTemplatePath = Join-Path -Path (Get-CoreosClusterDirectory -ClusterName:$Name) $ConfigTemplate

                Copy-Item $Config $ConfigTemplatePath
                $ConfigInfo | Add-Member DefaultConfigTemplate $ConfigTemplate
            } else {
                throw ("Config $Config not found.")
            }
        }

        # Store the VMs Info
        $ClusterInfo = New-Object PSObject
        $ClusterInfo | Add-Member VMs @()
        $ClusterInfo | Add-Member Name $Name
        $ClusterInfo | Add-Member Config $ConfigInfo


        for ($i = 0; $i -lt $Count; $i++) {
            if ($Configs) {
                New-VMInCoreosClusterInfo -ClusterInfo:$ClusterInfo -Config:$Configs[$i]
            } else {
                New-VMInCoreosClusterInfo -ClusterInfo:$ClusterInfo
            }
        }

        Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        Invoke-CoreosClusterBuilder -ClusterInfo:$ClusterInfo

        Write-Output $ClusterInfo
    }
}

<#
.SYNOPSIS
    Removes a cluster of coreos virtual machines and associated files.
#>
Function Remove-CoreosCluster {
    [CmdletBinding(DefaultParameterSetName="ClusterInfo")]
    Param (
        [Parameter (Mandatory=$true, ParameterSetName="ClusterInfo", ValueFromPipeline=$true)]
        [PSObject] $ClusterInfo,

        [Parameter (Mandatory=$true, ParameterSetName="ClusterName")]
        [String] $ClusterName
    )

    PROCESS {
        if ($ClusterName) {
            $ClusterInfo = Get-CoreosCluster -ClusterName:$ClusterName
        }

        # Call to ensure failed vms are marked.
        Invoke-CoreosClusterBuilder -ClusterInfo:$ClusterInfo

        $ClusterInfo | Stop-CoreosCluster
        $ClusterInfo.VMs | where { $_.State -eq "Completed" -or $_.State -eq "Failed" } | foreach { $_.State = "Remove" }

        Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        Invoke-CoreosClusterBuilder -ClusterInfo:$ClusterInfo

        $ClusterFilesDirectory = Get-CoreosClusterDirectory -ClusterName:$ClusterInfo.Name
        Remove-Item -Force -Recurse $ClusterFilesDirectory
    }
}

<#
.SYNOPSIS
    Starts up a cluster of coreos virtual machines.
#>
Function Start-CoreosCluster {
    [CmdletBinding(DefaultParameterSetName="ClusterInfo")]
    Param (
        [Parameter (Mandatory=$true, ParameterSetName="ClusterInfo", ValueFromPipeline=$true)]
        [PSObject] $ClusterInfo,

        [Parameter (Mandatory=$true, ParameterSetName="ClusterName")]
        [String] $ClusterName
    )

    PROCESS {
        if ($ClusterName) {
            $ClusterInfo = Get-CoreosCluster -ClusterName:$ClusterName
        }

        $ClusterInfo.VMs | foreach { Start-VM -VMName $_.Name | Out-Null }
    }
}

<#
.SYNOPSIS
    Stops a cluster of coreos virtual machines.
#>
Function Stop-CoreosCluster {
    [CmdletBinding(DefaultParameterSetName="ClusterInfo")]
    Param (
        [Parameter (Mandatory=$true, ParameterSetName="ClusterInfo", ValueFromPipeline=$true)]
        [PSObject] $ClusterInfo,

        [Parameter (Mandatory=$true, ParameterSetName="ClusterName")]
        [String] $ClusterName
    )

    PROCESS {
        if ($ClusterName) {
            $ClusterInfo = Get-CoreosCluster -ClusterName:$ClusterName
        }

        $ClusterInfo.VMs | foreach { Stop-VM -VMName $_.Name | Out-Null }
    }
}

<#
.SYNOPSIS
    Gets a cluster of coreos virtual machines.
#>
Function Get-CoreosCluster {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    PROCESS {
        $infoFile = Join-Path -Path $(Get-CoreosClustersDirectory) "$ClusterName\cluster-info.json"
        if (!(Test-Path $infoFile)) {
            throw "Coreos Cluster $ClusterName doesn't exist."
            return
        }

        Get-Content $infoFile -Raw | ConvertFrom-Json
    }
}

############################
### Manage VM Functions ####
############################
############################
# Manage Cluster Functions #
############################
<#
.SYNOPSIS
    Creates and installs coreos on a cluster of virtual machines.
#>
Function New-CoreosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $ClusterName,

        [Parameter (Mandatory=$false)]
        [String] $Config
    )

    PROCESS {
        if (!(Test-IsShellAdmin)) {
            throw "You must run as an administrator to run this script."
            return
        }

        $ClusterInfo = Get-CoreosCluster -ClusterName $ClusterName -ErrorAction:Stop

        if ($Config) {
            New-VMInCoreosClusterInfo -ClusterInfo:$ClusterInfo -Config:$Config
        } else {
            New-VMInCoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        Invoke-CoreosClusterBuilder -ClusterInfo:$ClusterInfo

        Write-Output $ClusterInfo
    }
}

############################
##### Config Functions #####
############################
<#
.SYNOPSIS
    Creates a config file witht the coreos settings.
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
    Gets a coreos virtual machine.
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
#>
Function New-EtcdDiscoveryToken {
    $wr = Invoke-WebRequest -Uri "https://discovery.etcd.io/new"
    Write-Output $wr.Content
}

############################
#### Internal Functions ####
############################
<#
.SYNOPSIS
    Adds the CoreosISO to a VM.
#>
Function Add-CoreosISO {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName
    )

    BEGIN {
        $coreosisoLocation = Get-CoreosISO
    }

    PROCESS {        
        Remove-CoreosISO -VMName:$VMName
        Add-VMDvdDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 0 -Path $coreosisoLocation
    }
}

<#
.SYNOPSIS
    Remove the CoreosISO from a VM.
#>
Function Remove-CoreosISO {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName
    )

    BEGIN {
        $coreosisoLocation = Get-CoreosISO
    }

    PROCESS {
        Get-VMDvdDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 0 | Remove-VMDvdDrive
    }
}

<#
.SYNOPSIS
    Adds a new VM to the coreos cluster info.
#>
Function New-VMInCoreosClusterInfo {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo,

        [Parameter (Mandatory=$false)]
        [String] $Config
    )

    PROCESS {
        $VMNumber = ($ClusterInfo.VMs | Measure).Count
        $VMNumber_00 = $VMNumber.ToString("00")

        $VMName = "$($ClusterInfo.Name)_$VMNumber_00"
        $ConfigTemplate = $null

        if ($Config) {
            if (Test-Path $Config) {
                $ConfigTemplate = "template_$VMNumber_00.yaml"
                $ConfigTemplatePath = Join-Path -Path (Get-CoreosClusterDirectory -ClusterName:$($ClusterInfo.Name)) $ConfigTemplate

                Copy-Item $Config $ConfigTemplatePath
            } else {
                throw ("Config $Config not found.")
            }
        } elseif ($ClusterInfo.Config.DefaultConfigTemplate) {
            $ConfigTemplate = $ClusterInfo.Config.DefaultConfigTemplate
        }

        $VM = New-Object PSObject
        $VM | Add-Member Name $VMName
        $VM | Add-Member Number $VMNumber
        $VM | Add-Member Number_00 $VMNumber_00
        $VM | Add-Member State "Queued"
        if ($ConfigTemplate) {
            $VM | Add-Member ConfigTemplate $ConfigTemplate
        }

        $ClusterInfo.VMs += $VM
    }
}

<#
.SYNOPSIS
    Takes in a cluster info and takes necessary steps to build the cluster vms.
#>
Function Invoke-CoreosClusterBuilder {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo
    )

    PROCESS {
        $ClusterFilesDirectory = Get-CoreosClusterDirectory -ClusterName $ClusterInfo.Name
        $NetworkSwitchNames = @()
        $ClusterInfo.Config.Networks | foreach { $NetworkSwitchNames += $_.SwitchName }

        # Clean up in the event the previous run was aborted.
        $failedVms = $ClusterInfo.VMs | where { $_.State -ne "Queued" -and $_.State -ne "Completed" -and $_.State -ne "Failed" -and $_.State -ne "Removed" -and $_.State -ne "Remove" }
        if ($failedVMs) {
            $failedVMs | foreach {
                Write-Warning "VM $($_.Name) found in an incomplete state. Marking as failed."
                $_.State = "Failed"
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo
        }

        $queued = $ClusterInfo.VMs | where { $_.State -eq "Queued" }
        if ($queued) {
            $queued | foreach {
                $_.State = "Starting"
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo
        }

        # Create the config files for the VMs
        if (($ClusterInfo.VMs | where { $_.State -eq "Starting" } | Measure).Count -gt 0) {
            Write-Verbose "Creating the Config Files for the VMs."

            $ClusterInfo.VMs | where { $_.State -eq "Starting" -and $_.ConfigTemplate -and -not $_.Config} | foreach {
                $ConfigTemplatePath = Join-Path -Path $ClusterFilesDirectory $_.ConfigTemplate
                $Config = "config_$($_.Number_00).yaml"
                $ConfigPath = Join-Path -Path $ClusterFilesDirectory $Config
                New-CoreosConfig `
                    -Path:$ConfigTemplatePath `
                    -Destination:$ConfigPath `
                    -VMName:$_.Name `
                    -ClusterName:$ClusterInfo.Name `
                    -VMNumber:$_.Number `
                    -EtcdDiscoveryToken:$ClusterInfo.Config.EtcdDiscoveryToken `
                    -NetworkConfigs:$ClusterInfo.Config.Networks | Out-Null

                $_ | Add-Member Config $Config
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo

            # Create the VM
            Write-Verbose "Creating the VMs."
            $ClusterInfo.VMs | where { $_.State -eq "Starting" } | foreach {
                $VMName = $_.Name
                $vhdLocation = "$((Get-VMHost).VirtualHardDiskPath)\$VMName.vhd"

                # Create the VM - Windows 2012 doesn't support -Generation
                if ((Get-WmiObject Win32_OperatingSystem).Version -ge 6.3) {
                    # Windows 6.3 and higher = 2012 R2 + 81. http://msdn.microsoft.com/en-us/library/windows/desktop/ms724832(v=vs.85).aspx
                    $vm = New-VM -Name $VMName -MemoryStartupBytes 1024MB -NoVHD -Generation 1 -BootDevice CD -SwitchName $NetworkSwitchNames[0]
                } else {
                    $vm = New-VM -Name $VMName -MemoryStartupBytes 1024MB -NoVHD -BootDevice CD -SwitchName $NetworkSwitchNames[0]
                }
                $vm | Set-VMMemory -DynamicMemoryEnabled:$true
                $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $VMName -SwitchName $_ } | Out-Null
                $vhd = New-VHD -Path $vhdLocation -SizeBytes 10GB

                Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhd.Path
                
                $_.State = "ReadyForInstall"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        if (($ClusterInfo.VMs | where { $_.State -eq "ReadyForInstall" } | Measure).Count -gt 0) {
            Write-Verbose "Installing Coreos on VMs."

            # Add Coreos Image and config to VM
            $ClusterInfo.VMs | where { $_.State -eq "ReadyForInstall" } | foreach {
                Add-CoreosISO -VMName:$_.Name
                if ($_.Config) { Add-DynamicRun -VMName:$_.Name -ClusterName:$ClusterInfo.Name -Config:$_.Config -Install }
                else { Add-DynamicRun -VMName:$_.Name -ClusterName:$ClusterInfo.Name -Install }

                Start-VM -VMName $_.Name
                $_.State = "Installing"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        $Count = ($ClusterInfo.VMs | where { $_.State -eq "Installing" } | Measure).Count
        if ($Count -gt 0) {
            $timeout = Get-InstallTimeout
            $timeout = $timeout + ($timeout/20)*$Count
            for ($i=1; $i -le $timeout; $i++) {
                Start-Sleep -s 1
                Write-Progress -Activity "Installing coreos to $Count VMs in Cluster $Name" -SecondsRemaining $($timeout - $i)
            }

            $ClusterInfo.VMs | where { $_.State -eq "Installing" } | foreach {
                Stop-VM -VMName $_.Name -TurnOff | Out-Null
                Remove-CoreosISO -VMName:$_.Name
                Remove-DynamicRun -VMName:$_.Name

                $_.State = "Installed"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        if (($ClusterInfo.VMs | where { $_.State -eq "Installed" } | Measure).Count -gt 0) {
            Write-Verbose "Tidying up after install."

            # $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
            #     # Remove-VMNetworkAdapter -VMName:$_.Name
            #     Start-VM -VMName:$_.Name | Out-Null
            # }

            # $timeout = 60
            # for ($i=1; $i -le $timeout; $i++) {
            #     Start-Sleep -s 1
            #     Write-Progress -Activity "Starting the VMs quickly so the configuration is properly loaded." -SecondsRemaining $($timeout - $i)
            # }

            # $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
            #     $VMName = $_.Name
            #     Stop-VM -VMName:$VMName | Out-Null
            #     # $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $VMName -SwitchName $_ } | Out-Null
            # }

            $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
                $_.State = "Completed"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        # Remove and VMs with the State Remove
        if (($ClusterInfo.VMs | where { $_.State -eq "Remove" } | Measure).Count -gt 0) {
            Write-Verbose "Removing VMS"

            $ClusterInfo.VMs | Where { $_.State -eq "Remove" } | foreach {
                $vhdPaths = (Get-VMHardDiskDrive -VMName $_.Name).Path
                Get-VMHardDiskDrive -VMName $_.Name | Remove-VMHardDiskDrive
                $vhdPaths | Remove-Item -Force

                Remove-VM -VMName $_.Name
                $_.State = "Removed"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }
    }
}

############################
###### Hack Functions ######
############################
<#
.SYNOPSIS
    Creates the necessary files and adds them to the coreos vm to automatically install or configure the vm.
#>
Function Add-DynamicRun {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName,

        [Parameter (Mandatory=$true, ParameterSetName="Install")]
        [Switch] $Install,

        [Parameter (Mandatory=$true, ParameterSetName="Reconfigure")]
        [Switch] $Reconfigure,

        [Parameter (Mandatory=$false, ParameterSetName="Install")]
        [Parameter (Mandatory=$true, ParameterSetName="Reconfigure")]
        [String] $Config
    )

    BEGIN {
        $drisoLocation = Get-DynamicrunISO
        $coreosisoLocation = Get-CoreosISO
    }

    PROCESS {
        $drvhdlocation = Join-Path -Path $(Get-CoreosClustersDirectory) "$ClusterName\tmp\$VMName.vhdx"
        if (!(Test-Path(Split-Path -parent $drvhdlocation))) {
            New-Item (Split-Path -parent $drvhdlocation) -Type directory | Out-Null
        }

        # Create the vhd with the dynamic run configuration
        $vhd = New-VHD -Path $drvhdlocation -Dynamic -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT -Confirm:$false -Force
        Start-Sleep -s 1

        if ($Config) { $configPath = Join-Path -Path $(Get-CoreosClusterDirectory -ClusterName $ClusterName) $Config }

        if ($Install) { & cmd /C "copy `"$(Get-DynamicrunInstallFolder)\**`" $($vhd.DriveLetter):\" | Out-Null }
        if ($Reconfigure) { & cmd /C "copy `"$(Get-DynamicrunReconfigureFolder))\**`" $($vhd.DriveLetter):\" | Out-Null }
        if ($Config) { & cmd /C "copy `"$configPath`" $($vhd.DriveLetter):\cloud-config.yaml" | Out-Null }

        Dismount-VHD $drvhdlocation

        Get-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 | Remove-VMDvdDrive
        Get-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 | Remove-VMHardDiskDrive

        Add-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 -Path $drisoLocation
        Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 -Path $drvhdlocation
    }
}

<#
.SYNOPSIS
    Removes the files from the vm created to automatically install or configure the vm so that it can be used.
#>
Function Remove-DynamicRun {
    [CmdletBinding()]
    Param (
        [String] $VMName
    )

    PROCESS {
        if ((Get-VM -VMName $VMName).State -ne "Off") {
            Stop-VM -VMName $VMName -TurnOff | Out-Null
        }

        $dynamicrunVhd = (Get-VMHardDiskDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 1).Path
        Get-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 | Remove-VMDvdDrive
        Get-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 | Remove-VMHardDiskDrive

        if ($dynamicrunVhd -and (Test-Path($dynamicrunVhd))) {
            Remove-Item $dynamicrunVhd -Force
        }
    }
}
