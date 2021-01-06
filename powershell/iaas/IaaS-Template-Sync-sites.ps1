param ( [string]$targetEnv)

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
$configVsphereTemplate = [ConfigReader]::New("config-vsphere-template.json")
$configVcenter = [ConfigReader]::New("config-vsphere.json")


# $targetEnv="prod"



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
$masterTemplatesFolderName = $configVsphereTemplate.getConfigValue($targetEnv, "masterTemplatesFolder")
$masterTemplatesTag = $configVsphereTemplate.getConfigValue($targetEnv, "masterTemplatesTag")

$masterTemplatesFolder = get-folder -name $masterTemplatesFolderName  -Type VM -Server $vCenter
$masterTemplates = Get-Template -location $masterTemplatesFolder -Server $vCenter | Sort-Object

## get templates targets from configuration file

$TemplatesTargets = $configVsphereTemplate.getConfigValue($targetEnv, "TemplatesTargets") | Get-Member -MemberType NoteProperty | Select-object -ExpandProperty Name 

## loop for each master template

foreach ($masterTemplate in ($masterTemplates | Where-Object {$_.name -like "*master*"}) ) {
    
    ## check if the current master tempate has a sync tag.
    $vmtags= $null 
    $vmtags= Get-TagAssignment -Entity $masterTemplate -Category "IaaS" 

foreach ($vmtag in $vmtags) {

    ## if the sync tag is present
    if ($vmtag.Tag.Name -match $masterTemplatesTag) {

    ## for each templates target
    foreach ($TemplatesTarget in $TemplatesTargets){



## set replica informations
$replicaTemplatesFolderName = $configVsphereTemplate.getConfigValue($targetEnv, "TemplatesTargets", $TemplatesTarget, "replicaTemplatesFolder")
$replicaTemplatesFolder = get-folder -name $replicaTemplatesFolderName  -Type VM -Server $vCenter

$replicaClusterName = $configVsphereTemplate.getConfigValue($targetEnv, "TemplatesTargets", $TemplatesTarget, "replicaCluster")
$replicaVMHost = Get-VMHost -location (get-cluster -name $replicaClusterName) | get-random -Count 1

$replicaDSName = $configVsphereTemplate.getConfigValue($targetEnv, "TemplatesTargets", $TemplatesTarget, "replicaDSName")
$replicaTemplatesDatastore = $replicaVMHost | Get-Datastore -Server $vCenter | Where-Object {($_.name -like $replicaDSName) -and ($_.Type -like "VMFS")}


$replicaTemplates = Get-Template -location $replicaTemplatesFolder -Server $vCenter
$newReplicaTemplates = @()

$replicaTemplatesSuffixName = $configVsphereTemplate.getConfigValue($targetEnv, "TemplatesTargets", $TemplatesTarget, "replicaTemplatesSuffix")




# copy master template to destination replica



   

   write-host "VM Tag is found"
    write-host $masterTemplate.name " will be synched to the replica site" + $replicaTemplatesSuffixName
    $replicaVMHostRandom = Get-VMHost -location (get-cluster -name $replicaClusterName) | get-random -Count 1
    # clone VM from master template to a new replica with -transit at the end
    $replicaTemplateTransit = New-Template -Template $masterTemplate -Name ($masterTemplate.name + "-transit") -Location $replicaTemplatesFolder -Datastore $replicaTemplatesDatastore -VMHost $replicaVMHostRandom -Server $vCenter -Confirm:$false
    # rename replicaTemplate to add -old at the end (will be removed once copy from parent will be completed)
    
    $replicaTemplateToDelete = ""

    foreach ($replicaTemplate in $replicaTemplates) {
        
        # Where-Object ( )
        if (($replicaTemplate.name).startswith($masterTemplate.name)) {
            
            $newReplicaTemplates += $replicaTemplates
            

            $replicaTemplateToDelete = set-template -Template $replicaTemplate -Name ($masterTemplate.name + "-old") -Server $vCenter

            
        }


    }
    set-template -Template $replicaTemplateTransit -Name ($masterTemplate.name + $replicaTemplatesSuffixName) -Server $vCenter
    ## Remove -old template 
    if ($replicaTemplateToDelete -notlike "") {Remove-Template -Template $replicaTemplateToDelete -DeletePermanently:$true -Confirm:$false}

    

    

   

    }

    Remove-TagAssignment $vmtag -Confirm:$false

} else {

    Write-Host "the entity has tags but not the good: " + $vmtag.Tag.Name
}
   
}



# $replicaTemplates | ForEach-Object {
#     if ($_ -notin $newReplicaTemplates) {
#         write-host "remove orphaned replica: "  $_.name
#     }
# }

}
"finish"

Disconnect-VIServer -Confirm:$false -Server $vCenter