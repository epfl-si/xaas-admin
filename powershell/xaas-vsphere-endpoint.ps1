<#
USAGES:
    xaas-vsphere-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl -action updateVMStoragePolicies -vmName <vmName> -diskPoliciesJSON <diskPoliciesJSON>
 
#>
<#
    BUT 		: Permet d'effectuer des opérations sur les éléments faisant partie de l'infrastructure SAP

	DATE 	: Mai 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
    

    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    DOCUMENTATION: TODO:

#>
param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$vmName,
      [string]$diskPoliciesJSON) # Tableau associatif avec en ID les noms de disque et en valeur, la policy à mettre


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVSphere 	= [ConfigReader]::New("config-vsphere.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_UPDATE_STORAGE_POLICIES              = "updateVMStoragePolicies"



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
    $logHistory = [LogHistory]::new(@('vsphere', 'endpoint'), $global:LOGS_FOLDER, 120)
    
    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)
                                                
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

                                                
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    $vsphereApi = [vSphereAPI]::new($configVSphere.getConfigValue(@($targetEnv, "server")), 
                                    $configVSphere.getConfigValue(@($targetEnv , "user")), 
                                    $configVSphere.getConfigValue(@($targetEnv, "password")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $vsphereApi.activateDebug($logHistory)    
    }
    

    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Mise à jour des storages policies
        $ACTION_UPDATE_STORAGE_POLICIES {
            
            $logHistory.addLine(("Getting Storage Policies for VM '{0}'..." -f $vmName))

            $vmStoragePolicieInfos = $vsphereApi.getVMStoragePolicyInfos($vmName)

            # Si pas trouvé
            if($null -eq $vmStoragePolicieInfos)
            {
                Throw ("No Storage Policies found for VM '{0}'" -f $vmName)
            }

            $logHistory.addLine(("Preparing new storage policies for disks..."))

            # Pour enregistrer les nouvelles policies à mettre pour les disques
            $disksNewPolicies = @{}

            # Création d'un objet avec les infos pour les disques à mettre à jour
            $diskPoliciesToUpdate = $diskPoliciesJSON | ConvertFrom-Json

            $vmDiskIdList = $vsphereApi.getVMDiskIdList($vmName)
            ForEach($diskId in $vmDiskIdList)
            {
                # Recherche des infos du disque
                $diskInfos = $vsphereApi.getVMDiskInfos($vmName, $diskId)

                $logHistory.addLine(("> Found disk '{0}' with ID '{1}'" -f $diskInfos.label, $diskId))

                # On regarde si on a une storage Policy à changer pour le disque courant
                $diskNewPolName = $diskPoliciesToUpdate.($diskInfos.label)

                # Si on doit changer la policy de stockage pour le disque
                if($null -ne $diskNewPolName)
                {
                    $logHistory.addLine((">> Change to policy '{0}'" -f $diskNewPolName))

                    $newStoragePolicy = $vsphereApi.getStoragePolicyByName($diskNewPolName)

                    if($null -eq $newStoragePolicy)
                    {
                        Throw ("Storage Policy '{0}' doesn't exists" -f $diskNewPolName)
                    }

                    $disksNewPolicies.$diskId = $newStoragePolicy.policy
                }
                else # Pas besoin de changer la policy de stockage
                {
                    $logHistory.addLine(">> Keeps its policy (ID={0})" -f $vmStoragePolicieInfos.disks.$diskId)
                    $disksNewPolicies.$diskId = $vmStoragePolicieInfos.disks.$diskId
                }
                
            }# FIN BOUCLE de parcours des disques de la VM

            $homeStoragePolicy = $newStoragePolicy = $vsphereApi.getStoragePolicyByName($diskPoliciesToUpdate.vmhome)

            if($null -eq $homeStoragePolicy)
            {
                Throw ("Home Storage Policy '{0}' doesn't exists" -f $diskPoliciesToUpdate.vmhome)
            }

            # Si la policy Home a changé
            if($homeStoragePolicy.policy -ne $vmStoragePolicieInfos.vm_home)
            {
                $logHistory.addLine(("Changing VM Home Storage Policy to '{0}' " -f $homeStoragePolicy.name))
            }


            $logHistory.addLine(("Updating VM '{0}' storage policies..." -f $vmName))
            $vsphereApi.updateVMStoragePolicyList($vmName, $homeStoragePolicy.policy, $disksNewPolicies)

        }# FIN Action mise à jour des storages policies


        default {
            Throw ("Action '{0}' not supported" -f $action)
        }

    }

    $logHistory.addLine("Script execution done!")


    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

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