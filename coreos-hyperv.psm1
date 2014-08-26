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

<#
.SYNOPSIS
    Creates a cluster of coreos vms.
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
    Creates a modified config file based on a base file and machine specific information.
#>
Function New-CoreosConfig {
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

Export-ModuleMember *-*