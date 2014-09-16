############################
# Manage Cluster Functions #
############################
<#
.SYNOPSIS
    Creates and installs coreos on a cluster of virtual machines.
#>
Function New-CoreosCluster {
    [CmdletBinding(DefaultParameterSetName="NetworkConfigs_SingleConfig")]
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
        if (!(TestIsAdmin)) {
            throw "You must run as an administrator to run this script."
            return
        }

        $ClusterFilesDirectory = GetCoreosClusterDirectory -ClusterName:$Name

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
                $ConfigTemplatePath = Join-Path -Path (GetCoreosClusterDirectory -ClusterName:$Name) $ConfigTemplate

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
                NewVMInCoreosClusterInfo -ClusterInfo:$ClusterInfo -Config:$Configs[$i]
            } else {
                NewVMInCoreosClusterInfo -ClusterInfo:$ClusterInfo
            }
        }

        OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        CoreosClusterVMWorker -ClusterInfo:$ClusterInfo

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

        $ClusterInfo | Stop-CoreosCluster
        $ClusterInfo.VMs | where { $_.State -eq "Completed" } | foreach { $_.State = "Remove" }

        OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        CoreosClusterVMWorker -ClusterInfo:$ClusterInfo

        $ClusterFilesDirectory = GetCoreosClusterDirectory -ClusterName:$ClusterInfo.Name
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
        $infoFile = Join-Path -Path $(GetCoreosClustersDirectory) "$ClusterName\cluster-info.json"
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

        [Parameter (Mandatory=$false)]
        [int] $VMNumber,

        [Parameter (Mandatory=$false)]
        [String] $EtcdDiscoveryToken,

        [Parameter (Mandatory=$false)]
        [String] $ClusterName
    )

    PROCESS {
        if (!(Test-Path $Path)) {
            throw "Config doesn't exist"
        }

        if (Test-Path $Destination) {
            Move-Item -Path $Destination -Destination "$Destination.$(GetDateTimeStamp)_bak"
        }

        $vmnumber00 = $VMNumber.ToString("00")

        $cfg = Get-Content $Path | foreach { $_ -replace '{{VM_NAME}}', $VMName }
        if ($VMNumber -or $VMNumber -eq 0) { $cfg = $cfg | foreach { $_ -replace '{{VM_NUMBER}}', $VMNumber.ToString() } | foreach { $_ -replace '{{VM_NUMBER_00}}', $vmnumber00 } }
        if ($EtcdDiscoveryToken) { $cfg = $cfg | foreach { $_ -replace '{{ETCD_DISCOVERY_TOKEN}}', $EtcdDiscoveryToken } }
        if ($ClusterName) { $cfg = $cfg | foreach { $_ -replace '{{CLUSTER_NAME}}', $ClusterName } }

        $cfg | Out-UnixFile -Path $Destination

        Get-Item $Destination
    }
}

<#
.SYNOPSIS
    Gets a coreos files directory.
#>
Function Get-CoreosFilesDirectory {
    [CmdletBinding()]
    Param (
        
    )

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
}

<#
.SYNOPSIS
    Adds a new VM to the coreos cluster info.
