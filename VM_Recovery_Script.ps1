########################################################################################################################
# Start of the script - Description, Requirements & Legal Disclaimer
########################################################################################################################
# Developed for Rubrik
################################################
# Description:
# This script runs a Recovery Plan for VMs protected by Cloud
################################################ 
# Requirements:
# - Run PowerShell as administrator with command "Set-ExecutionPolcity unrestricted" on the host running the script
# - A Cloud cluster or EDGE appliance, network access to it and credentials to login
# - A CSV with the following fields: VMName,Action,DisableNetwork,RemoveNetworkDevices,PowerOn,RunScriptsinLiveMount,PreFailoverScript,PostFailoverScriptDelay,PostFailoverScript,NextVMFailoverDelay,PreFailoverUserPrompt,PostFailoverUserPrompt
# - Example CSV Line = FileServer1,LiveMount,TRUE,FALSE,TRUE,FALSE,,0,,30,Are you bloody sure?,Has the VM come online?
# - Valid options for Action are LiveMount, InstantRecover, recommended to use LiveMount first to validate recovery
# - The options DisableNetwork,PowerOn,RunScriptsinLiveMount are only used LiveMount operations 
# - Valid options for DisableNetwork,RemoveNetworkDevices,PowerOn,RunScriptsinLiveMount are TRUE or FALSE
# - Valid options for PostFailoverScriptDelay,NextVMFailoverDelay is 0 - any number of seconds
# - If no script is specified for PreFailoverScript,PostFailoverScript then nothing is run
# - If no user prompt is specified for PreFailoverUserPrompt,PostFailoverUserPrompt then the user isn't prompted, this choice can be made per VM
# - This script always fails over to the latest snapshot available
################################################
# Legal Disclaimer:
# This script is written by Joshua Stenhouse is not supported under any support program or service. 
# All scripts are provided AS IS without warranty of any kind. 
# The author further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. 
# The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
# In no event shall its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if the author has been advised of the possibility of such damages.
################################################
# Configure the variables below for the Cloud Cluster
################################################
$CloudCluster = "192.168.0.200"
$RecoveryPlanCSV = "C:\Scripts\CloudRecoveryPlan\CloudRecoveryPlan.csv"
$LogDirectory = "C:\Scripts\CloudRecoveryPlan\"
# Prompting for username and password to authenicate, can set manually to remove human interaction
$Credentials = Get-Credential -Credential $null
$CloudUser = $Credentials.UserName
$Credentials.Password | ConvertFrom-SecureString
$CloudPassword = $Credentials.GetNetworkCredential().password
########################################################################################################################
# Nothing to configure below this line - Starting the main function of the script
########################################################################################################################
# Adding certificate exception to prevent API errors
################################################
add-type @"
    using System.Net;
    using System.Security.Cryptography.X509Certificates;
    public class TrustAllCertsPolicy : ICertificatePolicy {
        public bool CheckValidationResult(
            ServicePoint srvPoint, X509Certificate certificate,
            WebRequest request, int certificateProblem) {
            return true;
        }
    }
