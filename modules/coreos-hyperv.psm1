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
        
    )

    BEGIN {}

    PROCESS {
    }

    END {}
}

<#
.SYNOPSIS
    Removes a cluster of coreos virtual machines and associated files.
#>
Function Remove-CoreosCluster {
    [CmdletBinding()]
    Param (
        
    )

    BEGIN {}

    PROCESS {
    }

    END {}
}

<#
.SYNOPSIS
    Starts up a cluster of coreos virtual machines.
#>
Function Start-CorosCluster {
    [CmdletBinding()]
    Param (
        
    )

    BEGIN {}

    PROCESS {
    }

    END {}
}

<#
.SYNOPSIS
    Stops a cluster of coreos virtual machines.
#>
Function Start-CorosCluster {
    [CmdletBinding()]
    Param (
        
    )

    BEGIN {}

    PROCESS {
    }

    END {}
}

<#
.SYNOPSIS
    Gets a cluster of coreos virtual machines.
#>
Function Get-CorosCluster {
    [CmdletBinding()]
    Param (
        
    )

    BEGIN {}

    PROCESS {
    }

    END {}
}

############################
### Manage VM Functions ####
############################
<#
.SYNOPSIS
    Creates and installs coreos on a virtual machine to a cluster.
#>
Function New-CoreosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName,

        [Parameter (Mandatory=$true)]
        [String[]] $NetworkSwitchNames,

        [Parameter (Mandatory=$false)]
        [String] $Config
    )

    BEGIN {}

    PROCESS {
        # Create an install vm and start it.
        $vm = New-CoreosInstallVM -Name:$VMName -ClusterName:$ClusterName -NetworkSwitchNames:$NetworkSwitchNames -Config:$Config
        Start-VM $vm | Out-Null

        # Blindly wait for install to complete. Need to come up with some way of monitoring this.
        $timeout = GetInstallTimeout
        for ($i=0; $i -lt $timeout; $i++) {
            Write-Progress -Activity "Installing coreos to VM $VMName" -SecondsRemaining $($timeout - $i)
            Start-Sleep -s 1 
        }

        Stop-VM -VMName $VMName -TurnOff | Out-Null

        RemoveCoreosISO -VMName:$VMName
        RemoveDynamicRun -VMName:$VMName
    }

    END {}
}

<#
.SYNOPSIS
    Creates a virtual machine with a coreos install disk.
#>
Function New-CoreosInstallVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName,

        [Parameter (Mandatory=$true)]
        [String[]] $NetworkSwitchNames,

        [Parameter (Mandatory=$false)]
        [String] $Config
    )

    BEGIN {}

    PROCESS {
        $vhdLocation = "$((Get-VMHost).VirtualHardDiskPath)\$VMName.vhd"

        $NetworkSwitchNames | foreach { Get-VMSwitch -Name $_ -ErrorAction:Stop} | Out-Null

        # Create the VM
        $vm = New-VM -Name $VMName -MemoryStartupBytes 1024MB -NoVHD -Generation 1 -BootDevice CD -SwitchName $NetworkSwitchNames[0]
        $vm | Set-VMMemory -DynamicMemoryEnabled:$true
        $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $VMName -SwitchName $_ } | Out-Null
        $vhd = New-VHD -Path $vhdLocation -SizeBytes 10GB

        Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhd.Path
        
        AddCoreosISO -VMName:$VMName
        if ($Config) { AddDynamicRun -VMName:$VMName -ClusterName:$ClusterName -Config:$Config -Install }
        else { AddDynamicRun -VMName:$VMName -ClusterName:$ClusterName -Install }
        
        Write-Output (Get-VM -Name $VMName)
    }

    END {}
}

<#
.SYNOPSIS
    Removes a coreos virtual machine and associated files from a cluster.
#>
Function Remove-CoreosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {
        Get-VM -VMName $VMName | Stop-VM -TurnOff | Out-Null

        RemoveCoreosISO -VMName:$VMName
        RemoveDynamicRun -VMName:$VMName

        $vhd = (Get-VMHardDiskDrive -VMName -ControllerNumber 0 -ControllerLocation 0)
        Get-VM -VMName:$VMName | Remove-VM

        if ($vhd -and (Test-Path($vhd.Path))) {
            Remove-Item $vhd.Path -Force
        }
    }

    END {}
}

<#
.SYNOPSIS
    Starts up a coreos virtual machine.
#>
Function Start-CorosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {
        PreStartCoreosVM -VMName:$VMName -VMNumber:$VMNumber
        Start-VM -VMName:$VMName
    }

    END {}
}

<#
.SYNOPSIS
    Stops a coreos virtual machine.
