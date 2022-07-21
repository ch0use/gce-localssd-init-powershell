<#
  .SYNOPSIS
  Check if defined drive letters exist, recreate them if they do not.
  .DESCRIPTION
  This script should be run at every boot.
  
  Check if defined drive letters exist, recreate them if they do not. 
  
  A new storage pool with simple (striped) resiliency is created using the configured quantity of Local SSDs required. 
  
  A new volume is created in the new storage pool using the configured friendly name, all available space, the configured NTFS allocation size , and mounted at the configured drive letter. 
  
  An optional external post script is run after the volume is created which can perform additional configuration such as changing the Pagefile to use the new volume, or maybe restart SQL Server service.
  .EXAMPLE
  .\localssd_init.ps1
  .NOTES
  Configure $LocalSSDConfig entries below with the Name, DriveLetter, LocalSSDQty, NTFSAlloc, and PostScript
  - Name: Friendly name to use, should be short, without spaces
  - DriveLetter: The Drive letter where the Local SSD volume should be mounted.
  - LocalSSDQty: The quantity of Local SSD disks to use for the volume. Each disk is 375 GB in size.
  - NTFSAlloc: The NTFS allocation unit size to use when formatting the volume. Best practice: 65536 (64K) for Pagefile, 8192 (8K) for SQL Server Temp DB. Express numbers as Bytes.
  - PostScript: Path to external powershell script to run after the volume is successfully recreated. This script could do additional tasks such as configuring the Pagefile or restarting SQL Server service.

  Script logs actions to the System Event Log under the 'localssd_init' source and Event ID 1.

  localssd_init.txt and DATALOSS.txt are written to the root of newly created volumes.

  To configure this script to run at Startup, place it and any other PostScript scripts in a folder and then run the following commands:
  Set-ExecutionPolicy RemoteSigned
  $path="C:\path\to\localssd_init.ps1"
  $trigger = new-jobtrigger -atstartup -randomdelay 00:00:10 (adjust random delay of 10 seconds as necessary)
  register-scheduledjob -trigger $trigger -filepath $path -name localssd_init
  get-scheduledjob (confirm job is listed)
  Reboot the server when convenient
  get-job -name localssd_init (should have entries for each time the script ran at Startup)
#>

[OutputType([string])]
$ErrorActionPreference = "Continue"
$VerbosePreference = "Continue"

# Create our event log source
new-eventlog -logname System -source "localssd_init"  -ErrorAction SilentlyContinue

# Define our custom class
class LocalSSDVol { [string]$Name; [string]$DriveLetter; [int]$LocalSSDQty; [string]$NTFSAlloc; [string]$PostScript }

################################################
# CONFIGURE THE REQUIRED LOCAL SSD VOLUMES HERE
$LocalSSDConfig = @(
    [LocalSSDVol]@{Name = "SQLTempDB"; DriveLetter = 'E'; LocalSSDQty = 2; NTFSAlloc = '65536' },
    [LocalSSDVol]@{Name = "Pagefile"; DriveLetter = 'P'; LocalSSDQty = 2; NTFSAlloc = '8192'; PostScript = "C:\path\to\pagefile.ps1" }
)
################################################

# Recreate a given volume using the $LocalSSDConfig object having the DriveLetter, LocalSSDQty, NTFSAlloc, and PostScript.
function RecreateVol {
    $LocalSSDVol = $args[0]

    # Make sure we have available Local SSDs present, which show under "nvme_card" and have a specific size. This will not include Persistent Disks.
    try { $LocalSSDdisks = Get-PhysicalDisk -canpool $true -FriendlyName "nvme_card"  | where-object { $_.Size -eq 402653184000 } | select-object -First $LocalSSDVol.LocalSSDQty }
    catch {
        $logMsg = "$(get-date -format g) Not enough Local SSDs are available to recreate $($LocalSSDVol.Name) $($LocalSSDVol.DriveLetter)!"
        write-eventlog -logname System -source "localssd_init" -EntryType Error -eventid 1 -message $logMsg
        throw $logMsg
        exit 1
    }

    # Create the storage poool and new volume.
    try { $vol = New-StoragePool -FriendlyName $LocalSSDVol.Name -StorageSubSystemFriendlyName "Windows Storage on localssd" -ResiliencySettingNameDefault "Simple" -ProvisioningTypeDefault "Fixed" -PhysicalDisks $LocalSSDdisks | New-Volume -FriendlyName $LocalSSDVol.Name -AccessPath "$($LocalSSDVol.DriveLetter):" -FileSystem NTFS -AllocationUnitSize $LocalSSDVol.NTFSAlloc -UseMaximumSize }
    catch {
        $logMsg = "$(get-date -format g) Failed to create Storage Pool or Volume: $($_.Exception.Message)"
        write-eventlog -logname System -source "localssd_init" -EntryType Error -eventid 1 -message $logMsg
        throw $logMsg
    }

    # If the volume was created successfully, run the PostScript, if present.
    if ($null -ne $vol) {
        $logMsg = "$(get-date -format g) Volume $($LocalSSDVol.DriveLetter) $($LocalSSDVol.Name) was missing and recreated successfully."
        Write-Host $logMsg
        write-eventlog -logname System -source "localssd_init" -EntryType Warning -eventid 1 -message $logMsg
        $logMsg | out-file -FilePath "$($LocalSSDVol.DriveLetter):\localssd_init.txt"
        "DATA LOSS RISK ON THIS EPHEMERAL VOLUME" | out-file -FilePath "$($LocalSSDVol.DriveLetter):\DATALOSS.txt"

        if ($null -ne $LocalSSDVol.PostScript) {
            Write-Host "Calling post script $($LocalSSDVol.PostScript)"
            Invoke-Expression $LocalSSDVol.PostScript
        }
    }
}

# Main engine start

# Check if the Local SSD drive letters already exist, recreate them if they don't
$LocalSSDConfig | ForEach-Object {
    $LocalSSD = $_

    Write-Host "$(get-date -format g) Checking for $($LocalSSD.Name) drive $($LocalSSD.DriveLetter)"

    try { $Vol = Get-Volume -DriveLetter $LocalSSD.DriveLetter -ErrorAction Stop }
    catch {
        Write-Warning "$(get-date -format g) Drive $($LocalSSD.Name) $($LocalSSD.DriveLetter) does not exist. Recreating..."

        RecreateVol $LocalSSD
    }

    if ($null -ne $Vol) { 
        $logMsg = "$(get-date -format g) Drive $($LocalSSD.Name) $($LocalSSD.DriveLetter) exists." 
        Write-Host $logMsg
        write-eventlog -logname System -source "localssd_init" -EntryType Information -eventid 1 -message $logMsg
    }
}