"@
[System.Net.ServicePointManager]::CertificatePolicy = New-Object TrustAllCertsPolicy
################################################
# Starting logging & importing the CSV
################################################
$Now = get-date
$Log = $LogDirectory + "\Cloud-RecoveryPlanLog-" + $Now.ToString("yyyy-MM-dd") + "@" + $Now.ToString("HH-mm-ss") + ".log"
Start-Transcript -Path $Log -NoClobber 
$RecoveryPlanVMs = import-csv $RecoveryPlanCSV
################################################
# Building Cloud API string & invoking REST API
################################################
$baseURL = "https://" + $CloudCluster + "/api/v1/"
$xCloudSessionURL = $baseURL + "session"
$authInfo = ("{0}:{1}" -f $CloudUser,$CloudPassword)
$authInfo = [System.Text.Encoding]::UTF8.GetBytes($authInfo)
$authInfo = [System.Convert]::ToBase64String($authInfo)
$headers = @{Authorization=("Basic {0}" -f $authInfo)}
$TypeJSON = "application/json"
# Authentication with API
Try 
{
$xCloudSessionResponse = Invoke-WebRequest -Uri $xCloudSessionURL -Headers $headers -Method POST -Body $sessionBody -ContentType $TypeJSON
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
# Extracting the token from the JSON response
$xCloudSession = (ConvertFrom-Json -InputObject $xCloudSessionResponse.Content)
$CloudSessionHeader = @{'Authorization' = "Bearer $($xCloudSession.token)"}
###############################################
# Getting list of VMs
###############################################
$VMListURL = $baseURL+"vmware/vm?limit=5000"
Try 
{
$VMListJSON = Invoke-RestMethod -Uri $VMListURL -TimeoutSec 100 -Headers $CloudSessionHeader -ContentType $TypeJSON
$VMList = $VMListJSON.data
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
###################################################################
# Start Per VM Actions here
###################################################################
write-host "Starting per VM RecoveryPlan Actions"
foreach ($VM in $RecoveryPlanVMs)
{
###############################################
# Setting the variables for the current VM
###############################################
$VMName = $VM.VMName
$VMAction = $VM.Action
$VMDisableNetwork = $VM.DisableNetwork
$VMRemoveNetworkDevices = $VM.RemoveNetworkDevices
$VMPowerOn = $VM.PowerOn
$VMRunScriptsinLiveMount = $VM.RunScriptsinLiveMount
$VMPreFailoverScript = $VM.PreFailoverScript
$VMPostFailoverScriptDelay = $VM.PostFailoverScriptDelay
$VMPostFailoverScript = $VM.PostFailoverScript
$VMNextVMFailoverDelay = $VM.NextVMFailoverDelay
$VMPreFailoverUserPrompt = $VM.PreFailoverUserPrompt
$VMPostFailoverUserPrompt = $VM.PostFailoverUserPrompt
# Inserting space in log for readability
write-host "--------------------------------------------"
write-host "Performing Action for VM:$VMName"
# Giving the user 3 seconds to see
sleep 3
###################################################################
# VM Pre-Failover User Prompt
###################################################################
if ($VMPreFailoverUserPrompt -ne "")
{
# Setting title and user prompt
$PromptTitle = "Pre-Failover Prompt"
$PromptMessage = "VM:$VMName 
$VMPreFailoverUserPrompt"
# Defining options
$Continue = New-Object System.Management.Automation.Host.ChoiceDescription "&Continue", `
    "Continues to run the recovery plan"
$Stop = New-Object System.Management.Automation.Host.ChoiceDescription "&Stop", `
    "Stops the recovery plan altogether"
$PromptOptions = [System.Management.Automation.Host.ChoiceDescription[]]($Continue, $Stop)
# Prompting user and defining the result
$PromptResult = $host.ui.PromptForChoice($PromptTitle, $PromptMessage, $PromptOptions, 0) 
switch ($PromptResult)
    {
        0 {"User Selected Continue Recovery Plan"}
        1 {"User Selected Stop Recovery Plan"}
    }
# Performing the exit action if selected
if ($PromptResult -eq 1)
{
# Stopping transcript
Stop-Transcript
# Killing PowerShell script process
kill $PID
}
}
###############################################
# Getting VM ID and outputting VM info to log/console
###############################################
$VMID = $VMList | Where-Object {($_.name -eq $VMName)} | select -ExpandProperty id
$VMSLADomain = $VMList | Where-Object {($_.name -eq $VMName)} | select -ExpandProperty effectiveSlaDomainName
$VMclusterName = $VMList | Where-Object {($_.name -eq $VMName)} | select -ExpandProperty clusterName
$VMHostName = $VMList | Where-Object {($_.name -eq $VMName)} | select -ExpandProperty hostName
$VMIPAddress = $VMList | Where-Object {($_.name -eq $VMName)} | select -ExpandProperty ipAddress
Write-host "ID:$VMID
IPAddress:$VMIPAddress
SLADomain:$VMSLADomain 
clusterName:$VMclusterName
HostName:$VMHostName"
###############################################
# Getting VM snapshot ID
###############################################
$VMSnapshotURL = $baseURL+"vmware/vm/"+$VMID+"/snapshot"
Try 
{
$VMSnapshotJSON = Invoke-RestMethod -Uri $VMSnapshotURL -TimeoutSec 100 -Headers $CloudSessionHeader -ContentType $TypeJSON
$VMSnapshot = $VMSnapshotJSON.data
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
# Selecting most recent VM snapshot to use for recovery operation
$VMSnapshotID = $VMSnapshot | Sort-Object -Descending date | select -ExpandProperty id -First 1
$VMSnapshotDate = $VMSnapshot | Sort-Object -Descending date | select -ExpandProperty date -First 1
Write-host "Snapshot:$VMSnapshotDate"
###############################################
# Performing Live Mount - If configured for VMAction
###############################################
# Using defaultESXi host of original VM by not specifying it in the VM JSON
IF ($VMAction -eq "LiveMount")
{
write-host "Action:$VMAction"
###########################################
# Running pre-failover script if RunScriptsinTest is enabled and script configured
###########################################
if (($VMRunScriptsinLiveMount -eq "TRUE") -and ($VMPreFailoverScript -ne ""))
{
Try 
{
write-host "Running Pre-FailoverScript:$VMPreFailoverScript"
invoke-expression $VMPreFailoverScript
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
}
###########################################
# Setting URL and creating JSON
###########################################
# Setting default if not specified in CSV
if ($VMDisableNetwork -eq ""){$VMDisableNetwork = "false"}
if ($VMRemoveNetworkDevices -eq ""){$VMRemoveNetworkDevices = "true"}
if ($VMPowerOn -eq ""){$VMPowerOn = "true"}
# Forcing to lower case to compensate for excel auto-correct capitalizing 
$VMDisableNetwork = $VMDisableNetwork.ToLower()
$VMRemoveNetworkDevices = $VMRemoveNetworkDevices.ToLower()
$VMPowerOn = $VMPowerOn.ToLower()
$VMLMJSON =
"{
  ""vmName"": ""$VMName - LiveMount"",
  ""disableNetwork"": $VMDisableNetwork,
  ""removeNetworkDevices"": $VMRemoveNetworkDevices,
  ""powerOn"": $VMPowerOn
}"
$VMLiveMountURL = $baseURL+"vmware/vm/snapshot/"+$VMSnapshotID+"/mount"
###########################################
# POST to REST API URL with VMJSON
###########################################
Try 
{
write-host "Starting LiveMount for VM:$VMName"
$VMLiveMountPOST = Invoke-RestMethod -Method Post -Uri $VMLiveMountURL -Body $VMLMJSON -TimeoutSec 100 -Headers $CloudSessionHeader -ContentType $TypeJSON
$VMOperationSuccess = $TRUE
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
###########################################
# Running post-failover script if RunScriptsinTest is enabled, script configured and test started
###########################################
if (($VMRunScriptsinLiveMount -eq "TRUE") -and ($VMPostFailoverScript -ne "") -and ($VMOperationSuccess -eq $TRUE))
{
# Waiting sleep delay for post script
write-host "Sleeping $VMPostFailoverScriptDelay seconds for VMPostFailoverScriptDelay"
sleep $VMPostFailoverScriptDelay
Try 
{
write-host "Running Post-FailoverScript:$VMPostFailoverScript"
invoke-expression $VMPostFailoverScript
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
}
# End of LiveMount action below
}
# End of LiveMount action above
###############################################
# Performing Instant Recovery - If configured for VMAction
###############################################
IF ($VMAction -eq "InstantRecover")
{
write-host "Action:$VMAction"
###########################################
# Running pre-failover script if script configured
###########################################
if ($VMPreFailoverScript -ne "")
{
Try 
{
write-host "Running Pre-FailoverScript:$VMPreFailoverScript"
invoke-expression $VMPreFailoverScript
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
}
###########################################
# Setting URL and creating JSON
###########################################
# Setting default if not specified in CSV
if ($VMRemoveNetworkDevices -eq ""){$VMRemoveNetworkDevices = "true"}
# Forcing to lower case to compensate for excel auto-correct capitalizing 
$VMRemoveNetworkDevices = $VMRemoveNetworkDevices.ToLower()
$VMIRJSON =
"{
  ""vmName"": ""$VMName"",
  ""removeNetworkDevices"": $VMRemoveNetworkDevices
}"
$VMInstantRecoverURL = $baseURL+"vmware/vm/snapshot/"+$VMSnapshotID+"/instant_recover"
###########################################
# POST to REST API URL with VMJSON
###########################################
# Warning, connects the VM the production network, shuts down and renames the original VM if it exists as "Deprecated VMName Date Time"
Try 
{
write-host "Starting InstantRecover for VM:$VMName"
$VMInstantRecoverPOST = Invoke-RestMethod -Method Post -Uri $VMInstantRecoverURL -Body $VMIRJSON -TimeoutSec 100 -Headers $CloudSessionHeader -ContentType $TypeJSON
$VMOperationSuccess = $TRUE
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
###########################################
# Running post-failover script configured and test started
###########################################
if (($VMPostFailoverScript -ne "") -and ($VMOperationSuccess -eq $TRUE))
{
# Waiting sleep delay for post script
write-host "Sleeping $VMPostFailoverScriptDelay seconds for VMPostFailoverScriptDelay"
sleep $VMPostFailoverScriptDelay
Try 
{
write-host "Running Post-FailoverScript:$VMPostFailoverScript"
invoke-expression $VMPostFailoverScript
}
Catch 
{
Write-Host $_.Exception.ToString()
$error[0] | Format-List -Force
}
}
# End of InstantRecover action below
}
# End of InstantRecover action below
###############################################
# No valid VMAction configured
###############################################
IF (($VMAction -ne "LiveMount") -and ($VMAction -ne "InstantRecover"))
{
write-host "VMAction not configured for $VMName as LiveMount or InstantRecover meaning no action was taken"
}
###########################################
# Waiting for VMNextVMFailoverDelay and Post-Failover Prompt (if configured) if start test was a success
###########################################
if ($VMOperationSuccess -eq $TRUE)
{
write-host "Sleeping $VMNextVMFailoverDelay seconds for VMNextVMFailoverDelay"
sleep $VMNextVMFailoverDelay
###################################################################
# VM Post-Failover User Prompt
###################################################################
if ($VMPostFailoverUserPrompt -ne "")
{
# Setting title and user prompt
$PromptTitle = "Post-Failover Prompt"
$PromptMessage = "VM:$VMName 
$VMPostFailoverUserPrompt"
# Defining options
$Continue = New-Object System.Management.Automation.Host.ChoiceDescription "&Continue", `
    "Continues to run the recovery plan"
$Stop = New-Object System.Management.Automation.Host.ChoiceDescription "&Stop", `
    "Stops the recovery plan altogether"
$PromptOptions = [System.Management.Automation.Host.ChoiceDescription[]]($Continue, $Stop)
# Prompting user and defining the result
$PromptResult = $host.ui.PromptForChoice($PromptTitle, $PromptMessage, $PromptOptions, 0) 
switch ($PromptResult)
    {
        0 {"User Selected Continue Recovery Plan"}
        1 {"User Selected Stop Recovery Plan"}
    }
# Performing the exit action if selected
if ($PromptResult -eq 1)
{
# Stopping transcript
Stop-Transcript
# Killing PowerShell script process
kill $PID
}
}
# End of "Waiting for VMPostFailoverUserPrompt and Post-Failover Prompt (if configured) if start test was a success" below
}
# End of "Waiting for VMPostFailoverUserPrompt and Post-Failover Prompt (if configured) if start test was a success" above
#
# End of per VM actions below
}
# End of per VM actions above
#
# Inserting space in log for readability
write-host "--------------------------------------------"
write-host "End of RecoveryPlan Script"
################################################
# Stopping logging
################################################
Stop-Transcript
###############################################
# End of script
###############################################