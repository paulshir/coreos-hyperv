############################
# Manage Cluster Functions #
############################
<#
.SYNOPSIS
    Creates and installs coreos on a cluster of virtual machines.
.DESCRIPTION
    Creates and installs coreos on a cluster of virtual machines.
.PARAMETER Name
    The Name of the Cluster.
.PARAMETER Count
    The number of VMs in the cluster.
.PARAMETER NetworkConfigs
    An array of objects that contain information on the hyper-v virtual switch and settings for the network. 
    These configs can easily be created using the New-CoreosNetworkConfig function.
.PARAMETER Config
    Set a default config to be applied for all clusters.
.PARAMETER Configs
    Instead of setting a default config you can set a config for each machine individually. The count of configs
    must match the count of VMs being created in the cluster.
.OUTPUTS
    Outputs a ClusterInfo object with information about the cluster, the configuration and the virtual machines.
#>
Function New-CoreosCluster {
    [CmdletBinding(DefaultParameterSetName="SingleConfig")]
    Param (
        [Parameter (Mandatory=$true)]
        [Alias("ClusterName")]
        [String] $Name,

        [Parameter (Mandatory=$true)]
        [Int] $Count,

        [Parameter (Mandatory=$true)]
        [PSObject[]] $NetworkConfigs,

        [Parameter (Mandatory=$false)]
        [ValidateSet("Alpha","Beta","Stable","Master")]
        [String] $Channel = "Alpha",

        [Parameter (Mandatory=$false)]
        [String] $Release = "",

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
        $ConfigInfo | Add-Member EtcdDiscoveryToken $(New-EtcdDiscoveryToken -Size $Count)

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
        $ClusterInfo | Add-Member Channel $Channel
        $ClusterInfo | Add-Member Release $Release
        $ClusterInfo | Add-Member Name $Name
        $ClusterInfo | Add-Member Config $ConfigInfo
        $ClusterInfo | Add-Member VMs @()
        $ClusterInfo | Add-Member Version $(Get-ModuleVersion)   
        
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
.DESCRIPTION
    Removes a cluster of coreos virtual machines and associated files.
.PARAMETER ClusterInfo
    Specifies which cluster to remove based on the cluster info object.
    This can be piped from Get-ClusterInfo.
.PARAMETER ClusterName
    Specifies which cluster to remove based on the cluster name.  
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

        $ClusterInfo | Stop-CoreosCluster
        $ClusterInfo.VMs | foreach { 
            if ($_.State -eq "Queued" -and $_.Action -ne "Remove") {
                $_.State = "Complete"
            } else {
                $_.State = "Queued";                
            }
            
            $_.Action = "Remove";
        }

        Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        Invoke-CoreosClusterBuilder -ClusterInfo:$ClusterInfo

        $ClusterFilesDirectory = Get-CoreosClusterDirectory -ClusterName:$ClusterInfo.Name
        Remove-Item -Force -Recurse $ClusterFilesDirectory
    }
}

<#
.SYNOPSIS
    Starts up a cluster of coreos virtual machines.
.DESCRIPTION
    Starts up all the virtual machines in a coreos cluster.
.PARAMETER ClusterInfo
    Specifies which cluster to start from the cluster info object.
.PARAMETER ClusterName
    Specifies which cluster to start from the name of the cluster.
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
.DESCRIPTION
    Stops a cluster of coreos virtual machines.
.PARAMETER ClusterInfo
    Specifies which cluster to stop from the cluster info object.
.PARAMETER ClusterName
    Specifies which cluster to stop from the name of the cluster.
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
.DESCRIPTION
    Gets a cluster of coreos virtual machines. This returns a ClusterInfo Object.
    The ClusterInfo object can be piped to other commands.
.PARAMETER ClusterName
    The name of the cluster to get the info for.
.OUTPUTS
    Outputs a ClusterInfo object with information about the cluster, the configuration and the virtual machines.
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

        Get-Content $infoFile | Out-String | ConvertFrom-Json
    }
}

############################
### Manage VM Functions ####
############################
<#
.SYNOPSIS
    Creates and installs a coreos virtual machine in a coreos cluster.
