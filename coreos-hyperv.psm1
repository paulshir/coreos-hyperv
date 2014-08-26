<#
.SYNOPSIS
    Creates a VM set up with the coreos ready for auto installation.
#>
Function New-CoreosInstallVM {
    [CmdletBinding()]
    Param (
        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [Alias("vmname")]
        [String] $Name,

        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [String[]] $NetworkSwitchNames,

        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$false)]
        [String] $Config
    )

    BEGIN {

        $switch = Get-VMSwitch -Name $NetworkSwitchNames[0] -ErrorAction:Stop

        $drlocation = GetDynamicRunFilesLocation

        $vhdLocation = "$((Get-VMHost).VirtualHardDiskPath)\$Name.vhd"
        $drisolocation = GetDynamicRunISOLocation
        $coreosisoLocation = GetCoreosISOLocation
        $drvhdlocation = "$(GetTmpFileLocation)\$Name.vhdx"
    }

    PROCESS {
        # Create the vhd with the dynamic run configuration
        $vhd = New-VHD -Path $drvhdlocation -Dynamic -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT -Confirm:$false -Force
        Start-Sleep -s 1

        & cmd /C "copy $drlocation\** $($vhd.DriveLetter):\" | Out-Null
        if ($Config) {
            & cmd /C "copy $conifg $($vhd.DriveLetter):\" | Out-Null
        }

        Dismount-VHD $drvhdlocation

        # Create the VM
        $vm = New-VM -Name $Name -MemoryStartupBytes 1024MB -NoVHD -Generation 1 -BootDevice CD -SwitchName $switch.Name
        $vm | Set-VMMemory -DynamicMemoryEnabled:$true
        $vhd = New-VHD -Path $vhdLocation -SizeBytes 10GB

        Add-VMHardDiskDrive -VMName $Name -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhd.Path
        Add-VMDvdDrive -VMName $Name -ControllerNumber 0 -ControllerLocation 1 -Path $drisolocation
        Set-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 0 -Path $coreosisoLocation
        Add-VMHardDiskDrive -VMName $Name -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 -Path $drvhdlocation

        Remove-Item "$(GetTmpFileLocation)\$Name.vhdx" -Force
        
        Write-Output (Get-VM -Name $Name)
    }

    END {}
}

<#
.SYNOPSIS
    Creates a new vm with coreos installed on it.
#>
Function New-CoreosVM {
    [CmdletBinding()]
    Param (
        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [Alias("vmname")]
        [String] $Name,

        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [String[]] $NetworkSwitchNames,

        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$false)]
        [String] $Config
    )

    BEGIN {
        $NetworkSwitchNames | foreach { Get-VMSwitch -Name $_ -ErrorAction:Stop} | Out-Null
    }

    PROCESS {
        # Create an install vm and start it.
        $vm = New-CoreosInstallVM -Name:$Name -NetworkSwitchNames:$NetworkSwitchNames -Config:$Config
        Start-VM $vm | Out-Null

        # Blindly wait for install to complete. Need to come up with some way of monitoring this.
        $timeout = GetInstallTimeout
        for ($i=0; $i -lt $timeout; $i++) {
            Write-Progress -Activity "Installing coreos to VM $Name" -SecondsRemaining $($timeout - $i)
            Start-Sleep -s 1 
        }        

        NewCoreosVMAfterInstall -Name:$Name -NetworkSwitchNames:$NetworkSwitchNames
    }

    END {}
}

<#
.SYNOPSIS
    Creates a cluster of coreos vms.
