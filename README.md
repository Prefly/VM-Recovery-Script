# VM-Recovery-Script

## Description:
This script runs a Recovery Plan for VMs protected by Cloud

## Requirements:
- Run PowerShell as administrator with command "Set-ExecutionPolcity unrestricted" on the host running the script
- A Cloud cluster or EDGE appliance, network access to it and credentials to login- A CSV with the following fields: VMName,Action,DisableNetwork,RemoveNetworkDevices,PowerOn,RunScriptsinLiveMount,PreFailoverScript,PostFailoverScriptDelay,PostFailoverScript,NextVMFailoverDelay,PreFailoverUserPrompt,PostFailoverUserPrompt
- Example CSV Line = FileServer1,LiveMount,TRUE,FALSE,TRUE,FALSE,,0,,30,Are you bloody sure?,Has the VM come online?- Valid options for Action are LiveMount, InstantRecover, recommended to use LiveMount first to validate recovery
- The options DisableNetwork,PowerOn,RunScriptsinLiveMount are only used LiveMount operations 
- Valid options for DisableNetwork,RemoveNetworkDevices,PowerOn,RunScriptsinLiveMount are TRUE or FALSE
- Valid options for PostFailoverScriptDelay,NextVMFailoverDelay is 0 - any number of seconds
- If no script is specified for PreFailoverScript,PostFailoverScript then nothing is run
- If no user prompt is specified for PreFailoverUserPrompt,PostFailoverUserPrompt then the user isn't prompted, this choice can be made per VM
- This script always fails over to the latest snapshot available

## Legal Disclaimer:
-All scripts are provided AS IS without warranty of any kind. 
-The author further disclaims all implied warranties including, without limitation, any implied warranties of merchantability or of fitness for a particular purpose. 
-The entire risk arising out of the use or performance of the sample scripts and documentation remains with you. 
-In no event shall its authors, or anyone else involved in the creation, production, or delivery of the scripts be liable for any damages whatsoever (including, without limitation, damages for loss of business profits, business interruption, loss of business information, or other pecuniary loss) arising out of the use of or inability to use the sample scripts or documentation, even if the author has been advised of the possibility of such damages.

## Configure the variables below for the Cloud Cluster
```
$CloudCluster = "192.168.0.200"
$RecoveryPlanCSV = "C:\Scripts\CloudRecoveryPlan\CloudRecoveryPlan.csv"
$LogDirectory = "C:\Scripts\CloudRecoveryPlan\"
# Prompting for username and password to authenicate, can set manually to remove human interaction
$Credentials = Get-Credential -Credential $null
$CloudUser = $Credentials.UserName
$Credentials.Password | ConvertFrom-SecureString
$CloudPassword = $Credentials.GetNetworkCredential().password
```