#>
Function Stop-CorosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {
        Stop-VM -VMName:$VMName
    }

    END {}
}

<#
.SYNOPSIS
    Gets a coreos virtual machine.
#>
Function Get-CorosVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {
        Get-VM -VMName = $VMName
    }

    END {}
}

############################
# Other External Functions #
############################
<#
.SYNOPSIS
    Gets a coreos virtual machine.
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

        [Parameter (Mandatory=$False)]
        [int] $VMNumber,

        [Parameter (Mandatory=$false)]
        [String] $EtcdDiscoveryToken,

        [Parameter (Mandatory=$false)]
        [String] $ClusterName
    )

    BEGIN {
        if (!(Test-Path $Path)) {
            throw "Config doesn't exist"
        }

        if (!(Test-Path $Destination)) {
            Move-Item -Path $Destination -Destination "$Destination.$(GetDateTimeStamp)_bak"
        }

        $vmnumber00 = $VMNumber.ToString("00")
    }

    PROCESS {
        $cfg = Get-Content $Config | foreach { $_ -replace '{{VM_NAME}}', $VMName }
        if ($VMNumber) { $cfg = $cfg | foreach { $_ -replace '{{VM_NUMBER}}', $VMNumber} | foreach { $_ -replace '{{VM_NUMBER_00}}', $vmnumber00 } }
        if ($EtcdDiscoveryToken) { $cfg = $cfg | foreach { $_ -replace '{{ETCD_DISCOVERY_TOKEN}}', $EtcdDiscoveryToken } }
        if ($ClusterName) { $cfg = $cfg | foreach { $_ -replace '{{CLUSTER_NAME}}', $ClusterName } }

        $cfg | Out-File $Destination

        Get-Item $Destination
    }

    END {}
}

<#
.SYNOPSIS
    Gets a coreos files directory.
#>
Function Get-CoreosFilesDirectory {
    [CmdletBinding()]
    Param (
        
    )

    BEGIN {}

    PROCESS {
        if ($env:COREOS_HYPERV_COREOS_FILES_DIR) {
            $dir = $env:COREOS_HYPERV_COREOS_FILES_DIR
        } else {
            $dir = Join-Path -Path $((Get-VMHost).VirtualMachinePath) "Coreos Files"
        }

        if (!(Test-Path $dir)) {
            New-Item $dir -Type directory
        } else {
            Get-Item $dir
        }
    }

    END {}
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
Function GetDateTimeStamp {
    [CmdletBinding()]
    Param (        
    )

    BEGIN {}

    PROCESS {
        Get-Date -UFormat "%Y_%m_%d_%H_%M_%S" | Write-Output
    }

    END {}
}

Function GetModuleFilesDirectory {
    [CmdletBinding()]
    Param (        
    )

    BEGIN {}

    PROCESS {
        $MyInvocation.MyCommand.Module.FileList[0] | Write-Output
    }

    END {}
}

<#
.SYNOPSIS
    Get the coreos iso.
#>
Function GetCoreosISO {
    [CmdletBinding()]
    Param (
    )

    BEGIN {
        $path = Join-Path -Path $(Get-CoreosFilesDirectory) "coreos_production_iso_image.iso"
    }

    PROCESS {
        if (!(Test-Path $path)) {
            # Get the alpha image always as you can install stable, beta and alpha from this image.
            Invoke-WebRequest -Uri 'http://alpha.release.core-os.net/amd64-usr/current/coreos_production_iso_image.iso' -OutFile $path
        }

        Get-Item $path
    }

    END {}
}

<#
.SYNOPSIS
    Get the dynamicrun iso.
#>
Function GetDynamicrunISO {
    [CmdletBinding()]
    Param (
    )

    BEGIN {
        $path = Join-Path -Path $(GetModuleFilesDirectory) "dynamicrun\iso\config2.iso"
    }

    PROCESS {
        Get-Item $path
    }

    END {}
}

<#
.SYNOPSIS
    Get the dynamicrun install folder.
#>
Function GetDynamicrunInstallFolder {
    [CmdletBinding()]
    Param (
    )

    BEGIN {
        $path = Join-Path -Path $(GetModuleFilesDirectory) "dynamicrun\install"
    }

    PROCESS {
        Get-Item $path
    }

    END {}
}

<#
.SYNOPSIS
    Get the dynamicrun reconfigure folder.
#>
Function GetDynamicrunReconfigureFolder {
    [CmdletBinding()]
    Param (
    )

    BEGIN {
        $path = Join-Path -Path $(GetModuleFilesDirectory) "dynamicrun\reconfigure"
    }

    PROCESS {
        Get-Item $path
    }

    END {}
}

<#
.SYNOPSIS
    Gets the time to wait for an install.
#>
Function GetInstallTimeout {
    [CmdletBinding()]
    Param (
    )

    BEGIN {}

    PROCESS {
        if ($env:COREOS_HYPERV_INSTALL_TIMEOUT) {
            Write-Output $env:COREOS_HYPERV_INSTALL_TIMEOUT
        } else {
            Write-Output 180
        }
    }

    END {}
}

<#
.SYNOPSIS
    Tests if the current user is runnign as an administrator.
#>
Function TestIsAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

<#
.SYNOPSIS
    Adds the CoreosISO to a VM.
#>
Function AddCoreosISO {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName
    )

    BEGIN {
        $coreosisoLocation = GetCoreosISO
    }

    PROCESS {        
        RemoveCoreosISO -VMName:$VMName
        Add-VMDvdDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 0 -Path $coreosisoLocation
    }

    END {}
}

