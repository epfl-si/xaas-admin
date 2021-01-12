param ( [string]$targetEnv, [string]$VMName)

. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "ResumeOnFail.inc.ps1"))
# . ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "SQLDB.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "GroupsAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "REST", "NSXAPI.inc.ps1"))


# Chargement des fichiers de configuration
# $configVsphereTemplate = [ConfigReader]::New("config-vsphere-template.json")
$configVcenter = [ConfigReader]::New("config-vsphere.json")


$targetEnv="Test"
$VMName="itstxaas1134"


try {
	
	$vCenter = Connect-VIServer -Server ($configVcenter.getConfigValue($targetEnv, "server")) -user ($configVcenter.getConfigValue($targetEnv, "user")) -password ($configVcenter.getConfigValue($targetEnv, "password"))
						 

}
catch {
	Write-Error "Error connecting to vCenter API !"
	Write-Error $_.ErrorDetails.Message
	exit
}
## check if powercli module is loaded

If ( (Get-module vmware.powercli ) -like "" ) {

    Import-Module vmware.powercli
    Start-Sleep -Seconds 5
    Import-Module vmware.powercli
    
    }




### code

## set master templates from configuration files

$VM= Get-VM $VMName -Server $vCenter 
$VMID= Get-VM $VMName -Server $vCenter | get-view
$currentVMUUID = Get-VM $VMName -Server $vCenter | ForEach-Object {(Get-View $_.Id).config.uuid}
$currentVMInstanceUUID = Get-VM $VMName -Server $vCenter | ForEach-Object {(Get-View $_.Id).config.InstanceUuid}

Write-Host "the UUID of the VM: " $vmname " is: " $currentVMUUID

"finish"

Disconnect-VIServer -Confirm:$false -Server $vCenter