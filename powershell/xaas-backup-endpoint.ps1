<#
USAGES:
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action getBackupTag -vmName <vmName>
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action setBackupTag -vmName <vmName> -backupTag (<backupTag>|"")
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action getBackupList -vmName <vmName>
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action restoreBackup -vmName <vmName> -restoreBackupId <restoreId>
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action restoreBackup -vmName <vmName> -restoreTimestamp <restoreTimestamp>
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -action getRestoreStatus -restoreJobId <restoreJobId>
    xaas-backup-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices -action VMHasSnap -vmName <vmName>
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
param ( [string]$targetEnv, 
        [string]$targetTenant,
        [string]$action, 
        [string]$vmName, 
        [string]$backupTag, 
        [string]$restoreBackupId, 
        [string]$restoreTimestamp, 
        [string]$restoreJobId)



# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))


# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "Backup", "NetBackupAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configXaaSBackup = [ConfigReader]::New("config-xaas-backup.json")
$configVra = [ConfigReader]::New("config-vra.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Récupérer ou initialiser le tag d'une VM dans vSphere
$ACTION_GET_BACKUP_TAG = "getBackupTag"
$ACTION_SET_BACKUP_TAG = "setBackupTag"

# Récupérer la liste des backup, dire à NetBackup d'en restaurer un ou statut d'un restore existant
$ACTION_GET_BACKUP_LIST = "getBackupList"
$ACTION_RESTORE_BACKUP = "restoreBackup"
$ACTION_GET_RESTORE_STATUS = "getRestoreStatus"

# Savoir si une VM a un snapshot en cours
$ACTION_VM_HAS_RUNNING_SNAPSHOT = "VMHasSnap"

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
    $logHistory = [LogHistory]::new('xaas-backup', (Join-Path $PSScriptRoot "logs"), 30)

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))
   
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

    # -------------------------------------------------------------------------------------------


    # En fonction de l'action demandée, on ouvre les connexions nécessaire sur les différents éléments, on les 
    # fermera de la même manière à la fin du script.
    # On fait de cette manière pour optimiser un peu le temps d'exécution du script et éviter de se connecter
    # à des éléments inutiles et perdre du temps...
    switch ($action)
    {
        { ($_ -eq $ACTION_GET_BACKUP_TAG) -or ($_ -eq $ACTION_SET_BACKUP_TAG) }  {
            <# Connexion à l'API Rest de vSphere. On a besoin de cette connxion aussi (en plus de celle du dessus) parce que les opérations sur les tags ne fonctionnent
                pas via les CMDLet Get-TagAssignement et autre...  #>
            $vsphereApi = [vSphereAPI]::new($configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "server")),
            $configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "user")),
            $configXaaSBackup.getConfigValue(@($targetEnv, "vSphere", "password")))

            # Si on doit activer le Debug,
            if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
            {
                # Activation du debug
                $vsphereApi.activateDebug($logHistory)    
            }
        }

        { ($_ -eq $ACTION_GET_BACKUP_LIST) -or ($_ -eq $ACTION_RESTORE_BACKUP) -or ($_ -eq $ACTION_GET_RESTORE_STATUS)} {
            # Connexion à l'API REST de NetBackup
            $nbu = [NetBackupAPI]::new($configXaaSBackup.getConfigValue(@($targetEnv, "backup", "server")),
                                        $configXaaSBackup.getConfigValue(@($targetEnv, "backup", "user")),
                                        $configXaaSBackup.getConfigValue(@($targetEnv, "backup", "password")))

            # Si on doit activer le Debug,
            if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
            {
                # Activation du debug
                $nbu.activateDebug($logHistory)    
            }
        }

        $ACTION_VM_HAS_RUNNING_SNAPSHOT {
            # Création d'une connexion au serveur vRA pour accéder à ses API REST
            $vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
                                $targetTenant, 
                                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
                                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))
        
            # Si on doit activer le Debug,
            if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
            {
                # Activation du debug
                $vra.activateDebug($logHistory)    
            }
        }
    }



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

            # S'il y a un tag de backup 
            if($null -ne $tag)
            {
                $logHistory.addLine(("Removing existing tag ({0}) on VM {1}" -f $tag.name, $vmName))
                # On supprime le tag
                $vsphereApi.detachVMTag($vmName, $tag.name)
            }

            # Si on doit ajouter un tag
            if(($backupTag -ne ""))
            {
                $logHistory.addLine(("Adding new tag ({0}) on VM {1}" -f $backupTag, $vmName))

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

        # Récupération du statut d'un restore
        $ACTION_GET_RESTORE_STATUS {

            $jobDetails = $nbu.getJobDetails($restoreJobId)

            if($null -eq $jobDetails)
            {
                $output.error = ("No job found for id {0}" -f $restoreJobId)
            }
            else
            {

                $output.results += @{
                                        restoreJobId = $restoreJobId
                                        status = $jobDetails.attributes.state.ToLower()
                                        # Cette valeur sera à $null si le job de restore est toujours en cours
                                        code = $jobDetails.attributes.status
                                    }
            }
        }

        # Savoir si la VM a un snapshot en cours
        $ACTION_VM_HAS_RUNNING_SNAPSHOT {

            $vm = $vra.getItem('Virtual Machine', $vmName)

            # Si pas trouvée 
            if($null -eq $vm)
            {
                $output.error = ("VM {0} not found" -f $vmName)
            }
            else
            {

                $output.results += @{
                                        vmName = $vmName
                                        hasSnapshot = ($vm.resourceData.entries | Where-Object { $_.key -eq "SNAPSHOT_LIST"}).value.items.length -gt 0
                                    }

            } # Fin si la VM a été trouvée 

        }

    }

    # Affichage du résultat
    displayJSONOutput -output $output
    
    # Ajout d'informations dans le log
    $logHistory.addLine("Script result `n{0}" -f ($output | ConvertTo-Json))


    # En fonction de l'action demandée, on referme les connexions
    switch ($action)
    {
        { ($_ -eq $ACTION_GET_BACKUP_TAG) -or ($_ -eq $ACTION_SET_BACKUP_TAG) }  {
            $vsphereApi.disconnect()
        }

        { ($_ -eq $ACTION_GET_BACKUP_LIST) -or ($_ -eq $ACTION_RESTORE_BACKUP) -or ($_ -eq $ACTION_GET_RESTORE_STATUS)} {
            $nbu.disconnect()
        }

        $ACTION_VM_HAS_RUNNING_SNAPSHOT {
            $vra.disconnect()
        }
    }


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
