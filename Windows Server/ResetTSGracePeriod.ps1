<#
.Synopsis
   Reset Terminal Services Grace period
.DESCRIPTION
   Resets the Terminal Services grace period if it's below 20 days left. This script should be run using
   a scheduled task (Task Manager) under the system account. If you place this script in C:\Temp you can import
   the xml file in Task Scheduler.
#>

$Threshold = 20
$GracePeriod = (Get-WmiObject -namespace root\cimv2\terminalservices -class win32_terminalservicesetting).GetGracePeriodDays()
If ($GracePeriod.DaysLeft -lt $Threshold)
{
    Remove-Item 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\RCM\GracePeriod' -Recurse
}
