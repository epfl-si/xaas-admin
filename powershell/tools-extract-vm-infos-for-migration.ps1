<#
USAGES:
    tools-extract-vm-infos-for-migration.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices -vmName <vmName>
#>
<#
    BUT 		: Script permettant d'extraire les informations utiles à la migration d'une VM d'un BG à un autre.
                  

	DATE 	: Mars 2021
    AUTEUR 	: Lucien Chaboudez
    

    Confluence :
        La procédure de migration durant laquelle les informations générées par ce script seront utilisées se trouve
        ici: https://confluence.epfl.ch:8443/display/SIAC/%5BIaaS%5D+KB+-+requests+-+Clone+an+existing+VM+to+a+new+one                          

#>
param ( [string]$targetEnv, 
        [string]$targetTenant,
        [string]$vmName)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configvSphere = [ConfigReader]::New("config-vsphere.json")

# Liste des propriétés à extraire de la VM
$propList = @(
	"VirtualMachine.Storage.Cluster.Name",
	"VMware.VirtualCenter.OperatingSystem",
	"ch.epfl.deployment_tag",
	"ch.epfl.iaas.dmz.add_ports.details",
	"ch.epfl.iaas.dmz.add_ports.enabled",
	"ch.epfl.iaas.dmz.add_ports.reason",
	"ch.epfl.iaas.dmz.add_resources.details",
	"ch.epfl.iaas.dmz.add_resources.enabled",
	"ch.epfl.iaas.dmz.add_resources.reason",
	"ch.epfl.iaas.dmz.enabled",
	"ch.epfl.iaas.dmz.open_ports",
	"ch.epfl.owner_mail",
	"ch.epfl.xaas.backup.vm.tag"
)

# Fichier de sortie pour les informations extraites
$outFolder = ([IO.Path]::Combine($global:RESULTS_FOLDER, "VM-Infos"))
$outFile = ([IO.Path]::Combine($outFolder, ("{0}.csv" -f $vmName)))

# On commence par contrôler le prototype d'appel du script
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

if(!(Test-Path $outFolder))
{
    New-Item -Path $outFolder -ItemType:Directory | Out-Null
}

$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                        $targetTenant, 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

# Recherche de la VM vRA
Write-Host ("Getting vRA VM '{0}' on {1} tenant in {2} infrastructure..." -f $vmName, $targetTenant, $targetEnv)
$vraVm = $vra.getItem("Virtual Machine", $vmName) 

if($null -eq $vraVm)
{
    Write-Host -ForegroundColor:DarkRed "vRA VM not found!"
    exit
}

Write-host "Extracting informations..." -NoNewline

("Owner;{0}" -f $vraVm.owners[0].ref) | Out-File -Append -Encoding:utf8 $outFile
("DeploymentName;{0}" -f $vraVm.parentResourceRef.label) | Out-File -Append -Encoding:utf8 $outFile


# Extraction des propriétés nécessaires
ForEach($prop in $propList)
{
    ("{0};{1}" -f $prop, ($vraVm.resourceData.Entries | Where-Object { $_.key -eq $prop }).value.value)  | Out-File -Append -Encoding:utf8 $outFile 
}


Write-Host "done"
Write-host ("Informations can be found in following CSV file: {0}" -f $outFile)
                    
$vra.disconnect()


