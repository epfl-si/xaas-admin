<#
   BUT : Permet de procéder à une extension de quota qui a été demandée par l'utilisateur
         et validée par l'admin de faculté
         
   
   AUTEUR : Lucien Chaboudez
   DATE   : Novembre 2014
   
   PARAMETRES :
   - Aucun -   
   
   REMARQUE : Ce script pourrait être amélioré en enregistrant, pendant l'exécution, la liste des volumes/vserver
              sur lesquels faire un "resize" et faire ceux-ci à la fin du script. Cela permettrait de gagner du temps.
              Cependant, cette possibilité n'a pas été implémentée dans le script courant car à priori, plus aucune
              augmentation de quota ne sera autorisée (ou alors cela sera des cas isolés). Du coup, la performance
              du script devient plus que relative...
   
   MODIFS:
   15.04.2015 - LC - Modification de la gestion des "resize" de volumes. Regroupage au lieu d'en faire un après 
                     chaque augmentation pour un utilisateur. Ceci diminue la durée d'exécution du script.
                   - Ajout d'envoi de mail pour informer de ce qui a été effectué.
   16.06.2017 - LC - Modification de la commande pour initialiser le quota. Depuis PowerShell Toolkit 4.4, il faut 
                     passer le chiffre en bytes et plus un chiffre avec une unité.
   21.08.2017 - LC - Il y avait une erreur quand on multipliait le quota par 1024 pour avoir des bytes... C'était un
                     string qui était multiplié 1024x ... correction. 
   
#>

# Inclusion des constantes
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# ------------------------------------------------------------------------

<#
   BUT : Initialise un utilisateur comme ayant eu une update de quota en appelant le WebService 
         adéquat.
         
   IN  : $userSciper    -> Sciper de l'utilisateur pour lequel le quota a été mis à jour
#>
function setQuotaUpdateDone 
{
   param($userSciper)
   
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-quota-update-done.php?sciper="+$userSciper
   
   # Appel de l'URL pour initialiser l'utilisateur comme renommé 
   getWebPageLines -url $url | Out-Null
}


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

	IN  : $notifications-> Dictionnaire