#>
Function New-CoreosCluster {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [Alias("ClusterName")]
        [String] $Name,

        [Parameter (Mandatory=$true)]
        [int] $Count,

        [Parameter (Mandatory=$true)]
        [String[]] $NetworkSwitchNames,

        [Parameter (Mandatory=$false, ParameterSetName="SingleConfig")]
        [string] $Config,

        [Parameter (Mandatory=$false, ParameterSetName="MultipleConfigs")]
        [String[]] $Configs,

        [Parameter (Mandatory=$false)]
        [Switch] $InstallInParallel=$false,

        [Parameter (Mandatory=$false)]
        [Switch] $GenerateEtcdDiscoveryToken
    )

    BEGIN {
        $NetworkSwitchNames | foreach { Get-VMSwitch -Name $_ -ErrorAction:Stop} | Out-Null
        if ($Configs -and $Configs.length -ne $Count) { throw "Number of config files doesn't match the count in the cluster" }
    }

    PROCESS {
        $token = null
        if ($GenerateEtcdDiscoveryToken) {
            $token = New-EtcdDiscoveryToken    
        }


        for ($i = 1; $i -le $Count; $i++) {
            $VMName = "$Name_$($i.ToString("00"))"
            $editedConfig
            if ($Config) {
                $editedConfig = New-CoreosConfig -Config:$Config -Name:$VMName -VMNumber:$i -E
            } elseif ($Configs) {
                $editedConfig = New-CoreosConfig -Config:$Configs[$($i - 1)] -Name:$VMName -VMNumber:$i
            }

            if ($InstallInParallel) {
                New-CoreosInstallVM -Name:$VMName -NetworkSwitchNames:$NetworkSwitchNames -Config:$editedConfig
            } else {
                New-CoreosVM -Name:$VMName -NetworkSwitchNames:$NetworkSwitchNames -Config:$editedConfig
            }
        }

        if ($InstallInParallel) {
            for ($i = 1; $i -le $Count; $i++) {
                $VMName = "$Name_$($i.ToString("00"))"
                Start-VM $VMName
            }

            # Blindly wait for install to complete. Need to come up with some way of monitoring this.
            # Adding some extra time for running in parallel.
            $timeout = GetInstallTimeout
            $timeout = $timeout + ($timeout/10)*$Count
            for ($i=0; $i -lt $timeout; $i++) {
                Write-Progress -Activity "Installing coreos to $Count VMs in Cluster $Name" -SecondsRemaining $($timeout - $i)
                Start-Sleep -s 1 
            }

            for ($i = 1; $i -le $Count; $i++) {
                $VMName = "$Name_$($i.ToString("00"))"
                NewCoreosVMAfterInstall -Name:$VMName -NetworkSwitchNames:$NetworkSwitchNames
            }   
        }
    }

    END {}
}

<#
.SYNOPSIS
    Creates a modified config file based on a base file and machine specific information.
#>
Function New-CoreosConfig {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
        [String] $Config,

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
        if (!(Test-Path $Config)) {
            throw "Config doesn't exist"
        }

        $outdir = "$(GetTmpFileLocation)\conifgs"
        if (!(Test-Path $outdir)) {
            mkdir $outdir | Out-Null
        }

        $outConfig = "$outdir\$vmname"

        $vmnumber00 = $VMNumber.ToString("00")
    }

    PROCESS {
        $cfg = Get-Content $Config | foreach { $_ -replace '${VM_NAME}', $VMName }
        if ($VMNumber) { $cfg = $cfg | foreach { $_ -replace '${VM_NUMBER}', $VMNumber} | foreach { $_ -replace '${VM_NUMBER_00}', $vmnumber00 } }
        if ($EtcdDiscoveryToken) { $cfg = $cfg | foreach { $_ -replace '${ETCD_DISCOVERY_TOKEN}', $EtcdDiscoveryToken } }
        if ($ClusterName) { $cfg = $cfg | foreach { $_ -replace '${CLUSTER_NAME}', $ClusterName } }

        $cfg | Out-File $outConfig
    }

    END {}
}

<#
.SYNOPSIS
    Get the coreos iso.
