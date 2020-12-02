<#
   BUT : Traite les demandes de renommage de dossier utilisateurs
   
   AUTEUR : Lucien Chaboudez
   DATE   : 23.07.2014

   REMARQUE : Ce script ne gère pas les cas où plusieurs utilisateurs ont changé de "username" sur le
              même volume. Dans ce cas-là, il y aura une erreur et un mail sera envoyé. Il faudra 
              effectuer les corrections à la main. Au vu du peu d'utilisateur qui changent de "username",
              aucun temps supplémentaire n'a été pris pour pouvoir gérer le cas de figure en question.

   PARAMETRES : Aucun
   
   MODIFS :
   29.05.2015 - LC - Modif car quelques bug
                   - Reformatage du mail car c'est de l'HTML et c'était envoyé en mode texte donc au final
                     l'affichage était pourri...
   16.06.2017 - LC - (Peut-être) suite à installation des PowerShell Toolkit 4.4, lorsque l'on fait un Set-NcQuota,
                     il ne faut plus passer l'unité dans laquelle on donne le chiffre du quota mais il faut le passer
                     en bytes.
   30.09.2020 - LC - Refonte complète pour utiliser API REST au lieu du module DataONTAP pour PowerShell. 
#>

# Inclusion des constantes
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "NameGeneratorMyNAS.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# ------------------------------------------------------------------------
# ---------------------------- FONCTIONS ---------------------------------

<#
   BUT : Initialise un utilisateur comme renommé en appelant le WebService 
         adéquat.
         
   IN  : $renameInfos.sciper    -> Sciper de l'utilisateur qu'on veut initialiser comme renommé.
#>
function setUserRenamed 
{
   param($sciper)
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-user-renamed.php?sciper="+$sciper
   
   # Appel de l'URL pour initialiser l'utilisateur comme renommé 
   getWebPageLines -url $url | Out-Null
}


# ------------------------------------------------------------------------
<#
   BUT : Permet de savoir si un dossier est vide
         
   IN  : $folderPath -> chemin jusqu'au dossier

   RET : $true | $false
#>

