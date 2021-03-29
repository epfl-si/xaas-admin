<#
USAGES:
    xaas-nsx-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action setVMTags -vmName <vmName> -jsonTagList <jsonTagList>
    xaas-nsx-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action addVMTags -vmName <vmName> -jsonTagList <jsonTagList>
    xaas-nsx-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action delVMTags -vmName <vmName> -tagList <tagList>
 
#>
<#
    BUT 		: Permet de faire différentes opérations dans NSX

	DATE 	: Mars 2021
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
      # JSON avec la liste des tags, avec "key=>value", ne pas oublier de mettre entre simple quotes
      # Ex: '{"key":"value", "key2":"value2"}'
      [string]$jsonTagList,
      # Juste le nom des tags, séparés par des virgules (sans espaces), ça va donner un tableau
      [Array]$tagList)


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

# Chargement des fichiers propres à XaaS
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NSXAPI.inc.ps1"))



# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configNSX      = [ConfigReader]::New("config-nsx.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_SET_VM_TAGS    = "setVMTags"
$ACTION_ADD_VM_TAGS    = "addVMTags"
$ACTION_DEL_VM_TAGS    = "delVMTags"


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le code.

	IN  : $notifications-> Dictionnaire
	IN  : $targetEnv	-> Environnement courant
	IN  : $targetTenant	-> Tenant courant
#>
function handleNotifications
{
	param([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications.$notif.count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications.$notif | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{

                # TODO: Créer les différentes notifications
				# ---------------------------------------
				# Erreur dans la récupération de stats d'utilisation pour un Bucket
				# 'bucketUsageError'
				# {
                #     $valToReplace.bucketList = ($uniqueNotifications -join "</li>`n<li>")
                #     $valToReplace.nbBuckets = $uniqueNotifications.count
				# 	$mailSubject = "Warning - S3 - Usage info not found for {{nbBuckets}} Buckets"
				# 	$templateName = "xaas-s3-bucket-usage-error"
				# }
			

				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			$notificationMail.send($mailSubject, $templateName, $valToReplace)

		} # FIN S'il y a des notifications pour la catégorie courante

	}# FIN BOUCLE de parcours des catégories de notifications
}


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
    $logHistory = [LogHistory]::new(@('xaas','nsx', 'endpoint'), $global:LOGS_FOLDER, 120)
    
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
    
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
    #>
    # TODO: A adapter en ajoutant des clefs pointant sur des listes
	$notifications=@{
                    }
                                                
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création d'une connexion au serveur NSX pour accéder aux API REST de NSX
	$logHistory.addLine("Connecting to NSX-T...")
	$nsx = [NSXAPI]::new($configNSX.getConfigValue(@($targetEnv, "server")), 
						 $configNSX.getConfigValue(@($targetEnv, "user")), 
						 $configNSX.getConfigValue(@($targetEnv, "password")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $nsx.activateDebug($logHistory)    
    }

    # Si on a un nom de VM
    if($vmName -ne "")
    {
        $logHistory.addLine(("Getting Virtual Machine {0}..." -f $vmName))
        $vm = $nsx.getVirtualMachine($vmName)
        
        # Si la VM demandée n'existe pas,
        if($null -eq $vm)
        {
            Throw ("Virtual Machine {0} doesn't exists" -f $vmName)
        }
    }

    # Si on a reçu la liste des tags en JSON, on créé l'objet
    if($jsonTagList -ne "")
    {
        # Transformation du JSON qu'on a récupéré pour avoir une Hashtable, car ça permettra de travailler plus 
        # facilement dessus de cette manière
        $tagList = PSCustomObjectToHashtable -obj ($jsonTagList | ConvertFrom-Json)
    }

    
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Initialisation des tags d'une VM
        $ACTION_SET_VM_TAGS {
            
            $logHistory.addLine("Assigning tags on Virtual Machine...")
            # Création des tags
            $vm = $nsx.setVirtualMachineTags($vm, $tagList)
        

        }


        # -- Ajout de tags à une VM
        $ACTION_ADD_VM_TAGS {
            
            # Extraction des tags existants sur la VM
            $existingTags = $vm.tags
            if($null -eq $existingTags)
            {
                $existingTags = @()
            }
            

            $logHistory.addLine(("Current Tag list is:`n{0}" -f ( ($existingTags | ForEach-Object { ("{0}={1}" -f $_.tag, $_.scope) }) -join "`n")))
            

            $logHistory.addLine(("Adding missing tags:`n{0}" -f (($tagList.keys | Foreach-Object { ("{0}={1}" -f $_, $tagList[$_])}) -join "`n")))

            # Liste des nouveau tags
            $newTags = [HashTable]@{}
            if($existingTags.count -gt 0)
            {

            }
            # Ajout des tags existants
            $existingTags | Foreach-Object {
                $newTags.Add($_.tag, $_.scope)
            }

            # Ajout/mise à jour de ce qui manque
            $tagList.keys | Foreach-Object {
                $newTags[$_] = $tagList[$_]
            }

            $logHistory.addLine(("Assigning updated tags on Virtual Machine:`n{0}" -f ( ($newTags.keys | Foreach-Object { ("{0}={1}" -f $_, $newTags[$_])}) -join "`n")))
            # Ajout des tags
            $vm = $nsx.setVirtualMachineTags($vm, $newTags)
        }


        # -- Suppression de tags d'une VM
        $ACTION_DEL_VM_TAGS {
            
            # Extraction des tags existants sur la VM
            $existingTags = $vm.tags
            if($null -eq $existingTags)
            {
                $existingTags = @()
            }
            $logHistory.addLine(("Current Tag list is:`n{0}" -f ( ($existingTags | ForEach-Object { ("{0}={1}" -f $_.tag, $_.scope) }) -join "`n")))

            $logHistory.addLine(("Removing unwanted tags:`n{0}" -f (($tagList.keys | Foreach-Object { ("{0}={1}" -f $_, $tagList[$_])}) -join "`n")))

            # Liste des nouveau tags
            $newTags = [HashTable]@{}
            # Ajout des tags existants en sautant ceux qui ne doivent pas y être
            $existingTags | Foreach-Object {
                if($tagList -notcontains $_.tag)
                {
                    $newTags.Add($_.tag, $_.scope)
                }
            }

            $logHistory.addLine(("Assigning updated tags on Virtual Machine:`n{0}" -f ( ($newTags.keys | Foreach-Object { ("{0}={1}" -f $_, $newTags[$_])}) -join "`n")))
            # Ajout des tags
            $vm = $nsx.setVirtualMachineTags($vm, $newTags)
        
        }


        default {
            Throw ("Action '{0}' not supported" -f $action)
        }
    }

    $logHistory.addLine("Script execution done!")


    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

    # Gestion des erreurs s'il y en a
    handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant
    

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