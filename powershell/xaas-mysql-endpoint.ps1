<#
USAGES:
    xaas-mysql-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action create -bgId <bgId> -friendlyName <friendlyName> [-linkedTo <linkedTo>] [-bucketTag <bucketTag>]
 
#>
<#
    BUT 		: Ce script est utilisé pour traiter les demandes pour le XaaS MySQL

	DATE 	: Janvier 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
    - Ce script prend du temps à s'exécuter car il charge le PowerCLI Amazon S3 et ce dernier étant énoOOOrme, 
        ça prend du temps... une tentative de ne  charger que les CmdLets nécessaires a été faite mais ça 
        n'accélère en rien...


    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    DOCUMENTATION: TODO:

#>

# TODO: adapter les paramètres en fonction de l'utilisation
param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$bgId,
      [string]$bucketTag,
      [switch]$status)

# Chargement du module PowerShell
# TODO: si besoin

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

# Chargement des fichiers propres à XaaS TODO: inclure les fichiers spécifiques



# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configMySQL = [ConfigReader]::New("config-xaas-mysql.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_DELETE              = "delete"
# TODO: Compléter la liste des actions


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
    # TODO: Adapter la ligne suivante
    #$logHistory = [LogHistory]::new('xaas-s3', (Join-Path $PSScriptRoot "logs"), 30)
    
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

    # TODO: Ajouter ici la création des éléments d'accès au backend. Voir Exemple
    # $scality = [ScalityAPI]::new($configXaaSS3.getConfigValue(@($targetEnv, "server")),
    #                              $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "credentialProfile")),
    #                              $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "webConsoleUser")),
    #                              $configXaaSS3.getConfigValue(@($targetEnv, $targetTenant, "webConsolePassword")),
    #                              $configXaaSS3.getConfigValue(@($targetEnv, "isScality")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $scality.activateDebug($logHistory)    
    }
    

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)


    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau bucket 
        $ACTION_CREATE {

            $doCleaningIfError = $true

        }# FIN Action Create


        # -- Effacement d'un bucket
        $ACTION_DELETE {

        }

        # TODO: Compléter avec la liste des actions définies précédemment
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

    # Si on était en train de créer un bucket et qu'on peut faire le cleaning
    if(($action -eq $ACTION_CREATE) -and $doCleaningIfError)
    {
        # TODO: Adapter le contenu

        # On efface celui-ci pour ne rien garder qui "traine"
        #$logHistory.addLine(("Error while creating Bucket '{0}', deleting it so everything is clean. Error was: {1}" -f $bucketInfos.bucketName, $errorMessage))

        # Suppression du bucket
        #deleteBucket -scality $scality -bucketName $bucketInfos.bucketName
    }

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