$Logfile = "C:\Windows\Temp\win-updates.log"

function LogWrite {
   Param ([string]$logstring)
   $now = Get-Date -format s
   Add-Content $Logfile -value "$now $logstring"
   Write-Host $logstring
}


#Disable IPv6 for network adapter
Try
{
LogWrite "Disabling IPv6 on network adapter"
Disable-NetAdapterBinding -InterfaceDescription "vmxnet3 ethernet adapter" -ComponentID ms_tcpip6
}

Catch
{
LogWrite "Error encountered when running Disable_IPv6.ps1 script. Review script and build to determine what went wrong."
}