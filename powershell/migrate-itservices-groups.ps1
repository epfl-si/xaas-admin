<#
USAGES:
	migrate-itservices-groups.ps1 -targetEnv prod|test|dev
#>
<#
    Header bidon
#>
param ( [string]$targetEnv)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ITServices.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "GroupsAPI.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

$configGroups = [ConfigReader]::New("config-groups.json")

$targetTenant = "itservices"

# Pour s'interfacer avec l'application Groups
$groupsApp = [GroupsAPI]::new($configGroups.getConfigValue(@($targetEnv, "server")),
                                $configGroups.getConfigValue(@($targetEnv, "appName")),
                                $configGroups.getConfigValue(@($targetEnv, "callerSciper")),
                                $configGroups.getConfigValue(@($targetEnv, "password")))


# Création de l'objet qui permettra de générer les noms des groupes AD et "groups" ainsi que d'autre choses...
$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)


# Objet pour lire les informations sur le services IT
$itServices = [ITServices]::new()

$groupsManualRename = @()
$groupsRenameOk = @()

# ID du groupe vsissp-prod-admins à ajouter dans tous les groupes
$adminSciper = "S19307"

$serviceList = $itServices.getServiceList($targetEnv)
# Ajout du service ADMIN
$serviceList += @{
    longName = "XaaS Admins"
    shortName = "xaasadm"
    snowId = "SVC0000"
    serviceManagerSciper = "287589"
    deniedVRAServiceList = @()
}

Foreach($service in $serviceList)
{
    $nameGenerator.initDetails(@{serviceShortName = $service.shortName
                                serviceName = $service.longName
                                snowServiceId = $service.snowId})

    Write-Host $service.longName
    $curName = "{0}{1}_{2}" -f  [NameGenerator]::AD_GROUP_PREFIX, $nameGenerator.getEnvShortName(), $service.shortName
    $newName = $nameGenerator.getRoleADGroupName("CSP_CONSUMER", $false)

    $additionalDetails = @{
        deniedVRASvc = $service.deniedVRAServiceList
        hasApproval = $true
    }
    $adGroupDesc = $nameGenerator.getRoleADGroupDesc("CSP_CONSUMER", $additionalDetails)

    Write-Host (">> Renaming AD Group {0} to {1}" -f $curName, $newName)

    try
    {
        $GroupDN = $(Get-ADGroup -Identity $curName).distinguishedName

        # Renommage 
        Set-ADGroup -Identity $GroupDN -sAMAccountName $newName # nom pré win-2000
        Rename-ADObject -Identity $GroupDN -NewName $newName # nom du groupe

        # Mise à jour de la description 
        Set-ADGroup $newName -Description $adGroupDesc -Confirm:$false

    }
    catch
    {
        Write-Warning (">> Group {0} not found in AD, maybe already renamed" -f $curName)
    }

    Write-Host (">> Renaming 'groups' Group {0} to {1}" -f $curName, $newName)

    $group = $groupsApp.getGroupByName($curName)

    if($null -ne $group)
    {
        # Si le groupe vsissp-prod-admins n'est pas dans la liste des admins
        if($null -eq ($groupsApp.listAdmins($group.id) | Where-Object { $_.id -eq $adminSciper}))
        {
            # Ajout en tant qu'Admin
            Write-Host (">>>> Adding 'vsissp-prod-admins' group as admin")
            $groupsApp.addAdmin($group.id, $adminSciper)

        }
        else
        {
            Write-Host (">>> 'vsissp-prod-admins' already in admin list")

        }

        try
        {
            $newGroup = $groupsApp.renameGroup($curName, $newName)    

            $groupsRenameOk +=  ("{0} to {1}" -f $curName, $newName)
        }
        catch
        {
            Write-Warning (">> Impossible to rename 'groups' group {0}" -f $curName)
            $groupsManualRename += ("{0} to {1}" -f $curName, $newName)
        }    
    }
    else
    {
        Write-Warning (">> Group {0} not found in 'groups', maybe already renamed" -f $curName)
    }


}

if($groupsManualRename.count -gt 0)
{
    Write-Host "Following groups have to be manually renamed in 'groups'"
    $groupsManualRename
}

Write-Host ""
Write-Host "Groups successfully renamed:"
$groupsRenameOk
