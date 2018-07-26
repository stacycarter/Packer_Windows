REM Calling PowerShell cleanup script
REM Running it via Windows Shell versus PowerShell provisioner because the PowerShell provisioner creates Scheduled Tasks when running scripts, and these were getting left behind by Packer ie bug.

Powershell.exe -executionpolicy remotesigned -File A:\cleanup.ps1