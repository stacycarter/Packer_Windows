# Set log file path (log file should already exist from earlier script)
$Logfile = "C:\Windows\Temp\win-updates.log"

function LogWrite {
   Param ([string]$logstring)
   $now = Get-Date -format s
   Add-Content $Logfile -value "$now $logstring"
   Write-Host $logstring
}

LogWrite "The cleanup.ps1 script is starting..."

# Disable auto-logon
Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon' -Name AutoLogonCount -Value 0

LogWrite "Disabled auto-logon."

# Delete MRT.exe if it exists. MSRT (malicious software removal tool) gets picked up as vulnerability.
$MSRTPath = 'C:\Windows\System32\MRT.exe'

# Write the current version of VMware Tools to the win-updates.log
try
    {
        $ToolsVersion = & 'C:\Program Files\VMware\VMware Tools\VMwareToolboxCmd.exe' -v
        LogWrite "VMware Tools version on this build is $ToolsVersion."
    }
catch
    {
        LogWrite "Error occurred when the cleanup.ps1 script attempted to get the VMware Tools version in the guest OS of the build. Please investigate."
    } 

# JetBrains Packer plugin seems to be leaving remnant tasks in Task Scheduler.  Check for tasks and delete any that start with the name Packer.
$PackerTasks = get-scheduledtask -TaskName Packer*
if ($PackerTasks)
    {
        try
            {
                LogWrite "One or more Packer tasks found in Task Scheduler."  
                LogWrite "Deleting the following task(s): $($PackerTasks.taskname)"
                $PackerTasks | unregister-scheduledtask -confirm:$false
            }
        catch
            {
               LogWrite "Error occurred when the cleanup.ps1 script attempted to unregister remnant Packer* tasks.  Please investigate."
            } 
    }


if (Test-Path $MSRTPath)
    {
    try
        {
            LogWrite "$MSRTPath does exist.  Deleting it because the Malicious software removal tool is known to get picked up by security scanner as vulnerability."
            Remove-Item $MSRTPath -Force
        }
    catch
        {
            LogWrite "$MyInvocation.ScriptName found that $MSRTPath exists, however an error occurred when the script tried to delete this file.  Please power on image and investigate."
        }
    }
else
    {
    LogWrite "Verified that the file $MSRTPath does not exist."
    }


# Send email with a copy of the win-updates log someone 
$From = "sender"
$To = "recipient"
$Subject = "Win-updates log file from $env:computername Packer image build"
$Body = "Please review the attached file and confirm that no errors were encountered during the execution of the Packer Builder/Provisioner scripts for $env:computername."
$Body += "`n `nEnter more here"
$Attachment = $Logfile
$SMTPServer = "enter FQDN here"
Send-MailMessage -From $From -to $To -Subject $Subject -Body $Body -SmtpServer $SMTPServer -att $Attachment –DeliveryNotificationOption OnSuccess






