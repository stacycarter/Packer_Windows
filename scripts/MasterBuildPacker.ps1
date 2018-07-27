## Custom Master Packer Windows server build script, created by S. Carter.
## Review/Update the variable names and values in this script and the Windows Packer .json file you're using to make sure they all line up.
## Script is designed to work with VMs/templates that live on vSphere datastore clusters.
## Prior to kicking off Packer, this script will perform some rename/copy/migrate actions so that there is always at least one old copy of the vSphere template in vCenter (in case something with the new Packer image build goes wrong.)
## The folders that contain the old and new templates must have the templates (with the correct naming) before you kick off this script.
## This script will also obtain some required creds prior to kicking off Packer.


[cmdletbinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("Win2K16_SAD", "Win2K16_CORE")]
    $OSName,

    [Parameter(Mandatory=$true)]
    [ValidateSet("vCenterFQDN1", "vCenterFQDN2", "vCenterFQDN3", IgnoreCase = $true)]
    $vcenter_server
	)


# Set variables 
$env:PACKER_LOG = "1"  #to ensure Packer logging is enabled
$env:PACKER_LOG_PATH = "C:\Packer\PackerLogs\" + $OSName + "_Packerlog_" + $(get-date -f yyyy-MM-dd) + ".txt"  #this log file will be included as an attachment in the completion email
$WindowsPackerLogPath = "C:\Packer\PackerLogs\" + $OSName +  "_WinPackerScript_" + $(get-date -f yyyy-MM-dd) + ".txt"  #this log file will be included as an attachment in the completion email
$ScriptName = "MasterBuildPacker"
$DatastoreCluster = "enter datastore cluster name here" #needed to determine destination datastore for storage vmotioning old templates (renaming)
$OldTemplatesFolder = "Enter old templates folder name here"
$CurrentTemplatesFolder = "Enter current templates folder name here"
$Currenttemplate = $null
$Attachments = @()

# Dot source Write-Log function for logging
. C:\Packer\Write-Log.ps1

Write-Log -Path $WindowsPackerLogPath "The $ScriptName script is starting with $OSName and $vcenter_server as the parameters." 

Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -WebOperationTimeoutSeconds 600 -Confirm:$false

