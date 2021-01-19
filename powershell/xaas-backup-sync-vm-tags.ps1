<#
USAGES:
    xaas-backup-sync-vm-tags.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research [-importFromvSphere]
#>
<#
    BUT 		: Script lancé par une tâche planifiée, afin de synchroniser, de manière unidirectionnelle,
                    les tags de backup des VM depuis vRA vers vSphere.
                  Du côté vRA, on regarde le contenu de la custom property définie par $VRA_CUSTOM_PROPERTY_BACKUP_TAG
                  Si on reçoit $null, c'est que la custom property n'existe pas. Dans ce cas-là, on skip la VM
                  Sinon, on regarde si le contenu est synchro avec ce qui est dans vSphere et si ce n'est pas le cas,
                  on met à jour le tag sur la VM dans vSphere.

	DATE 	: Octobre 2019
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.01

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
      [switch]$importFromvSphere)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "JSONUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NewItems.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")
$configXaaSBackup = [ConfigReader]::New("config-xaas-backup.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Récupérer ou initialiser le tag d'une VM dans vSphere
$VRA_CUSTOM_PROPERTY_BACKUP_TAG = "ch.epfl.xaas.backup.vm.tag"
# Catégorie des tags
$NBU_TAG_CATEGORY = "NBU"

# -------------------------------------------- FONCTIONS ---------------------------------------------------

<#
    BUT : Renvoie la représentation d'un tag passé, histoire que ça soit plus "parlant" quand on affiche dans
          la console, surtout dans le cas où le tag est vide.

    IN  : $backupTag    -> Le tag dont on veut la représentation
#>
function backupTagRepresentation([string]$backupTag)
{
    if($backupTag -eq "")
    {
        return "<empty>"
    }
    return $backupTag
}

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    $logName = 'xaas-backup-sync-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()
    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $counters = [Counters]::new()
    $counters.add('BGProcessed', '# BG Processed')
    $counters.add('UpdatedTags', '# VM Updated tags')
    $counters.add('CorrectTags', '# VM Correct tags')
    $counters.add('ProcessedVM', '# VM Processed')
    $counters.add('VMNotInvSphere', '# VM not in vSphere')

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

    # -------------------------------------------------------------------------------------------

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))

    <# Connexion à l'API Rest de vSphere. On a besoin de cette connxion aussi (en plus de celle du dessus) parce que les opérations sur les tags ne fonctionnent
    pas via les CMDLet Get-TagAssignement et autre...  #>
    $logHistory.addLineAndDisplay("Connecting to vSphere...")
    $vsphereApi = [vSphereAPI]::new($configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "server")),
                                    $configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "user")),
                                    $configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "password")))

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
						 $targetTenant, 
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    if($importFromvSphere)                         
    {
        $logHistory.addLineAndDisplay("!!! Synchronizing from vSphere to vRA !!!")
    }

    # Parcours des Business Groups
    $vra.getBGList() | ForEach-Object {

        $logHistory.addLineAndDisplay("Processing BG {0} ..." -f $_.Name)
        $counters.inc('BGProcessed')
        
        # Parcours des VM se trouvant dans le Business Group
        $vra.getBGItemList($_, "Virtual Machine") | ForEach-Object {

            $vmName = $_.Name

            $counters.inc('ProcessedVM')

            $logHistory.addLineAndDisplay("-> vRA VM {0} ..." -f $vmName)
            
            # Recherche de la custom property représentant le Tag de backup
            $vRATag = getvRAObjectCustomPropValue -object $_ -customPropName $VRA_CUSTOM_PROPERTY_BACKUP_TAG

            $vSphereTag = $null

            # Si la propriété existe
            # OU
            # Si on doit synchro depuis vSphere
            if(($null -ne $vRATag) -or $importFromvSphere)
            {
                if($null -ne $vRATag)
                {
                    $logHistory.addLineAndDisplay("--> vRA Backup tag found! -> {0}" -f (backupTagRepresentation -backupTag $vRATag))
                }
                
                # Si on ne trouve pas la VM dans vSphere, 
                if(! $vsphereApi.VMExists($vmName))
                {
                    $logHistory.addLineAndDisplay("--> VM doesn't exists in vSphere !!")
                    $counters.inc('VMNotInvSphere')
                    continue
                }

                # Recherche du tag attribué à la VM 
                $vSphereTag = $vsphereApi.getVMTags($vmName, $NBU_TAG_CATEGORY)
            } 

            # Si on a trouvé un tag, on récupère son nom.
            if($null -ne $vSphereTag)
            {
                $vSphereTag = $vSphereTag.Name
            }
            else
            {
                # On met chaine vide au lieu de $null car plus pratique pour après
                $vSphereTag = ""
            }
            
            # Si on n'a pas trouvé de tag de backup pour vRA
            if($null -eq $vRATag)
            {
                $logHistory.addLineAndDisplay("--> No vRA backup tag")
                $vRATag = ""
            }

            # Si les tags sont différents 
            if($vSphereTag -ne $vRATag)
            {
                $logHistory.addLineAndDisplay(("--> Tags are different (vRA={0}, vSphere={1}), updating..." -f (backupTagRepresentation -backupTag $vRATag), 
                                                                                                                (backupTagRepresentation -backupTag $vSphereTag)))

                # Si on doit updater vRA depuis vSphere
                if($importFromvSphere)
                {
                    # Mise à jour de la custom property sur la VM dans vRA
                    $vra.updateVMCustomProp($_, $VRA_CUSTOM_PROPERTY_BACKUP_TAG, $vSphereTag)
                }
                else # On doit updater vSphere depuis vRA
                {
                    # S'il y a effectivement un Tag sur la VM
                    if($vSphereTag -ne "")
                    {
                        # Suppression du tag existant dans vSphere
                        $vsphereApi.detachVMTag($vmName, $vSphereTag)
                    }

                    # Si le tag dans vRA n'est pas vide, 
                    if($vRATag -ne "")
                    {
                        $vsphereApi.attachVMTag($vmName, $vRATag)
                    }
                }
                
                $counters.inc('UpdatedTags')
            }
            else # Le tag dans vRA et dans vSphere est identique
            {
                $logHistory.addLineAndDisplay("--> vSphere tag up-to-date ({0})" -f (backupTagRepresentation -backupTag $vSphereTag))

                $counters.inc('CorrectTags')
            }

        } # FIN BOUCLE parcours des VM dans le Business Group
   
    } # FIN BOUCLE de parcours des Business Group

    # Affichage des compteurs
    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))
}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }
    
    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace)

}

# Déconnexion des API 
$logHistory.addLineAndDisplay("Disconnecting from vRA...")
$vra.disconnect()

$logHistory.addLineAndDisplay("Disconnecting from vSphere...")
$vsphereApi.disconnect()