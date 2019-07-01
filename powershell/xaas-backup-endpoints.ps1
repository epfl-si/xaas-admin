<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service de Backup en tant que XaaS.

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

    PARAMETRES:
        -targetEnv          -> Environnement cible pour l'exécution. Les valeurs possibles sont définies dans
                                include/define.inc.ps1 => $global:TARGET_ENV__*
        -action             -> l'action que l'on demande au script d'effectuer, elles sont définies plus bas, dans
                                la partie qui traite des constantes.
        -vmName             -> Nom de la VM concernée par l'action.
        -backupTag          -> Tag de backup à affecter à une VM. A passer uniquement si $action == $ACTION_SET_BACKUP_TAG
                                Si on désire désactiver le backup pour une VM, on doit passer un tag vide.
        -restoreBackupId    -> ID du backup à restaurer. A passer uniquement si $action == $ACTION_RESTORE_BACKUP

#>
param ( [string]$targetEnv, [string]$action, [string]$vmName, [string]$backupTag, [string]$restoreBackupId)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NetBackupAPI.inc.ps1"))

# Chargement des fichiers de configuration
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config", "config-mail.inc.ps1"))
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config", "config-xaas-backup.inc.ps1"))

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Récupérer ou initialiser le tag d'une VM dans vSphere
$ACTION_GET_BACKUP_TAG = "getBackupTag"
$ACTION_SET_BACKUP_TAG = "setBackupTag"

# Récupérer la liste des backup ou dire à NetBackup d'en restaurer un
$ACTION_GET_BACKUP_LIST = "getBackupList"
$ACTION_RESTORE_BACKUP = "restoreBackup"

# Liste de toutes les actions pour la validation des paramètres plus bas
$ALL_ACTIONS = @(
    $ACTION_GET_BACKUP_TAG
    $ACTION_SET_BACKUP_TAG
    $ACTION_GET_BACKUP_LIST
    $ACTION_RESTORE_BACKUP
)

$NBU_TAG_CATEGORY = "NBU"
$NBU_TAG_PREFIX = "NBU-"

# -------------------------------------------- FONCTIONS ---------------------------------------------------


<#
-------------------------------------------------------------------------------------
    BUT : Renvoie l'objet à utiliser pour effectuer l'affichage du résultat d'exécution 
            du script
#>
function getObjectForOutput
{
    return @{
            error = ""
            results = @()
        }
}


<#
-------------------------------------------------------------------------------------
    BUT : Affiche le résultat de l'exécution en JSON
    
    IN  : $output -> objet (créé à la base avec getObjectForOutput) contenant le 
                        résultat à afficher
#>
function displayJSONOutput
{
    param([psobject]$output)

    Write-Host ($output | ConvertTo-Json -Depth 100)
}


<#
-------------------------------------------------------------------------------------
    BUT : Affiche comment utiliser le script
    
    IN  : $errorDetails     -> détails de l'erreur
#>
function printUsage
{
    param([string]$errorDetails)
   	$invoc = (Get-Variable MyInvocation -Scope 1).Value
   	$scriptName = $invoc.MyCommand.Name

    $output = getObjectForOutput

    $envStr = $global:TARGET_ENV_LIST -join "|"
    
    # Génération de l'erreur
    $output.error = ("{6}`n`n `
Possibles usages: `n `
{0} -targetEnv {1} -action {2}|{3} -vmName <vmName>`n `
{0} -targetEnv {1} -action {4} -vmName <vmName> -backupTag <backupTag> `n `
{0} -targetEnv {1} -action {5} -vmName <vmName> -restoreBackupId <backupId>" -f `
                        $scriptName, ` # 0 
                        $envStr, ` # 1
                        $ACTION_GET_BACKUP_TAG, ` # 2
                        $ACTION_GET_BACKUP_LIST,` # 3
                        $ACTION_SET_BACKUP_TAG, ` # 4
                        $ACTION_RESTORE_BACKUP, ` # 5
                        $errorDetails ) # 6
    
    # Affichage du résultat
    displayJSONOutput -output $output
    
    # et on quitte le script
    exit
}


<#
-------------------------------------------------------------------------------------
    BUT: Défini si un paramètre est valide. Si ce n'est pas le cas, on affiche l'usage et on quitte

    IN  : $value            -> la valeur du paramètre
    IN  : $allowEmpty       -> $true|$false pour dire si le paramètre peut être vide
    IN  : $allowedValues    -> tableau avec la liste des valeurs autorisées pour le paramètre
                                Si tableau vide passé, on ne prend pas en compte.   
    IN  : $errorDetails     -> détails de l'erreur à afficher dans le cas où c'est une erreur    
#>
function checkParam
{
    param([string]$value, [bool]$allowEmpty, [Array]$allowedValues, [string]$errorDetails)

    # Si on ne peut pas passer de paramètre vide et que le paramètre est vide, 
    if((($allowEmpty -eq $false) -and ($value -eq "")) `
        -or `
        # Si on a une liste de valeurs autorisées et que ce n'est pas dans celle-ci
        (($allowedValues.Count -gt 0) -and($allowedValues -notcontains $value))) 
    {
        printUsage -errorDetails $errorDetails
        exit 1
    }
}


<#
-------------------------------------------------------------------------------------
    BUT: Retourne le tag de backup pour la VM dont le nom est passé en paramètre 

    IN  : $vmName       -> Nom de la VM dont on veut le tag de backup

    RET :   Le tag de backup
            $null si n'existe pas
