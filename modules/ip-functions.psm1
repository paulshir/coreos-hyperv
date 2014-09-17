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
