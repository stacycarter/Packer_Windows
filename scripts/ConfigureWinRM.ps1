# Modify WinRM service config (temporarily) in order for Packer to communicate with the server to finish building the image.
# Not a good idea to keep this set to "true" for VMs provisioned from this Packer image.
# This can be reversed for VMs provisioned from this template via a server group policy.

$Logfile = "C:\Windows\Temp\win-updates.log"

function LogWrite {
   Param ([string]$logstring)
   $now = Get-Date -format s
   Add-Content $Logfile -value "$now $logstring"
   Write-Host $logstring
}

LogWrite "The ConfigureWinRM.ps1 script is attempting to set the WinRM service config (temporarily) to allow unencrypted communication in order for Packer to successfully finish building the image."
LogWrite "This can be reversed for VMs provisioned from this template via a server group policy."

try
{
winrm quickconfig -quiet
winrm set winrm/config/service '@{AllowUnencrypted="true"}'
}

catch
{
LogWrite "Error occurred when the ConfigureRM.ps1 script attempted to set the winrm service to AllowUnencrypted=true."
}