.DESCRIPTION
    Creates and installs a coreos virtaul machine in a coreos cluster.
    Applies the same values to the config as were applied to the other virtual machines in the cluster.
.PARAMETER ClusterName
    The name of the cluster to add the new vm to.
.PARAMETER Config
    The path to the config file to use for this VM. If no config file is specified then the default config file for the
    cluster will be used.
.OUTPUTS
    Outputs an updated ClusterInfo object with information about the cluster, the configuration and the virtual machines.
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
#### Internal Functions ####
############################
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
        $VM | Add-Member Action "Create"
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
        $failedVms = $ClusterInfo.VMs | where { $_.State -eq "InProgress" }
        if ($failedVMs) {
            $failedVMs | foreach {
               Write-Warning "VM $($_.Name) found in an incomplete state. Marking as failed."
                $_.State = "Failed"
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo
        }

        $queued = $ClusterInfo.VMs | where { $_.State -eq "Queued" }
        if (!$queued) {
            return
        }

        $toCreate = $queued | where { $_.Action -eq "Create"}
        if ($toCreate) {
            
            # Get the image
            $image = Get-CoreosImage -ImageDir:$(Get-ImageDirectory) -Channel:$($ClusterInfo.Channel) -Release:$($ClusterInfo.Release) -ErrorAction:Stop

            $baseConfigDrive = Get-BaseConfigDrive -ModuleFilesDir:$(Get-ModuleFilesDirectory) -ImageDir:$(Get-ImageDirectory) -ErrorAction:Stop            

            # Generate the config
            $queued | where { $_.Action -eq "Create" } | foreach { $_.State = "InProgress" }
            Write-Verbose "Creating the Config Files and drives for the VMs."

            $toCreate | where { $_.ConfigTemplate -and -not $_.Config } | foreach {
                $ConfigTemplatePath = Join-Path -Path $ClusterFilesDirectory $_.ConfigTemplate
                $Config = "config_$($_.Number_00).yaml"
                $ConfigPath = Join-Path -Path $ClusterFilesDirectory $Config
                New-CoreosConfig `
                    -Path:$ConfigTemplatePath `
                    -Destination:$ConfigPath `
                    -VMName:$_.Name `
                    -ClusterName:$ClusterInfo.Name `
                    -VMNumber:$_.Number `
                    -Channel:$ClusterInfo.Channel `
                    -EtcdDiscoveryToken:$ClusterInfo.Config.EtcdDiscoveryToken `
                    -NetworkConfigs:$ClusterInfo.Config.Networks | Out-Null

                $ConfigDrive = New-CoreosConfigDrive -BaseConfigDrivePath:$baseConfigDrive -ConfigPath:$ConfigPath

                $_ | Add-Member Config $Config
                $_ | Add-Member ConfigDrive $ConfigDrive
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo

            # Create the VM
            Write-Verbose "Creating the VMs."
            $toCreate | foreach {
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

                # Copy the image to the vhd location.
                Copy-Item -Path:$image.ImagePath -Destination:$vhdLocation
                Resize-VHD -Path:$vhdLocation -SizeBytes:10GB
                Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhdLocation
                Remove-VMDvdDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 0 | Out-Null

                if ($_.ConfigDrive) {
                    Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 0 -Path $_.ConfigDrive
                }

                $_.State = "Complete"
                $_.Action = "None"
            }

            Out-CoreosClusterInfo -ClusterInfo $ClusterInfo
        }

        $queued | where { $_.Action -eq "Remove" } | foreach { $_.State = "InProgress" }

        $toRemove = $queued | where { $_.Action -eq "Remove" }
        if ($toRemove) {
            Write-Verbose "Removing VMS"

            $toRemove | foreach {
                $vhdPaths = (Get-VMHardDiskDrive -VMName $_.Name).Path
                Get-VMHardDiskDrive -VMName $_.Name | Remove-VMHardDiskDrive
                $vhdPaths | Remove-Item -Force

                Remove-VM -VMName $_.Name
                $_.State = "Removed"
                $_.Action = "None"
            }

            Out-CoreosClusterInfo -ClusterInfo:$ClusterInfo
        }
    }
}

Function Get-ModuleVersion {
    Param()
    PROCESS {
        (Get-Module coreos-hyperv).Version
    }
}
