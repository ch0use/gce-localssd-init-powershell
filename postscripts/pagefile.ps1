new-eventlog -logname System -source "pagefile"  -ErrorAction SilentlyContinue

write-host "$(get-date -format g) Disabling automatically managed pagefile"
$pagefile = Get-WmiObject Win32_ComputerSystem -EnableAllPrivileges
$pagefile.AutomaticManagedPagefile = $false
$pagefile.put() | Out-Null

Set-WmiInstance -Class Win32_PageFileSetting -Arguments @{name = "P:\pagefile.sys"; InitialSize = 0; MaximumSize = 0 } -EnableAllPrivileges | Out-Null
$logMsg = "$(get-date -format g) System-managed pagefile created at P:\pagefile.sys"
Write-Host $logMsg
write-eventlog -logname System -source "pagefile" -EntryType Information -eventid 1 -message $logMsg

(get-wmiobject win32_pagefilesetting | where-object -Property Name -like "C:\pagefile.sys").Delete()
$logMsg = "$(get-date -format g) Pagefile removed from C:\pagefile.sys"
Write-Host $logMsg
write-eventlog -logname System -source "pagefile" -EntryType Information -eventid 1 -message $logMsg

write-host "$(get-date -format g) Final pagefile config:"
get-wmiobject win32_pagefilesetting

# Host needs to be rebooted in order for Pagefile configuration to take effect.