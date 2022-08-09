# localssd_init.ps1

## Synopsis
Check if defined drive letters exist, recreate them if they do not.

## Description
The `localssd_init.ps1` script should be run at every Windows startup on any GCE instances which have ephemeral Local SSDs. When a GCE instance with Local SSDs is shutdown from within the OS, the GCE instance will power off and data on those ephemeral Local SSDs is lost, including the volume configuration and mapped drive letter. 

At Startup, this script will check if specific drive letters exist and recreate them using available Local SSDs if they do not. 

A new storage pool with simple (striped) resiliency is created using the configured quantity of Local SSDs required. 

A new volume is created in the new storage pool using the configured friendly name, all available space, the configured NTFS allocation size, and mounted at the configured drive letter. 

An optional external post script is run after the volume is created which can perform additional configuration such as changing the Pagefile to use the new volume, or restart SQL Server service in case of TempDB stored on Local SSD.

## Run
`.\localssd_init.ps1`

## Notes
Configure `$LocalSSDConfig` entries in the `localssd_init.ps1` script with the following required values:
- `Name`: Friendly name to use, should be short, without spaces
- `DriveLetter`: The Drive letter where the Local SSD volume should be mounted.
- `LocalSSDQty`: The quantity of Local SSD disks to use for the volume. Each disk is 375 GB in size.
- `NTFSAlloc`: The NTFS allocation unit size to use when formatting the volume. Express numbers as Bytes. Best practice: 65536 (64K) for Pagefile volume, 8192 (8K) for SQL Server Temp DB volume.
- `PostScript`: Optional path to external powershell script to run after the volume is successfully recreated. This script could run tasks such as configuring the Pagefile or restarting SQL Server service.

`localssd_init.ps1` logs entries to the Windows System Event Log under the `localssd_init` source and Event ID 1.

`localssd_init.txt` and `DATALOSS.txt` are written to the root of newly created volumes indicating the time the volume was recreated and a warning about the ephemeral nature of the volume.

## Startup
To configure this script to run at Startup, place it and any other Postscript scripts in a folder and then run the following commands:

```
Set-ExecutionPolicy RemoteSigned
$path="C:\path\to\localssd_init.ps1"
$trigger = new-jobtrigger -atstartup -randomdelay 00:00:10
register-scheduledjob -trigger $trigger -filepath $path -name localssd_init
get-scheduledjob
```

Reboot the server when convenient and then run `get-job -name localssd_init` to see entries for each time the script ran at Startup, or check the Windows System Event Log.

# Postscripts
The [postscripts](postscripts/) folder has sample scripts that can be used. They can be customized as needed.