#>
function getVMBackupTag
{
    param([string]$vmName)

    $tagList = Get-VM -Name $vmName | Get-TagAssignment | Where-Object { $_.Tag -like ("{0}/{1}*" -f $NBU_TAG_CATEGORY, $NBU_TAG_PREFIX)}

    # Si aucun tag dans la liste
    if($null -ne $tagList)
    {
        # Le tag étant au format <Category>/<tagName>, on extrait les informations.
        # NOTE: on ne renvoie que le premier tag de la liste. Pas d'erreur/warning si plusieurs tags sont définis (à priori, ce n'est pas possible)
        $tagCategory, $tag = ([string]($tagList[0].tag)).split("/")

        return $tag
    }

    return $null
}


<#
-------------------------------------------------------------------------------------
    BUT: Supprime le tag de backup de la VM donnée

    IN  : $vmName       -> Nom de la VM dont on veut le tag de backup

#>
function deleteVMBackupTag
{
    param([string]$vmName)

    # Recherche du tag avec le filtre puis suppression de celui-ci 
    Get-VM -Name $vmName | Get-TagAssignment | Where-Object { $_.Tag -like ("{0}/{1}*" -f $NBU_TAG_CATEGORY, $NBU_TAG_PREFIX)} | Remove-TagAssignment -Confirm:$false
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
try
{
    # Test des paramètres
    if(($targetEnv -eq "") -or (-not(targetEnvOK -targetEnv $targetEnv)))
    {
        printUsage -errorDetails "Incorrect value for '-targetEnv'"
        exit
    }

    # Contrôle des autres paramètres 
    checkParam -value $action -allowEmpty $false -allowedValues $ALL_ACTIONS -errorDetails "Incorrect value for '-action'"
    checkParam -value $vmName -allowEmpty $false -allowedValues @() -errorDetails "Incorrect value for '-vmName'"

    checkParam -value $backupTag -allowEmpty $true

    if($action -eq $ACTION_RESTORE_BACKUP)
    {
        checkParam -value $restoreBackupId -allowEmpty $false -allowedValues @() -errorDetails "Incorrect value for '-restoreBackupId'"
    }
    

    # -------------------------------------------------------------------------------------------

    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-backup', (Join-Path $PSScriptRoot "logs"), 30)
    
    # Chargement des modules PowerCLI pour pouvoir accéder à vSphere.
    loadPowerCliModules

    # Pour éviter que le script parte en erreur si le certificat vCenter ne correspond pas au nom DNS primaire. On met le résultat dans une variable
    # bidon sinon c'est affiché à l'écran.
    $dummy = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

    # Connexion au serveur vSphere
    $connectedvCenter = Connect-VIServer -Server $global:XAAS_BACKUP_VCENTER_SERVER_LIST[$targetEnv] `
                                         -user $global:XAAS_BACKUP_VCENTER_USER_LIST[$targetEnv] `
                                         -Password $global:XAAS_BACKUP_VCENTER_PASSWORD_LIST[$targetEnv]

    # Connexion à l'API REST de NetBackup
    $nbu = [NetBackupAPI]::new($global:XAAS_BACKUP_SERVER_LIST[$targetEnv], $global:XAAS_BACKUP_USER_LIST[$targetEnv], $global:XAAS_BACKUP_PASSWORD_LIST[$targetEnv])   

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters")
    $logHistory.addLine("-action = {0}" -f $action)
    $logHistory.addLine("-vmName = {0}" -f $vmName)
    $logHistory.addLine("-backupTag = {0}" -f $backupTag)
    $logHistory.addLine("-restoreBackupId = {0}" -f $restoreBackupId)

    # En fonction de l'action demandée
    switch ($action)
    {
        # ------------------------- vSphere -------------------------

        # Récupération du tag d'une VM
        $ACTION_GET_BACKUP_TAG {

            # Récupération du tag de backup existant
            $tag = getVMBackupTag -vmName $vmName
            
            # Si un tag est trouvé,
            if($null -ne $tag)
            {
                # Génération du résultat
                $output.results += $tag
            }
            
        }


        # Initialisation du tag d'une VM
        $ACTION_SET_BACKUP_TAG {

            # Si on doit ajouter un tag
            if($backupTag -ne "")
            {
                # Récupération du tag de backup existant
                $tag = getVMBackupTag -vmName $vmName
                
                # Si un tag est trouvé,
                if($null -ne $tag)
                {
                    # Suppression du tag existant
                    deleteVMBackupTag -vmName $vmName
                }
                
                # Ajout du tag
                $dummy = Get-VM -Name $vmName | New-TagAssignment -Tag $backupTag -Confirm:$false
            }
            else # On doit supprimer le tag existant
            {
                deleteVMBackupTag -vmName $vmName
            }
        }


        # ------------------------- NetBackup -------------------------

        # Récupération de la liste des backup FULL d'une VM durant l'année écoulée
        $ACTION_GET_BACKUP_LIST {
            
            # Recherche de la liste des backup de la VM et on filtre ceux qui se sont bien terminés
            $nbu.getVMBackupList($vmName, "FULL", 365) | Where-Object {$_.attributes.backupStatus -eq 0} | ForEach-Object {

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

            $res = $nbu.restoreVM($vmName, $restoreBackupId)

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
	$mailMessage = getvRAMailContent -content ("<b>Script:</b> {0}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Web.HttpUtility]::HtmlEncode($errorTrace))

	sendMailTo -mailAddress $global:ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $mailMessage
}


# Déconnexion du serveur vCenter
Disconnect-VIServer  -Server $connectedvCenter -Confirm:$false 

# Déconnexion de l'API de backup
$nbu.disconnect()