#>
Function NewVMInCoreosClusterInfo {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo,

        [Parameter (Mandatory=$false)]
        [String] $Config
    )

    PROCESS {
        $VMNumber = ($ClusterInfo.VMs | Measure).Count + 1
        $VMNumber_00 = $VMNumber.ToString("00")

        $VMName = "$($ClusterInfo.Name)_$VMNumber_00"
        $ConfigTemplate = $null

        if ($Config) {
            if (Test-Path $Config) {
                $ConfigTemplate = "template_$VMNumber_00.yaml"
                $ConfigTemplatePath = Join-Path -Path (GetCoreosClusterDirectory -ClusterName:$($ClusterInfo.Name)) $ConfigTemplate

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
Function CoreosClusterVMWorker {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo
    )

    PROCESS {
        $ClusterFilesDirectory = GetCoreosClusterDirectory -ClusterName $ClusterInfo.Name
        $NetworkSwitchNames = @()
        $ClusterInfo.Config.Networks | foreach { $NetworkSwitchNames += $_.SwitchName }

        # Create the config files for the VMs
        if (($ClusterInfo.VMs | where { $_.State -eq "Queued" } | Measure).Count -gt 0) {
            Write-Verbose "Creating the Config Files for the VMs."

            $ClusterInfo.VMs | where { $_.State -eq "Queued" -and $_.ConfigTemplate -and -not $_.Config} | foreach {
                $ConfigTemplatePath = Join-Path -Path $ClusterFilesDirectory $_.ConfigTemplate
                $Config = "config_$($_.Number_00).yaml"
                $ConfigPath = Join-Path -Path $ClusterFilesDirectory $Config
                New-CoreosConfig -Path:$ConfigTemplatePath -Destination:$ConfigPath -VMName:$_.Name -ClusterName:$ClusterInfo.Name -VMNumber:$_.Number -EtcdDiscoveryToken:$ClusterInfo.Config.EtcdDiscoveryToken | Out-Null

                $_ | Add-Member Config $Config
            }

            OutCoreosClusterInfo -ClusterInfo $ClusterInfo

            # Create the VM
            Write-Verbose "Creating the VMs."
            $ClusterInfo.VMs | where { $_.State -eq "Queued" } | foreach {
                $VMName = $_.Name
                $vhdLocation = "$((Get-VMHost).VirtualHardDiskPath)\$VMName.vhd"

                # Create the VM
                $vm = New-VM -Name $VMName -MemoryStartupBytes 1024MB -NoVHD -Generation 1 -BootDevice CD -SwitchName $NetworkSwitchNames[0]
                $vm | Set-VMMemory -DynamicMemoryEnabled:$true
                $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $VMName -SwitchName $_ } | Out-Null
                $vhd = New-VHD -Path $vhdLocation -SizeBytes 10GB

                Add-VMHardDiskDrive -VMName $VMName -ControllerType IDE -ControllerNumber 0 -ControllerLocation 0 -Path $vhd.Path
                
                $_.State = "ReadyForInstall"
            }

            OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        if (($ClusterInfo.VMs | where { $_.State -eq "ReadyForInstall" } | Measure).Count -gt 0) {
            Write-Verbose "Installing Coreos on VMs."

            # Add Coreos Image and config to VM
            $ClusterInfo.VMs | where { $_.State -eq "ReadyForInstall" } | foreach {
                AddCoreosISO -VMName:$_.Name
                if ($_.Config) { AddDynamicRun -VMName:$_.Name -ClusterName:$ClusterInfo.Name -Config:$_.Config -Install }
                else { AddDynamicRun -VMName:$_.Name -ClusterName:$ClusterInfo.Name -Install }

                Start-VM -VMName $_.Name
                $_.State = "Installing"
            }

            OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        $Count = ($ClusterInfo.VMs | where { $_.State -eq "Installing" } | Measure).Count
        if ($Count -gt 0) {
            $timeout = GetInstallTimeout
            $timeout = $timeout + ($timeout/20)*$Count
            for ($i=1; $i -le $timeout; $i++) {
                Start-Sleep -s 1
                Write-Progress -Activity "Installing coreos to $Count VMs in Cluster $Name" -SecondsRemaining $($timeout - $i)
            }

            $ClusterInfo.VMs | where { $_.State -eq "Installing" } | foreach {
                Stop-VM -VMName $_.Name -TurnOff | Out-Null
                RemoveCoreosISO -VMName:$_.Name
                RemoveDynamicRun -VMName:$_.Name

                $_.State = "Installed"
            }

            OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        }

        if (($ClusterInfo.VMs | where { $_.State -eq "Installed" } | Measure).Count -gt 0) {
            Write-Verbose "Tidying up after install."

            $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
                Remove-VMNetworkAdapter -VMName:$_.Name
                Start-VM -VMName:$_.Name | Out-Null
            }

            $timeout = 60
            for ($i=1; $i -le $timeout; $i++) {
                Start-Sleep -s 1
                Write-Progress -Activity "Starting the VMs quickly so the configuration is properly loaded." -SecondsRemaining $($timeout - $i)
            }

            $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
                $VMName = $_.Name
                Stop-VM -VMName:$VMName | Out-Null
                $NetworkSwitchNames | Select-Object -Skip 1 | foreach { Add-VMNetworkAdapter -VMName $VMName -SwitchName $_ } | Out-Null
            }

            $ClusterInfo.VMs | Where { $_.State -eq "Installed" } | foreach {                
                $_.State = "Completed"
            }

            OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
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

            OutCoreosClusterInfo -ClusterInfo:$ClusterInfo
        }
    }
}

############################
### Independent Functions ##
############################
Function GetDateTimeStamp {
    [CmdletBinding()]
    Param (        
    )

    PROCESS {
        Get-Date -UFormat "%Y_%m_%d_%H_%M_%S" | Write-Output
    }
}

Function GetModuleFilesDirectory {
    [CmdletBinding()]
    Param (        
    )

    PROCESS {
        $MyInvocation.MyCommand.Module.FileList[0] | Write-Output
    }
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
}

<#
.SYNOPSIS
    Gets the time to wait for an install.
#>
Function GetInstallTimeout {
    [CmdletBinding()]
    Param (
    )

    PROCESS {
        if ($env:COREOS_HYPERV_INSTALL_TIMEOUT) {
            Write-Output $env:COREOS_HYPERV_INSTALL_TIMEOUT
        } else {
            Write-Output 180
        }
    }
}

<#
.SYNOPSIS
    Gets the clusters directory storing metadata about the clusters.
#>
Function GetCoreosClustersDirectory {
    [CmdletBinding()]
    Param (
    )

    PROCESS {
        Join-Path -Path $(Get-CoreosFilesDirectory) "Clusters"
    }
}

<#
.SYNOPSIS
    Gets the cluster directory storing metadata about the cluster.
#>
Function GetCoreosClusterDirectory {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    PROCESS {
        Join-Path -Path $(GetCoreosClustersDirectory) $ClusterName
    }
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
    Outputs a file with Unix line endings.
#>
Function Out-UnixFile {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true, ValueFromPipeline=$true)]
        $Content,

        [Parameter (Mandatory=$true)]
        $Path
    )

    BEGIN {
        $str = ""
    }

    PROCESS {
        $str += $Content + "`n"
    }

    END {
        [System.IO.File]::WriteAllText($Path,$str,[System.Text.Encoding]::ASCII)
    }
}

