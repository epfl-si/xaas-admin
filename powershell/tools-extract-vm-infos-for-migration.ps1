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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRA8API.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra8.json")

# Liste des propriétés à extraire de la VM
$propList = @(
    # On met ici une liste car il se peut que l'information soit dans 2 endroits différents
	@("VirtualMachine.Storage.Cluster.Name", "VirtualMachine.Storage.Name"),
	@("VMware.VirtualCenter.OperatingSystem", "VirtualMachine.Cafe.Blueprint.Name") ,
    "VirtualMachine.Admin.Hostname",
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


$vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))
          

# Recherche de la VM vRA
Write-Host ("Getting vRA VM '{0}' on {1} tenant in {2} infrastructure..." -f $vmName, $targetTenant, $targetEnv)
$vraVm = $vra.getDeployment($global:VRA_ITEM_TYPE_VIRTUAL_MACHINE, $vmName) 

if($null -eq $vraVm)
{
    Write-Host -ForegroundColor:DarkRed "vRA VM not found!"
    exit
}

# Si le fichier de sortie existe, on le supprime
if(Test-Path $outFile)
{
    Remove-Item -path $outFile -Force
}

Write-host "Extracting informations..." -NoNewline
# TODO: Continuer ici
("Owner;{0}" -f $vraVm.owners[0].ref) | Out-File -Append -Encoding:utf8 $outFile
("DeploymentName;{0}" -f $vraVm.parentResourceRef.label) | Out-File -Append -Encoding:utf8 $outFile


$oneLinePropList = @()

# Extraction des propriétés nécessaires
ForEach($prop in $propList)
{
    $propArray = $prop
    if($propArray -isnot [System.Array])
    {
        $propArray = @($propArray)
    }

    $propVal = ""
    $valFound = $false
    ForEach($prop in $propArray) {
        $propVal = ($vraVm.resourceData.Entries | Where-Object { $_.key -eq $prop }).value.value

        if($null -ne $propVal)
        {
            $valFound = $true
            ("{0};{1}" -f $prop, $propVal)  | Out-File -Append -Encoding:utf8 $outFile 

            if($prop.startsWith("ch.epfl"))
            {
                $oneLinePropList += ("{0},{1}" -f $prop, ($propVal -replace ",",";"))
            }
            
            break
        }
        
    }

    if(!$valFound)
    {
        Write-Warning ("No value found for '{0}'" -f ($propArray -join ", "))
        #Throw "No value found for '{0}'" -f ($propArray -join ", ")
    }
}

# Recherche de l'IP dans le DNS
$ips = [System.Net.Dns]::GetHostAddresses(("{0}.xaas.epfl.ch" -f $vmName))

if($ips.count -eq 0)
{
    Write-Error  ("NO IP found for VM {0} in DNS" -f $vmName)
}

("`nOne line prop list:`n,{0}, HOP, VirtualMachine.Network0.Address, {1}, HOP, VirtualMachine.Network0.DnsSuffix, xaas.epfl.ch, HOP" -f ($oneLinePropList -join ", HOP,"), $ips[0].IPAddressToString) | Out-File -Append -Encoding:utf8 $outFile 


Write-Host "done"
Write-host ("Informations can be found in following CSV file: {0}" -f $outFile)

Write-Warning "Don't forget to reclaim IP address after VM unregistration process"
                    
$vra.disconnect()


