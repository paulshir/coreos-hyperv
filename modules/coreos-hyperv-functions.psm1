############################
#### External Functions ####
############################
<#
.SYNOPSIS
    Gets a coreos files directory.
.DESCRIPTION
    Gets the directory that information about coreos clusters and the virtual machines,
    and other files in relation to cluster generation are stored.
.OUTPUTS
    Returns the directory object where the files are stored.
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

############################
###### Get Functions #######
############################
Function Get-DateTimeStamp {
    [CmdletBinding()]
    Param (        
    )

    PROCESS {
        Get-Date -UFormat "%Y_%m_%d_%H_%M_%S" | Write-Output
    }
}

Function Get-ModuleFilesDirectory {
    [CmdletBinding()]
    Param (        
    )

    PROCESS {
        (Get-Module coreos-hyperv).FileList[0] | Write-Output
    }
}

<#
.SYNOPSIS
    Gets the clusters directory storing metadata about the clusters.
#>
Function Get-CoreosClustersDirectory {
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
Function Get-CoreosClusterDirectory {
    [CmdletBinding()]
    Param (
        [Parameter (Mandatory=$true)]
        [String] $ClusterName
    )

    PROCESS {
        Join-Path -Path $(Get-CoreosClustersDirectory) $ClusterName
    }
}

Function Get-ImageDirectory {
    [CmdletBinding()]
    Param (
    )

    PROCESS {
        $path = Join-Path -Path $(Get-CoreosFilesDirectory) "Images"

        if (Test-Path $path) {
            Get-Item $path
        } else {
            New-Item $Path -Type directory
        }
    }
}

############################
## Other General Functions #
############################

<#
.SYNOPSIS
    Tests if the current user is runnign as an administrator.
#>
Function Test-IsShellAdmin {
    ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
}

<#
.SYNOPSIS
    Write Coroes Cluster Info to file
#>
Function Out-CoreosClusterInfo {
    [CmdletBinding()]
    Param(
        [Parameter (Mandatory=$true)]
        [PSObject] $ClusterInfo
    )

    PROCESS {
        $outFile = "$(Get-CoreosClustersDirectory)\$($ClusterInfo.Name)\cluster-info.json"
        $ClusterInfo | ConvertTo-Json -depth 4 | Out-File $outFile -Force
    }
}