<#
.SYNOPSIS
    Write Coroes Cluster Info to file
#>
Function OutCoreosClusterInfo {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo
    )

    PROCESS {
        $outFile = "$(GetCoreosClustersDirectory)\$($ClusterInfo.Name)\cluster-info.json"
        $ClusterInfo | ConvertTo-Json -depth 4 | Out-File $outFile -Force
    }
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
        $drvhdlocation = Join-Path -Path $(GetCoreosClustersDirectory) "$ClusterName\tmp\$VMName.vhdx"
        if (!(Test-Path(Split-Path -parent $drvhdlocation))) {
            New-Item (Split-Path -parent $drvhdlocation) -Type directory | Out-Null
        }

        # Create the vhd with the dynamic run configuration
        $vhd = New-VHD -Path $drvhdlocation -Dynamic -SizeBytes 100MB | Mount-VHD -Passthru | Initialize-Disk -PartitionStyle MBR -PassThru | New-Partition -AssignDriveLetter -UseMaximumSize | Format-Volume -FileSystem FAT -Confirm:$false -Force
        Start-Sleep -s 1

        if ($Config) { $configPath = Join-Path -Path $(GetCoreosClusterDirectory -ClusterName $ClusterName) $Config }

        if ($Install) { & cmd /C "copy `"$(GetDynamicrunInstallFolder)\**`" $($vhd.DriveLetter):\" | Out-Null }
        if ($Reconfigure) { & cmd /C "copy `"$(GetDynamicrunReconfigureFolder))\**`" $($vhd.DriveLetter):\" | Out-Null }
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
Function RemoveDynamicRun {
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