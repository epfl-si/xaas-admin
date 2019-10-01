<#
USAGES:
    xaas-backup-endpoints.ps1 -targetEnv prod|test|dev -action getBackupTag -vmName <vmName>
    xaas-backup-endpoints.ps1 -targetEnv prod|test|dev -action setBackupTag -vmName <vmName> -backupTag (<backupTag>|"")
    xaas-backup-endpoints.ps1 -targetEnv prod|test|dev -action getBackupList -vmName <vmName>
    xaas-backup-endpoints.ps1 -targetEnv prod|test|dev -action restoreBackup -vmName <vmName> -restoreBackupId <restoreId>
    xaas-backup-endpoints.ps1 -targetEnv prod|test|dev -action restoreBackup -vmName <vmName> -restoreTimestamp <restoreTimestamp>
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service de Backup en tant que XaaS.
                  Pour accéder à vSphere, on utilise 2 manières de faire: 
                  - via les PowerCLI
                  - via la classe vSphereAPI qui permet de faire des opérations sur les tags
                    à l'aide de commandes REST.

	DATE 		: Juin 2019
	AUTEUR 	: Lucien Chaboudez

	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
                  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.

    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    Confluence :
    https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=99188910                                

#>
param ( [string]$targetEnv, [string]$action, [string]$vmName, [string]$backupTag, [string]$restoreBackupId, [string]$restoreTimestamp)

<# On enregistrer l'endroit où le script courant se trouve pour pouvoir effectuer l'import des autres fichiers.
On fait ceci au lieu d'utiliser $PSScriptRoot car la valeur de ce dernier peut changer si on importe un module (Import-Module) dans
un des fichiers inclus via ". <pathToFile>" #>
$SCRIPT_PATH = $PSScriptRoot

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ConfigReader.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "vSphereAPI.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "XaaS", "Backup", "NetBackupAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configXaaSBackup = [ConfigReader]::New("config-xaas-backup.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Récupérer ou initialiser le tag d'une VM dans vSphere
$ACTION_GET_BACKUP_TAG = "getBackupTag"
$ACTION_SET_BACKUP_TAG = "setBackupTag"

# Récupérer la liste des backup ou dire à NetBackup d'en restaurer un
$ACTION_GET_BACKUP_LIST = "getBackupList"
$ACTION_RESTORE_BACKUP = "restoreBackup"

$NBU_TAG_PREFIX = "NBU-"
$NBU_TAG_PREFIX_DONT_TOUCH = "SNBU-"
$NBU_CATEGORY = "NBU"

# -------------------------------------------- FONCTIONS ---------------------------------------------------



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-backup', (Join-Path $SCRIPT_PATH "logs"), 30)

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ArgsPrototypeChecker.inc.ps1"))
   

    # -------------------------------------------------------------------------------------------

    <# Connexion à l'API Rest de vSphere. On a besoin de cette connxion aussi (en plus de celle du dessus) parce que les opérations sur les tags ne fonctionnent
    pas via les CMDLet Get-TagAssignement et autre...  #>
    $vsphereApi = [vSphereAPI]::new($configXaaSBackup.getConfigValue($targetEnv, "vSphere", "server"), 
                                    $configXaaSBackup.getConfigValue($targetEnv, "vSphere", "user"), 
                                    $configXaaSBackup.getConfigValue($targetEnv, "vSphere", "password"))

    # Connexion à l'API REST de NetBackup
    $nbu = [NetBackupAPI]::new($configXaaSBackup.getConfigValue($targetEnv, "backup", "server"), 
                               $configXaaSBackup.getConfigValue($targetEnv, "backup", "user"), 
                               $configXaaSBackup.getConfigValue($targetEnv, "backup", "password"))   

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))

    # En fonction de l'action demandée
    switch ($action)
    {
        # ------------------------- vSphere -------------------------

        # Récupération du tag d'une VM
        $ACTION_GET_BACKUP_TAG {

            # Récupération du tag de backup existant
            $tag = $vSphereApi.getVMTags($vmName, $NBU_CATEGORY) 
            
            # Si un tag est trouvé,
            if($null -ne $tag)
            {
                # Génération du résultat
                $output.results += $tag.Name
            }
            
        }


        # Initialisation du tag d'une VM
        $ACTION_SET_BACKUP_TAG {

            # Recherche du tag de backup existant sur la VM
            $tag = $vSphereApi.getVMTags($vmName, $NBU_CATEGORY) 

            $canAddNewTag = $true

            # S'il y a un tag de backup 
            if($null -ne $tag)
            {
                # Si on a le droit de toucher au tag présent
                if($tag.Name -notlike ("{0}*" -f $NBU_TAG_PREFIX_DONT_TOUCH))
                {
                    # On supprime le tag
                    $vsphereApi.detachVMTag($vmName, $tag.name)
                }
                else # On ne peut pas toucher au tag présent
                {
                    # Donc on fait en sorte de ne pas en ajouter un autre (car ça provoquerait une erreur)
                    $canAddNewTag = $false
                    # Pour renvoyer le tag actuellement présent
                    $output.results += $tag.name
                }
            }

            # Si on doit ajouter un tag
            if(($backupTag -ne "") -and ($canAddNewTag))
            {
                $vsphereApi.attachVMTag($vmName, $backupTag)       

                $output.results += $backupTag
            }

            
        }


        # ------------------------- NetBackup -------------------------

        # Récupération de la liste des backup FULL d'une VM durant l'année écoulée
        $ACTION_GET_BACKUP_LIST {
            
            <# Recherche de la liste des backup de la VM durant la dernière année et on filtre :
                - Ceux qui se sont bien terminés 
                - Ceux qui ne sont pas encore expirés  #>
            $nbu.getVMBackupList($vmName) | Where-Object {
                $_.attributes.backupStatus -eq 0 `
                -and `
                (Get-Date) -lt [DateTime]($_.attributes.expiration -replace "Z", "")} | ForEach-Object {

                # Création d'un objet avec la liste des infos que l'on veut renvoyer 
                $backup = @{ 
                            id = $_.id
                            policyType = $_.attributes.policyType
                            policyName = $_.attributes.policyName
                            scheduleType = $_.attributes.scheduleType
                            backupTime = $_.attributes.backupTime
                            }

                # Ajout de l'objet à la liste
                $output.results += $backup
            }
        }

        # Lancement de la restauration d'un backup
        $ACTION_RESTORE_BACKUP {

            $res = $nbu.restoreVM($vmName, $restoreBackupId, $restoreTimestamp)

            # Génération de quelques infos pour le job de restore 
            $infos = @{
                        jobId = $res.id
                        msg = $res.attributes.msg
                    }
            # Ajout à la liste 
            $output.results += $infos
        }
    }

    # Affichage du résultat
    displayJSONOutput -output $output


}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant ""
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
}


# Déconnexion de l'API de backup
$nbu.disconnect()

# Déconnexion de l'API vSphere
$vsphereApi.disconnect()