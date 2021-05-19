<#
USAGES:
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research [-bgList <bgList>]
    tools-vm-with-snapshots.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research -bgRegex <bgRegex>
#>
<#
    BUT 		: Script permettant d'afficher les VMs qui ont un snapshot, soit pour tous les BG, soit pour une
                    liste de BG donnée (séparée par des virgules), soit pour les BG dont le nom match la regex passée
                    
	DATE 	: Mai 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

#>
param([string]$targetEnv, 
      [string]$targetTenant,
      [string]$bgList, # Liste des BG, séparés par des virgules. Il faut mettre cette liste entre simple quotes ''
      [string]$bgRegex) # Expression régulière pour le filtre des noms de BG. Il faut mettre entre simple quotes ''


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVra 		= [ConfigReader]::New("config-vra.json")


# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logHistory = [LogHistory]::new(@('tools','vm-with-snapshots'), $global:LOGS_FOLDER, 120)
    
# On commence par contrôler le prototype d'appel du script
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

# Ajout d'informations dans le log
$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

# On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
$targetEnv = $targetEnv.ToLower()
$targetTenant = $targetTenant.ToLower()


$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                $targetTenant, 
                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

# Recherche de la liste des BG en fonction des noms donnés
$targetBgList = $vra.getBGList()

# Si on doit filtrer sur des BG,
if($bgList -ne "") 
{
    # On transforme le paramètre en tableau
    $bgListNames = $bgList.split(",")

    $targetBgList = $targetBgList | Where-Object { $bgListNames -contains $_.name }
}
# Si on a passé une regex
elseif($bgRegex -ne "")
{
    $targetBgList = $targetBgList | Where-Object { $_.name -match $bgRegex }
}


[System.Collections.ArrayList]$vmWithSnap = @()

$now = Get-Date

# Parcours des BG
Foreach($bg in $targetBgList)
{
    
    $logHistory.addLineAndDisplay(("Processing BG '{0}'..." -f $bg.name))
    $vmList = $vra.getBGItemList($bg, $global:VRA_ITEM_TYPE_VIRTUAL_MACHINE)

    # Parcours des VM
    ForEach($vm in $vmList)
    {
        # Parcours des snapshots de la VM courante
        ForEach($snap in ($vm.resourceData.entries | Where-Object { $_.key -eq "SNAPSHOT_LIST"}).value.items)
        {

            # Récupération de la date de création
            $createDate = [DateTime]::parse(($snap.values.entries | Where-Object { $_.key -eq "SNAPSHOT_CREATION_DATE"}).value.value)
            # Calcul de l'âge du snapshot 
            $dateDiff = New-Timespan -start $createDate -end $now

            # Ajout au tableau pour un affichage propre à la fin
            $vmWithSnap.add([PSCustomObject]@{
                    bgName = $bg.name
                    VM = $vm.name
                    snapshotDate = $createDate.toString("dd.MM.yyyy HH:mm:ss")
                    ageDays = $dateDiff.days
                }) | Out-Null

            $logHistory.addLineAndDisplay(("-> VM '{0}' has snapshot since {1} ({2} days)" -f $vm.name, $createDate.toString("dd.MM.yyyy HH:mm:ss"), $dateDiff.days))

        }# FIN BOUCLE de parcours des snap de la VM

    }# FIN BOUCLE de parcours de VM du BG

}# FIN BOUCLE de parcours des BG

# Affichage du résultat
$vmWithSnap