#>
Function Get-CoreosISO {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $path,

        [Parameter (Mandatory=$true, ParameterSetName="stable")]
        [Switch] $Stable,
        
        [Parameter (Mandatory=$true, ParameterSetName="beta")]
        [Switch] $Beta,

        [Parameter (Mandatory=$true, ParameterSetName="alpha")]
        [Switch] $Alpha
    )

    BEGIN {}

    PROCESS {
        if ($Stable) {
            $address = 'http://stable.release.core-os.net/amd64-usr/current/coreos_production_iso_image.iso'
        } elseif ($Beta) {
            $address = 'http://beta.release.core-os.net/amd64-usr/current/coreos_production_iso_image.iso'
        } elseif ($Alpha) {
            $address = 'http://alpha.release.core-os.net/amd64-usr/current/coreos_production_iso_image.iso'
        }

        Invoke-WebRequest -Uri $address -OutFile $path
    }

    END {}
} 

<#
.SYNOPSIS
    Get a discovery token for etcd.
#>
Function New-EtcdDiscoveryToken {
    $wr = New-WebRequest -Uri "https://discovery.etcd.io/net"
    Write-Output $wr.Content
}

Function GetCoreosISOLocation {
    if ($env:COREOS_HYPERV_COREOS_ISO) {
        $coreosiso = $env:COREOS_HYPERV_COREOS_ISO
    } else {

        $coreosiso = "$(GetTmpFileLocation)\coreos_production_iso_image.iso"
    }

    if (!(Test-Path $coreosiso)) {
        Get-CoreosISO -Alpha -Path $coreosiso | Out-Null
    }

    Write-Output $coreosiso
}

Function GetDynamicRunISOLocation {
    if ($env:COREOS_HYPERV_DYNAMICRUN_ISO) {
        $driso = $env:COREOS_HYPERV_DYNAMICRUN_ISO
    } else {
        $moduleLocation = split-path (Get-Module coreos-hyperv).Path -parent
        $driso = "$moduleLocation\iso\config2.iso"
    }

    Write-Output $driso
}

Function GetDynamicRunFilesLocation {
    if ($env:COREOS_HYPERV_DYNAMICRUN_FILES) {
        $dynamicrunFiles = $env:COREOS_HYPERV_DYNAMICRUN_FILES
    } else {
        $moduleLocation = split-path (Get-Module coreos-hyperv).Path -parent
        $dynamicrunFiles = "$moduleLocation\dynamicrun"
    }

    Write-Output $dynamicrunFiles
}

Function GetTmpFileLocation {
    if ($env:COREOS_HYPERV_TMP_LOCATION) {
        $tmp = $env:COREOS_HYPERV_TMP_LOCATION
    } else {
        $moduleLocation = split-path (Get-Module coreos-hyperv).Path -parent
        $tmp = "$moduleLocation\tmp"
    }

    if (!(Test-Path $tmp)) {
        mkdir $tmp | Out-Null
    }

    Write-Output $tmp
}

Function GetInstallTimeout {
    if ($env:COREOS_HYPERV_INSTALL_TIMEOUT) {
        Write-Output $env:COREOS_HYPERV_INSTALL_TIMEOUT
    } else {
        Write-Output 200
    }
}

Function NewCoreosVMAfterInstall {
    [CmdletBinding()]
    Param (
        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [Alias("vmname")]
        [String] $Name,

        [Parameter (ValueFromPipelineByPropertyName=$true, Mandatory=$true)]
        [String[]] $NetworkSwitchNames
    )

    BEGIN {
        $NetworkSwitchNames | foreach { Get-VMSwitch -Name $_ -ErrorAction:Stop} | Out-Null
    }

    PROCESS {
        # Configure VM properly after install
        Stop-VM $vm -TurnOff | Out-Null

        Remove-VMDvdDrive -VMName $Name -ControllerNumber 0 -ControllerLocation 1
        Remove-VMDvdDrive -VMName $Name -ControllerNumber 1 -ControllerLocation 0
        Remove-VMHardDiskDrive -VMName $Name -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1

        $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $Name -SwitchName $_ } | Out-Null

        Write-Output (Get-VM -Name $Name)
    }

    END {}
}

Export-ModuleMember *-*