<#
.SYNOPSIS
    Remove the CoreosISO from a VM.
#>
Function RemoveCoreosISO {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $VMName
    )

    BEGIN {
        $coreosisoLocation = GetCoreosISO
    }

    PROCESS {
        Get-VMDvdDrive -VMName $VMName -ControllerNumber 1 -ControllerLocation 0 | Remove-VMDvdDrive
    }

    END {}
}

<#
.SYNOPSIS
    Determine if a set of configs need an etcd token.
#>
Function TestEtcdTokenRequired {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true, ParameterSetName="SingleConfig")]
        [string] $Config,

        [Parameter (Mandatory=$true, ParameterSetName="MultipleConfigs")]
        [String[]] $Configs
    )

    BEGIN {}

    PROCESS { Write-Output $true }

    END {}
}

############################
###### Hack Functions ######
############################
<#
.SYNOPSIS
    Creates the necessary files and adds them to the coreos vm to automatically install or configure the vm.
#>
Function AddDynamicRun {
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
        $drisoLocation = GetDynamicrunISO
        $coreosisoLocation = GetCoreosISO
    }

    PROCESS {

        $drvhdlocation = Join-Path -Path $(Get-CoreosFilesDirectory) "$ClusterName\tmp\$VMName.vhdx"
        if (!(Test-Path(Split-Path -parent $drvhdlocation))) {
            New-Item (Split-Path -parent $drvhdlocation) -Type directory
        }

        # Create the vhd with the dynamic run configuration
        $vhd = New-VHD -Path $drvhdlocation -Dynamic -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT -Confirm:$false -Force
        Start-Sleep -s 1

        if ($Install) { & cmd /C "copy $(GetDynamicrunInstallFolder)\** $($vhd.DriveLetter):\" | Out-Null }
        if ($Reconfigure) { & cmd /C "copy $(GetDynamicrunReconfigureFolder))\** $($vhd.DriveLetter):\" | Out-Null }
        if ($Config) { & cmd /C "copy $Config $($vhd.DriveLetter):\cloud-config.yaml" | Out-Null }

        Dismount-VHD $drvhdlocation

        Get-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 | Remove-VMDvdDrive
        Get-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 | Remove-VMHardDiskDrive

        Add-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 -Path $drisoLocation
        Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 -Path $drvhdlocation
    }

    END {}
}

<#
.SYNOPSIS
    Removes the files from the vm created to automatically install or configure the vm so that it can be used.
#>
Function RemoveDynamicRun {
    [CmdletBinding()]
    Param (
        [String] $VMName
    )

    BEGIN {}

    PROCESS {
        Stop-VM -VMName $VMName -TurnOff | Out-Null

        $dynamicrunVhd = (Get-VMHardDiskDrive -VMName -ControllerNumber 1 -ControllerLocation 1)
        Get-VMDvdDrive -VMName $VMName -ControllerNumber 0 -ControllerLocation 1 | Remove-VMDvdDrive
        Get-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 | Remove-VMHardDiskDrive

        if ($dynamicrunVhd -and (Test-Path($dynamicrunVhd.Path))) {
            Remove-Item $dynamicrunVhd.Path -Force
        }
    }

    END {}
}


<#
.SYNOPSIS
    Currently experiencing an issue on first boot for coreos vms getting the correct network config. This function takes away the network adapters and starts the vm.
    It then turns off the VM and readds the network adapters. This allows the config to be loaded properly.
#>
Function PreStartCoreosVM {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [String] $VMName,

        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {}

    END {}
}

<#
.SYNOPSIS
    Currently experiencing an issue on first boot for coreos vms getting the correct network config. This function takes away the network adapters and starts the vm.
    It then turns off the VM and readds the network adapters. This allows the config to be loaded properly.
#>
Function PreStartCoreosCluster {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    BEGIN {}

    PROCESS {}

    END {}
}