Function EmailAdmin 
{
    Param ([string]$Body)
    $From = "enter sender address here"
    $To = "enter recipient address here"
    $Subject = "Results for $OSName Packer image build"
    $Body += "`n `nAdd more email body here"
    $SMTPServer = "insert SMTP server name here"
    Send-MailMessage -From $From -to $To -Subject $Subject -Body $Body -SmtpServer $SMTPServer -Attachments $env:PACKER_LOG_PATH, $WindowsPackerLogPath –DeliveryNotificationOption OnSuccess
}

        ## The first part of this script will delete an older copy of the vSphere template from an old templates folder, rename and copy the current template to this folder.  
        ## This way if something goes wrong with the Packer build, you still have an old copy of the template in vCenter.
        if($global:DefaultVIServers) 
            {
                Disconnect-VIServer -Server $global:DefaultVIServers -Force -Confirm:$false
            }
        
        $vcenterServer = connect-viserver $vcenter_server 

        if(!($vcenterServer))
            {
                $EmailBody = "The $ScriptName script was not able to connect to $vcenter_server vCenter. Please investigate and re-run this script."
                Write-Log -Path $WindowsPackerLogPath $EmailBody
                EmailAdmin -Body $EmailBody
            }
        
        else
            {                 
                Write-Log -Path $WindowsPackerLogPath "The $ScriptName script connected to $vcenter_server vCenter successfully, moving to next step."
                # Get old template in $OldTemplatesFolder folder and delete it
                $Currenttemplate = get-folder $CurrentTemplatesFolder | get-template -name $OSName

                if (!($Currenttemplate))
                    {
                      $EmailBody = "The $ScriptName script was not able to find the existing $OSName template in the $CurrentTemplatesFolder folder.  " 
                      $EmailBody += "This script needs to first find the existing template, rename it with the prefix old-, and move it to the old templates folder before it creates the new one.  Please investigate and re-run this script."
                      Write-Log -Path $WindowsPackerLogPath $EmailBody
                      EmailAdmin -Body $EmailBody
                      Exit
                    }

                else
                    {
                        Write-Log -Path $WindowsPackerLogPath "The $ScriptName script found the existing template in $vcenter_server vCenter."
                        $OldName = "Old-" + $Currenttemplate.name
                        $OldTemplate = get-folder $OldTemplatesFolder | get-template -name $OldName 

                        if (!($OldTemplate))
                            {
                                $EmailBody = "The $ScriptName script was not able to find the $OldName template in the $OldTemplatesFolder folder.  " 
                                $EmailBody += "This script needs to find the old- template in the $OldTemplatesFolder folder and delete it so that it can clone the existing template to the $OldTemplatesFolder.  Please investigate and re-run this script."
                                Write-Log -Path $WindowsPackerLogPath $EmailBody
                                EmailAdmin -Body $EmailBody
                                Exit
                            }
                        
                        else
                            {
                                Write-Log -Path $WindowsPackerLogPath "The $ScriptName script was also able to find the $OldName template in the $OldTemplatesFolder in $vcenter_server vCenter."
                                $OldTemplate | remove-template -DeletePermanently -Confirm:$false
                                $OldTemplateStillExists = get-folder $OldTemplatesFolder | get-template -name $OldName
                                
                                if ($OldTemplateStillExists)
                                    {
                                        $EmailBody = "The $ScriptName script was not able to delete the old Windows template called $OldName from the $OldTemplatesFolder folder.  Please investigate and re-run this script."
                                        Write-Log -Path $WindowsPackerLogPath $EmailBody
                                        EmailAdmin -Body $EmailBody
                                        Exit
                                    }
                                
                                else
                                    {
                                        Write-Log -Path $WindowsPackerLogPath "The $ScriptName script was able to delete the old Windows template called $OldName from the $OldTemplatesFolder folder successfully."
                                        # Get the current datastore cluster for the template, determine the destination datastore to storage vMotion the template to for renaming purposes
                                        try
                                            {
                                            $DestinationDatastore = get-datastorecluster -template $Currenttemplate | get-datastore | Where-Object {(($_.name) -ne ($Currenttemplate.extensiondata.config.datastoreurl.name))} | Select-Object -First 1
                                            }
                                        catch
                                            {
                                            $EmailBody = "The $ScriptName script was not able to identify a destination datastore for the current template $($Currenttemplate.name). Please investigate and re-run this script."
                                            Write-Log -Path $WindowsPackerLogPath $EmailBody
                                            EmailAdmin -Body $EmailBody
                                            Exit
                                            }             

                                        # Rename and move templates from the $CurrentTemplatesFolder folder to the $OldTemplatesFolder folder and the $DestinationDatastore
                                        try
                                            {
                                            $Currenttemplate | set-template -name $OldName -confirm:$false
                                            get-template $OldName | set-template -tovm -confirm:$false
                                            get-vm $OldName | move-vm -Datastore $DestinationDatastore -Destination (Get-Folder $OldTemplatesFolder)
                                            get-vm $OldName | set-vm -totemplate -confirm:$false
                                            }
                                        catch
                                            { 
                                            $EmailBody = "The $ScriptName script was not able to rename $Currenttemplate.name to $OldName, move it to $DestinationDatastore and the $OldTemplatesFolder folder.  Please investigate and re-run this script."
                                            Write-Log -Path $WindowsPackerLogPath $EmailBody
                                            EmailAdmin -Body $EmailBody
                                            Exit
                                            }
                                    
                                        # Make sure that the old template was moved successfully to the folder where old templates are kept
                                        if (!(get-folder $OldTemplatesFolder | get-template $OldName))
                                            {
                                                $EmailBody = "The $ScriptName script tried to rename $Currenttemplate.name to $OldName, move it to the $OldTemplatesFolder folder."
                                                $EmailBody += " However, the query to see if the $OldName template now exists in the $OldTemplatesFolder folder failed. Something must have gone wrong.  Please investigate and re-run this script."
                                                Write-Log -Path $WindowsPackerLogPath $EmailBody
                                                EmailAdmin -Body $EmailBody
                                                Exit
                                            }
                                        else
                                            {
                                                Write-Log -Path $WindowsPackerLogPath "The $OSName template that was in the $CurrentTemplatesFolder folder was renamed with the prefix 'Old-' and moved to the $OldTemplatesFolder folder."
                                                
                                                if (!(get-datastore $DestinationDatastore | get-template $OldName))
                                                    {
                                                        $EmailBody = "The $ScriptName script tried to migrate the $OldName template to $DestinationDatastore as part of the renaming process."
                                                        $EmailBody += " However, the query to see if the $OldName template now exists on $DestinationDatastore failed. Something must have gone wrong.  Please investigate and re-run this script."
                                                        Write-Log -Path $WindowsPackerLogPath $EmailBody
                                                        EmailAdmin -Body $EmailBody
                                                        Exit
                                                    }
                                                else
                                                    {
                                                        Write-Log -Path $WindowsPackerLogPath "The $ScriptName script was able to successfully migrate the $OldName template to $DestinationDatastore as part of the renaming process."
                                                        Write-Log -Path $WindowsPackerLogPath "Now going to try and get credentials that will need to be passed to packer.exe..."

                                                        #Get credentials via PowerShell Rest API query
                                                        $vsphere_password = invoke-restmethod -Method Get -Uri insert_https_path_here -ErrorAction Stop
                                                        $vsphere_password = $vsphere_password.operation.Details.PASSWORD


                                                        #Get admin via PowerShell Rest API query
                                                        $admin_password = invoke-restmethod -Method Get -Uri insert_https_path_here -ErrorAction Stop
                                                        $admin_password = $admin_password.operation.Details.PASSWORD

                                                        $passwords = @{
                                                            localadmin_password = "$admin_password"
                                                            vsphere_password = "$vsphere_password"
                                                        }


                                                        switch ($OSName)
	                                                        {
		                                                        'Win2K16_SAD' 
			                                                        {
				                                                        $osData = @{
					                                                        os_name = 'Win2K16_SAD'
					                                                        vm_name = 'Win2K16_SAD'
					                                                        guest_os_type = 'windows9Server64Guest'
					                                                        iso_path = "NameofinstallationISO.ISO"
					                                                        }
			                                                        }

		                                                        'Win2K16_CORE' 
			                                                        {
				                                                        $osData = @{
					                                                        os_name = 'Win2K16_CORE'
					                                                        vm_name = 'Win2K16_CORE'
					                                                        guest_os_type = 'windows9Server64Guest'
					                                                        iso_path = "NameofinstallationISO.ISO"
					                                                        }
			                                                        }
	                                                        }

                                                        Write-Log -Path $WindowsPackerLogPath "This script will now try run Packer to create a new Windows vSphere golden template called $($osData.os_name)."

                                                        ## Start Packer processes
                                                        $startInfo = $NULL
                                                        $process = $NULL
                                                        $standardOut = $NULL

                                                        $startInfo = New-Object System.Diagnostics.ProcessStartInfo
                                                        $startInfo.FileName = "c:\packer\packer.exe"
                                                        $startInfo.WorkingDirectory = "C:\Packer"
                                                        $startInfo.Arguments = "build  -var `"vsphere_password=$($passwords.vsphere_password)`" -var `"admin_password=$($passwords.admin_password)`" -var `"vcenter_server=$($vcenter_server)`" -var `"os_name=$($osData.os_name)`" -var `"vm_name=$($osData.vm_name)`" -var `"guest_os_type=$($osData.guest_os_type)`" -var `"iso_path=$($osData.iso_path)`" .\packer-windowsserver.json"

                                                        $startInfo.RedirectStandardOutput = $true
                                                        $startInfo.UseShellExecute = $false
                                                        $startInfo.CreateNoWindow = $false

                                                        $process = New-Object System.Diagnostics.Process
                                                        $process.StartInfo = $startInfo
                                                        $process.Start() | Out-Null
                                                        $standardOut = $process.StandardOutput.ReadToEnd()
                                                        $process.WaitForExit()

                                                        # $standardOut should contain the results of packer.exe run
                                                        $standardOut


                                                        #Test to see if Packer successfully recreated $OSName template in $CurrentTemplatesFolder.
                                                        $Currenttemplate = $null
                                                        $Currenttemplate = get-folder $CurrentTemplatesFolder | get-template -name $OSName

                                                        if ($Currenttemplate)
                                                            {
                                                                $EmailBody += "The $OSName VMware template has been rebuilt using Packer. The log files are attached.  Please check to make sure all appropriate Windows updates installed successfully." 
                                                                Write-Log -Path $WindowsPackerLogPath $EmailBody
                                                                EmailAdmin -Body $EmailBody
                                                            }

                                                        else
                                                            {
                                                                $EmailBody += "The $OSName VMware template was not successfully rebuilt using Packer. Please investigate.  The log files are attached." 
                                                                Write-Log -Path $WindowsPackerLogPath $EmailBody
                                                                EmailAdmin -Body $EmailBody
                                                            }

                                                        ## Disconnect from vCenter server
                                                        Write-Log -Path $WindowsPackerLogPath "Disconnecting $vcenter_server session."
                                                        Disconnect-VIServer -Server $vcenter_server -Confirm:$false

                                                        }
                                                   }
                                               }
                                            }
                                    
                                        }  
                                }