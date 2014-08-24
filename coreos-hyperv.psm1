<#
.SYNOPSIS
    Creates a VM set up with the coreos ready for auto installation.
#>
Function New-CoreosInstallVM {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $Name,

        [Parameter (Mandatory=$true)]
        [String] $coreosiso,

        [Parameter (Mandatory=$false)]
        [int] $VMIndex=0,

        [Parameter (Mandatory=$false)]
        [String] $config
    )

    BEGIN {
        $thisDir = split-path (Get-Module coreos-hyperv).Path -parent
        $vhdDir = (Get-VMHost).VirtualHardDiskPath
        $vmName = "$($Name)_$($VMIndex)"
        $driso = "$thisDir\iso\config2.iso"
    }

    PROCESS {
        # Update the config

        # Create the vhd with the dynamic run configuration
        $drvhdpathDir = "$thisDir\tmp"
        if (!(Test-Path $drvhdpathDir)) {
            mkdir $drvhdpathDir
        }

        $drvhdpath = "$drvhdpathDir\$vmName.vhdx"

        $vhd = New-VHD -Path $drvhdpath -Dynamic -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT -Confirm:$false -Force
        Start-Sleep -s 1
        & cmd /C "copy $thisDir\dynamicrun\** $($vhd.DriveLetter):\" > out-null
        if ($config) {
            & cmd /C "copy $conifg $($vhd.DriveLetter):\"
        }

        Dismount-VHD $drvhdpath

        # Create the VM
        $vm = New-VM -Name $vmName -MemoryStartupBytes 1024MB -NoVHD -Generation 1 -BootDevice CD
        $vm | Set-VMMemory -DynamicMemoryEnabled:$true
        $vhd = New-VHD -Path "$vhdDir\$vmName.vhd" -SizeBytes 10GB

        Add-VMHardDiskDrive -VMName $vmName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhd.Path
        Add-VMDvdDrive -VMName $vmName -ControllerNumber 0 -ControllerLocation 1 -Path $driso -AllowUnverifiedPaths
        Set-VMDvdDrive -VMName $vmName -ControllerNumber 1 -ControllerLocation 0 -Path $coreosiso -AllowUnverifiedPaths        
        Add-VMHardDiskDrive -VMName $vmName -ControllerType IDE -ControllerNumber 1 -ControllerLocation 1 -Path $drvhdpath
        
        Write-Output (Get-VM -Name $vmName)
    }

    END {}
} 


        