function isFolderEmpty([string]$folderPath)
{
   return (Get-ChildItem $folderPath| Measure-Object).Count -eq 0
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
				'usernameRenameErrors'
				{
					$valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Users folder not renamed"
					$templateName = "user-rename-error"
            }
            
            # Pas possible de renommer correctement car des données dans l'ancien et le nouveau dossier
            'bothFoldersData'
            {
               $valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - User rename - Old and new folder exists"
					$templateName = "both-folders-data"
            }

            'oldFolderIncorrectOwner'
            {
               $valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
               $valToReplace.folderType = "vieux"
					$mailSubject = "Error - User rename - Incorrect owner on old folder"
					$templateName = "incorrect-owner"
            }

            'newFolderIncorrectOwner'
            {
               $valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
               $valToReplace.folderType = "nouveaux"
					$mailSubject = "Error - User rename - Incorrect owner on new folder"
					$templateName = "incorrect-owner"
            }

            'bothFoldersNotFound'
            {
               $valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Users folder not renamed - none of the folders exists"
					$templateName = "both-folders-not-found"
            }

            'ownerNotFoundForFolder'
            {
               $valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Users folder not renamed - Owner not found"
					$templateName = "owner-not-found"
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
   $logHistory = [LogHistory]::new('mynas-process-username-rename', (Join-Path $PSScriptRoot "logs"), 30)
    
   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MYNAS_MAIL_TEMPLATE_FOLDER, $global:MYNAS_MAIL_SUBJECT_PREFIX, @{})
   
   # Création de l'objet pour se connecter aux clusters NetApp
   $netapp = [NetAppAPI]::new($configMyNAS.getConfigValue("nas", "serverList"), `
                              $configMyNAS.getConfigValue("nas", "user"), `
                              $configMyNAS.getConfigValue("nas", "password"))

   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()
   
   <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
   #>
   $notifications = @{
      usernameRenameErrors = @()
      bothFoldersData = @()
      oldFolderIncorrectOwner = @()
      newFolderIncorrectOwner = @()
      bothFoldersNotFound = @()
      ownerNotFoundForFolder = @()
   }
   
   $logHistory.addLineAndDisplay("Getting infos... ")
   # Récupération de la liste des renommages à effectuer
   $renameList = downloadPage -url ($global:WEBSITE_URL_MYNAS+"ws/v2/get-users-to-rename.php") | ConvertFrom-Json

   if($renameList -eq $false)
   {
      Throw "Error getting rename list!"
   }

   $logHistory.addLineAndDisplay(("{0} folder(s) to rename" -f $renameList.Count))

   # Si rien à faire,
   if($renameList.Count -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }


   # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
   $counters.add('nbRename', '# User renamed')
   $counters.add('nbAlreadyRenamed', '# User already renamed')
   $counters.add('nbRenameError', '# User rename errors')

   # Parcours des éléments à renommer 
   foreach($renameInfos in $renameList)
   {
      # Pour savoir si les dossiers sont présents
      $noNewFolder = $false
      $noOldFolder = $false
      
      # Définition des UNC du dossier actuel et du nouveau pour les tests d'existence
      $uncPathCur = $nameGeneratorMyNAS.getUserUNCPath($renameInfos.vserver, $renameInfos.oldUsername)
      $uncPathNew = $nameGeneratorMyNAS.getUserUNCPath($renameInfos.vserver, $renameInfos.newUsername)
         
      $logHistory.addLineAndDisplay(("Rename: {0} => {1}" -f $renameInfos.oldUsername, $renameInfos.newUsername))
      
      # Si l'ancien dossier existe,
      if(Test-Path $uncPathCur -pathtype container) 
      {
         $logHistory.addLineAndDisplay(" -> Old folder exists... ")
      
         # Récupération du owner de l'ancien dossier       
         $domain, $curFolderOwner = ((Get-Acl $uncPathCur).owner).Split('\')
         
         # Si pas de owner trouvé 
         if($null -eq $curFolderOwner)
         {
            $notifications.ownerNotFoundForFolder += $uncPathCur
         }      
         #Si le owner correspond, 
         elseif( ($curFolderOwner -eq $renameInfos.newUsername) -or ($curFolderOwner -eq $renameInfos.oldUsername) )
         {
            $logHistory.addLineAndDisplay("-> Owner OK... ")

            # Si le nouveau dossier n'existe pas      
            if(!(Test-Path $uncPathNew -pathtype container) )
            {
               $logHistory.addLineAndDisplay("-> New folder doesn't exists... renaming old... ")

               # Renommage du dossier + gestion des erreurs 
               try
               {
                  # Tentative de renommage
                  Rename-Item -Path $uncPathCur -NewName $uncPathNew -Force
                  
                  $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                  
                  # On initialise l'utilisateur comme ayant été renommé.
                  setUserRenamed -sciper $renameInfos.sciper
                  
                  $counters.inc('nbRename')
               }
               catch
               {
                  # Ajout de l'erreur à la liste 
                  $notifications.usernameRenameErrors += ($uncPathCur+" to "+$uncPathNew)
                  $logHistory.addErrorAndDisplay("-> Error renaming folder")
                  
                  $counters.inc('nbRenameError')
               }

            }
            else # Le nouveau dossier existe déjà
            {
               $logHistory.addLineAndDisplay("-> New folder already exists... ")

               # Récupération de l'UID du nouveau dossier 
               $domain, $newFolderOwner = ((Get-Acl $uncPathNew).owner).Split('\')
               
               # Si le owner du nouveau dossier est incorrect (qu'il ne correspond pas à l'utilisateur)
               if( ($newFolderOwner -ne $renameInfos.newUsername) -and ($newFolderOwner -ne $renameInfos.oldUsername))
               {
                  $logHistory.addErrorAndDisplay("-> New folder owner incorrect!")
                  
                  # Ajout des infos dans le "log" 
                  $notifications.newFolderIncorrectOwner += ("{0}: Is INTRANET\{1} and should be INTRANET\{2} or INTRANET\{3}" -f `
                                                             $uncPathNew, $newFolderOwner, $renameInfos.newUsername, $renameInfos.oldUsername)

                  $counters.inc('nbRenameError')
               }
               else # Le owner du nouveau dossier est correct
               {
                  $logHistory.addLineAndDisplay("-> Owner OK... ")
                  # Si l'ancien dossier est vide
                  if(isFolderEmpty -folderPath $uncPathCur)
                  {
                     $logHistory.addLineAndDisplay("-> Old empty, deleting... ")
                     
                     # Suppression de "l'ancien" dossier
                     Remove-item -path $uncPathCur -Recurse -Force
                     
                     $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                     # On initialise l'utilisateur comme ayant été renommé.
                     setUserRenamed -sciper $renameInfos.sciper
                     
                     $counters.inc('nbRename')

                  }
                  else # L'ancien dossier n'est pas vide
                  {
                     $logHistory.addLineAndDisplay("-> Old folder not empty... ")

                     # Si le nouveau dossier est vide, 
                     if(isFolderEmpty -folderPath $uncPathNew)
                     {
                        # Ancien avec donnée  +  nouveau vide  => suppression nouveau vide + renommage ancien
                        $logHistory.addLineAndDisplay("-> Deleting new... ")
                        
                        # Suppression de "l'ancien" dossier
                        Remove-item -path $uncPathNew -Recurse -Force
                        
                        $logHistory.addLineAndDisplay("-> Renaming old... ")

                        try
                        {
                           # Tentative de renommage
                           Rename-Item -Path $uncPathCur -NewName $uncPathNew -Force

                           $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                           
                           # On initialise l'utilisateur comme ayant été renommé.
                           setUserRenamed -sciper $renameInfos.sciper
                           
                           $counters.inc('nbRename')
                        }
                        catch
                        {
                           # Ajout de l'erreur à la liste 
                           $notifications.usernameRenameErrors += ($uncPathCur+" to "+$uncPathNew)
                           $logHistory.addErrorAndDisplay("-> Error renaming folder")
                        }

                     }
                     else # Le nouveau dossier n'est pas vide
                     {
                        # enregistrement de l'information pour le renommage foireux
                        $notifications.bothFoldersData += ("Old: {0} - New: {1}" -f $uncPathCur, $uncPathNew)
                        
                        $counters.inc('nbRenameError')
                        
                     } # FIN SI le nouveau dossier n'est pas VIDE
                     
                  } # FIN Si l'ancien dossier n'est pas vide 
            
               } # FIN SI Le owner du nouveau dossier est correct
               
            } # FIN SI le nouveau dossier existe déjà 
         }
         else # Si le owner sur l'ancien dossier ne correspond pas
         {      
            $logHistory.addErrorAndDisplay("-> Incorrect owner ($curFolderOwner)! ")
            
            $notifications.oldFolderIncorrectOwner += ("{0} : Is 'INTRANET\{1}' and should be 'INTRANET\{2}' or 'INTRANET\{3}'" -f $uncPathCur, $curFolderOwner, $renameInfos.oldUsername, $renameInfos.newUsername)
            
            $counters.inc('nbRenameError')
         
         } # FIN SI l'UID sur le dossier ne correspond pas
         
      }      
      else # L'ancien dossier n'existe plus
      {      
         $logHistory.addLineAndDisplay("-> Old folder doesn't exists... ")

         $noOldFolder = $true
         
         # Si le nouveau dossier existe 
         if(Test-Path $uncPathNew -pathtype container) 
         {
            
            $logHistory.addLineAndDisplay("-> New folder exists...")
            
            # Récupération de l'UID du nouveau dossier 
            $domain, $newFolderOwner = ((Get-Acl $uncPathNew).owner).Split('\')
            
            # Si le Owner sur le nouveau dossier est OK
            if( ($newFolderOwner -eq $renameInfos.newUsername) -or ($newFolderOwner -eq $renameInfos.oldUsername))
            {       

               $logHistory.addLineAndDisplay("-> Owner OK... setting as renamed... ")

               # On initialise le dossier comme renommé
               setUserRenamed -sciper $renameInfos.sciper
                  
               $counters.inc('nbAlreadyRenamed')
            }
            else # Le owner sur le nouveau dossier est INCORRECT 
            {
               $logHistory.addErrorAndDisplay("Incorrect owner")
               
               $notifications.newFolderIncorrectOwner += ("{0}: Is INTRANET\{1} and should be INTRANET\{2} or INTRANET\{3}" -f `
                                                             $uncPathNew, $newFolderOwner, $renameInfos.newUsername, $renameInfos.oldUsername)
               
               $counters.inc('nbRenameError')
               
            } # FIN SI UID sur nouveau dossier incorrect 
            
         }         
         else # Le nouveau dossier n'existe pas  
         {
            # A ce stade, ni l'ancien ni le nouveau dossier n'existent... 

            $logHistory.addLineAndDisplay("-> New folder doesn't exists!")

            $noNewFolder = $true
            
            $notifications.bothFoldersNotFound += ("{0}<br>{1}" -f $uncPathCur, $uncPathNew)
            
            $counters.inc('nbRenameError')
         
         } # FIN Si le nouveau dossier n'existe pas 
         
      } # FIN SI l'ancien dossier n'existe plus      
      
      # ---------------- QUOTAS ---------------
      
      # Génération du nom actuel du user avec le domaine devant 
      $curUserFullName = ([string]::Concat("INTRANET\",$renameInfos.oldUsername))
      # Génération du nouveau nom du user
      $newUserFullName = ([string]::Concat("INTRANET\",$renameInfos.newUsername))
      
      # Récupération des infos de quota pour l'ancien nom
      $logHistory.addLineAndDisplay(("-> Getting quota rule for user {0}" -f $curUserFullName))
      $volume = $netapp.getVolumeByName($renameInfos.volumeName)
      $quotaRule = $netapp.getUserQuotaRule($volume, $curUserFullName)
      
      # Si on a une règle de quota, on la supprime
      if($null -ne $quotaRule)
      {
         $netapp.deleteUserQuotaRule($volume, $quotaRule)
         $hardMB =  $quotaRule.space.hard_limit / 1024 / 1024
         $logHistory.addLineAndDisplay(("-> Quota rule found. Creating rule for new username ({0}) with {1} MB..." -f $newUserFullName, $hardMB))
         # Ajout de la nouvelle entrée pour l'utilisateur avec son nouveau username
         $netapp.addUserQuotaRule($volume, $newUserFullName, $hardMB)
      }
      else
      {
         $logHistory.addLineAndDisplay("-> No quota rule found")
      }
      
      # Si aucun des dossiers n'existe
      if($noNewFolder -and $noOldFolder)
      {
         $logHistory.addLineAndDisplay("-> None of the folders exists, just setting user as renamed")
         # On initialise le dossier comme renommé car il se peut qu'il y ait eu un problème par le passé qui a fait que le renommage des dossiers 
         # n'ai pas bien fonctionné et donc entre temps le dossier utilisateur a été effacé...
         setUserRenamed -sciper $renameInfos.sciper
      }
      
   }# FIN BOUCLE de parcours des éléments à renommer

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