#>
function handleNotifications
{
	param([System.Collections.IDictionary] $notifications)

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

				# Erreurs de renommage des dossiers utilisateurs
				'quotaUpdatedUser'
				{
					$valToReplace.updateList = ($uniqueNotifications -join "")
					$mailSubject = "Info - {0} user(s) quota(s) updated" -f $uniqueNotifications.count
					$templateName = "quota-updated-users"
            }

            # Utilisateurs non trouvés dans AD
            'usersNotInAD'
            {
					$valToReplace.userList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Warning - Quota update - {0} user(s) not found in AD" -f $uniqueNotifications.count
					$templateName = "quota-update-users-not-in-ad"
            }
     

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

   # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
   $logHistory = [LogHistory]::new('mynas-process-quota-update', (Join-Path $PSScriptRoot "logs"), 30)
    
   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MYNAS_MAIL_TEMPLATE_FOLDER, $global:MYNAS_MAIL_SUBJECT_PREFIX, @{})

   <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
   #>
   $notifications = @{
      quotaUpdatedUser = @()
      usersNotInAD = @()
   }

   # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
   $counters.add('nbQuotaUpdated', '# quota updated')
   $counters.add('nbQuotaOK', '# quota OK')
   $counters.add('nbUsersNotFound', '# User not found in AD')

   # Création de l'objet pour se connecter aux clusters NetApp
   $netapp = [NetAppAPI]::new($configMyNAS.getConfigValue(@("nas", "serverList")),
                              $configMyNAS.getConfigValue(@("nas", "user")),
                              $configMyNAS.getConfigValue(@("nas", "password")))

   # le format des lignes renvoyées est le suivant :
   # <volumeName>,<usernameShort>,<vServerName>,<Sciper>,<softQuotaKB>,<hardQuotaKB>
   $quotaUpdateList = downloadPage -url ("$global:WEBSITE_URL_MYNAS/ws/v2/get-quota-updates.php") | ConvertFrom-Json

   if($quotaUpdateList -eq $false)
   {
      Throw "Error getting quota update list!"
   }

   $logHistory.addLineAndDisplay(("{0} quota(s) to update" -f $quotaUpdateList.count))

   # Si rien à faire,
   if($quotaUpdateList.count -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }


   # Pour la liste des volumes
   $volList = @{}

   # Parcours des éléments à renommer 
   foreach($updateInfos in $quotaUpdateList)
   {
      
      # On commence par regarder si l'utilisateur existe dans AD
      try
      {
         Get-ADUser $updateInfos.username | Out-Null
      }
      catch
      {
         # Si l'utilisateur n'existe pas, c'est qu'il a dû y avoir une erreur dans la gestion des données (venant de CADI probablement) 
         $logHistory.addWarningAndDisplay(("User {0} doesn't exists in ActiveDirectory, skipping it" -f $updateInfos.username))

         # On initialise la requête comme ayant été traitée pour pas que l'on retombe sur cet utilisateur à la prochaine exécution du script.
         setQuotaUpdateDone -userSciper $updateInfos.sciper

         $notifications.usersNotInAD += $updateInfos.username

         $counters.inc('nbUsersNotFound')
         continue
      }

      # Génréation des informations 
      $usernameAndDomain="INTRANET\"+$updateInfos.username
      
      $logHistory.addLineAndDisplay("Changing quota for $usernameAndDomain ")
      
      # Si on n'a pas encore les infos du volume en cache,
      if($volList.Keys -notcontains $updateInfos.volumeName)
      {
         # Recherche des infos du volume sur lequel on doit travailler
         $volList.($updateInfos.volumeName) = $netapp.getVolumeByName($updateInfos.volumeName)
      }

      # Recherche du quota actuel 
      $currentQuota = $netapp.getUserQuotaRule($volList.($updateInfos.volumeName), $usernameAndDomain)
      
      # Si pas trouvé, c'est que l'utilisateur a le quota par défaut
      if($null -eq $currentQuota)
      {
         $currentQuotaMB = "'default'"
      }
      else
      {
         $currentQuotaMB = ([Math]::Floor($currentQuota.space.hard_limit/1024/1024))
      }
      
      # Si le quota est différent ou que l'entrée de quota n'existe pas,
      if(($null -eq $currentQuota) -or ($currentQuota.space.hard_limit -ne ($updateInfos.hardKB * 1024)))
      {
         $logHistory.addLineAndDisplay(("-> Updating quota... Current: "+$currentQuotaMB+" MB - New: "+([Math]::Floor($updateInfos.hardKB/1024))+" MB... ") )
         
         # Exécution de la requête (et attente que le resize soit fait)
         $netapp.updateUserQuotaRule($volList.($updateInfos.volumeName), $usernameAndDomain, $updateInfos.hardKB/1024)
         
         # On initialise la requête comme ayant été traitée
         setQuotaUpdateDone -userSciper $updateInfos.sciper
            
         # Ajout de l'info au message qu'on aura dans le mail 
         $notifications.quotaUpdatedUser += ("<tr><td>{0}</td><td>{1}</td><td>{2}</td></tr>" -f $updateInfos.username, $currentQuotaMB, ([Math]::Floor($updateInfos.hardKB/1024)))
         
         $counters.inc('nbQuotaUpdated')
      }
      else # Le quota est correct
      {
         $logHistory.addLineAndDisplay(( "-> Quota is correct ({0} MB), no change needed" -f $currentQuota.space.hard_limit ))
         $counters.inc('nbQuotaOK')
      }

   }# FIN BOUCLE de parcours des quotas à modifier

   $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))
   
   # Gestion des erreurs s'il y en a
   handleNotifications -notifications $notifications

}
catch
{
    
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
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