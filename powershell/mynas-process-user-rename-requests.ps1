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
         
   IN  : $userSciper    -> Sciper de l'utilisateur qu'on veut initialiser comme renommé.
#>
function setUserRenamed 
{
   param($userSciper)
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-user-renamed.php?sciper="+$userSciper
   
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
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "MyNAS", "")
   
   # Création de l'objet pour se connecter aux clusters NetApp
   $netapp = [NetAppAPI]::new($configMyNAS.getConfigValue("nas", "serverList"), `
                              $configMyNAS.getConfigValue("nas", "user"), `
                              $configMyNAS.getConfigValue("nas", "password"))

   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()
   
   checkEnvironment


   $logHistory.addLineAndDisplay("Getting infos... ")
   # Récupération de la liste des renommages à effectuer
   $renameList = getWebPageLines -url ($global:WEBSITE_URL_MYNAS+"ws/get-users-to-rename.php?fs_mig_type=mig")

   $renameList = @("files0,dit_files0_indiv,chaboude,krejci,168105")

   if($renameList -eq $false)
   {
      Throw "Error getting rename list!"
   }

   # Recherche du nombre de renommages à effectuer 
   $nbRenames=getNBElemInObject -inObject $renameList

   $logHistory.addLineAndDisplay("$nbRenames folder(s) to rename")

   # Si rien à faire,
   if($nbRenames -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }


   # Tableau pour mettre la liste des 'username' qui ont foiré pour le renommage 
   $logUsernameRenameErrors=@()
   $logNewFolderExists=@()
   $logOldFolderIncorrectOwner=@()
   $logNewFolderIncorrectOwner=@()
   $logAlreadyRenamed=@()
   $logNothingFound=@()
   $logOwnerNotFound=@()

   # Pour la liste des dossiers renommés
   $logRenamedFolders=@()

   # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
   $counters.add('nbRename', '# User renamed')
   $counters.add('nbRenameError', '# User rename errors')

   # Parcours des éléments à renommer 
   foreach($renameInfos in $renameList)
   {
      # les infos contenues dans $renameInfos ont la structure suivante :
      # <cifsServerName>,<volName>,<oldName>,<newName>,<Sciper>
      
      # Transformation en tableau puis mise dans des variables plus "parlantes"...
      $vServerName, $volName, $curUsername, $newUsername, $userSciper = $renameInfos.split(',')
      
      # Définition des UNC du dossier actuel et du nouveau pour les tests d'existence
      $uncPathCur = $nameGeneratorMyNAS.getUserUNCPath($vServerName, $curUsername)
      $uncPathNew = $nameGeneratorMyNAS.getUserUNCPath($vServerName, $newUsername)
         
      $logHistory.addLineAndDisplay("Rename: $curUsername => $newUsername")
      
      # Si l'ancien dossier existe,
      if(Test-Path $uncPathCur -pathtype container) 
      {
         $logHistory.addLineAndDisplay(" -> Old folder exists... ")
      
         # Récupération du owner de l'ancien dossier       
         $domain, $curFolderOwner = ((Get-Acl $uncPathCur).owner).Split('\')
         
         # Si pas de owner trouvé 
         if($null -eq $curFolderOwner)
         {
            $logOwnerNotFound += $uncPathCur
         }      
         #Si le owner correspond, 
         elseif( ($curFolderOwner -eq $newUsername) -or ($curFolderOwner -eq $curUsername))
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

                  $logRenamedFolders += ($curUsername+" => "+$newUsername)
                  
                  $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                  
                  # On initialise l'utilisateur comme ayant été renommé.
                  setUserRenamed -userSciper $userSciper
                  
                  $counters.inc('nbRename')
               }
               catch
               {
                  # Ajout de l'erreur à la liste 
                  $logUsernameRenameErrors += ($curUsername+": "+$result)
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
               if( ($newFolderOwner -ne $newUsername) -and ($newFolderOwner -ne $curUsername))
               {no
                  $logHistory.addErrorAndDisplay("-> New folder owner incorrect!")
                  
                  # Ajout des infos dans le "log" 
                  $logNewFolderExists += "Incorrect Owner on new folder: $curUsername ($curFolderOwner) => $newUsername ($newFolderOwner)"

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
                     setUserRenamed -userSciper $userSciper
                     
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

                           $logRenamedFolders += ($curUsername+" => "+$newUsername+ "  (New existed but empty so was deleted)")
                           
                           $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                           
                           # On initialise l'utilisateur comme ayant été renommé.
                           setUserRenamed -userSciper $userSciper
                           
                           $counters.inc('nbRename')
                        }
                        catch
                        {
                           # Ajout de l'erreur à la liste 
                           $logUsernameRenameErrors += ($curUsername+": "+$result)
                           $logHistory.addErrorAndDisplay("-> Error renaming folder")
                        }

                     }
                     else # Le nouveau dossier n'est pas vide
                     {
                        # enregistrement de l'information pour le renommage foireux
                        $logNewFolderExists += "New folder exists and OLD and NEW have data in it! Contact owner: $curUsername ($curFolderOwner) => $newUsername ($newFolderOwner)"
                        
                        $counters.inc('nbRenameError')
                        
                     } # FIN SI le nouveau dossier n'est pas VIDE
                     
                  } # FIN Si l'ancien dossier n'est pas vide 
            
               } # FIN SI Le owner du nouveau dossier est correct
               
            } # FIN SI le nouveau dossier existe déjà 
         }
         else # Si le owner sur l'ancien dossier ne correspond pas
         {      
            $logHistory.addErrorAndDisplay("-> Incorrect owner ($curFolderOwner)! ")
            
            $logOldFolderIncorrectOwner += "Owner incorrect on $uncPathCur : Is '$curFolderOwner' and should be '$curUsername' or '$curUsername'"
            
            $counters.inc('nbRenameError')
         
         } # FIN SI l'UID sur le dossier ne correspond pas
         
      }      
      else # L'ancien dossier n'existe plus
      {      
         $logHistory.addLineAndDisplay("-> Old folder doesn't exists... ")
         
      # Si le nouveau dossier existe 
      if(Test-Path $uncPathNew -pathtype container) 
      {
            
            $logHistory.addLineAndDisplay("-> New folder exists...")
            
            # Récupération de l'UID du nouveau dossier 
            $domain, $newFolderOwner = ((Get-Acl $uncPathNew).owner).Split('\')
            
            # Si le Owner sur le nouveau dossier est OK
            if( ($newFolderOwner -eq $newUsername) -or ($newFolderOwner -eq $curUsername))
            {       

               $logHistory.addLineAndDisplay("-> Owner OK... setting as renamed... ")
               
               $logAlreadyRenamed += "$curUsername ($curFolderOwner) => $newUsername ($newFolderOwner)"

               # On initialise le dossier comme renommé
               setUserRenamed -userSciper $userSciper
                  
               $counters.inc('nbRename')
            }
            else # Le owner sur le nouveau dossier est INCORRECT 
            {
               $logHistory.addErrorAndDisplay("Incorrect owner")
               
               $logNewFolderIncorrectOwner += "Old folder not exists and incorrect owner on new folder: Is '$newFolderOwner' and should be '$curUsername' or '$curUsername'"

               $counters.inc('nbRenameError')
               
            } # FIN SI UID sur nouveau dossier incorrect 
            
         }         
         else # Le nouveau dossier n'existe pas  
         {
            # A ce stade, ni l'ancien ni le nouveau dossier n'existent... 

            $logHistory.addLineAndDisplay("-> New folder doesn't exists!")
            
            $logNothingFound += "Nothing found for folders: '$uncPathCur' and '$uncPathNew'"
            
            $counters.inc('nbRenameError')
         
         } # FIN Si le nouveau dossier n'existe pas 
         
      } # FIN SI l'ancien dossier n'existe plus      
      
      # ---------------- QUOTAS ---------------
      
      # Génération du nom actuel du user avec le domaine devant 
      $curUserFullName = ([string]::Concat("INTRANET\",$curUsername))
      # Génération du nouveau nom du user
      $newUserFullName = ([string]::Concat("INTRANET\",$newUsername))
      
      # Récupération des infos de quota pour l'ancien nom
      $logHistory.addLineAndDisplay(("-> Getting quota rule for user {0}" -f $curUserFullName))
      $volume = $netapp.getVolumeByName($volName)
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
      
      
   }# FIN BOUCLE de parcours des éléments à renommer

   $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

   # Si des dossiers ont été renommés
   if($logRenamedFolders.count -gt 0)
   {
      
      
      $mailMessage = stringArrayToMultiLineString -strArray $logRenamedFolders -lineSeparator "<br>"
      
      # S'il y avait des dossiers déjà renommés, 
      if($logAlreadyRenamed.count -gt 0)
      {
         #$mailMessage += "<br>-------------------------------------------------"
         $mailMessage += "<br><b>Some folders were already renamed<b><br>"
         #$mailMessage += "-------------------------------------------------"
         
         $mailMessage += stringArrayToMultiLineString -strArray $logAlreadyRenamed -lineSeparator "<br>"
         
      }# FIN SI il y avait des dossiers déjà renommés
      
      # Envoi du mail 
      sendMailToAdmins -mailSubject "MyNAS service: User folder have been renamed" -mailMessage $mailMessage
      
   }# FIN SI des dossiers ont été renommés 

   # Pour regrouper toutes les erreurs 
   $logAllErrors = @()

   # Si on a trouvé des utilisateurs avec des dossier existants
   if($logNewFolderExists.Count -gt 0)
   {

      $logAllErrors += "------------------------------------------------------------------------------------------------------"
      $logAllErrors += "<b>For some users, the folder for 'new' username already exists. Here are the errors:</b>"
      $logAllErrors += "------------------------------------------------------------------------------------------------------"
      $logAllErrors += $logNewFolderExists
      $logAllErrors += ""
   }

   # Si on a trouvé  des dossiers OLD avec des erreurs de owner
   if($logOldFolderIncorrectOwner.Count -gt 0)
   {

      $logAllErrors += "--------------------------------------------------------------"
      $logAllErrors += "<b>Some 'old' folders have incorrect owner:</b>"
      $logAllErrors += "--------------------------------------------------------------"
      $logAllErrors += $logOldFolderIncorrectOwner
      $logAllErrors += ""
   }

   # Si on a trouvé  des dossiers NEW avec des erreurs de owner
   if($logNewFolderIncorrectOwner.Count -gt 0)
   {

      $logAllErrors += "--------------------------------------------------------------"
      $logAllErrors += "<b>Some 'new' folders have incorrect owner:</b>"
      $logAllErrors += "--------------------------------------------------------------"
      $logAllErrors += $logNewFolderIncorrectOwner
      $logAllErrors += ""
   }


   # Si des erreurs ont été rencontrées 
   if($logAllErrors.count -gt 0)
   {
      $logHistory.addLineAndDisplay("Errors encountered... sending mail to admins... ")
      # Création d'un mail
      $mailMessage="The following errors have been found while renaming user folders. Please correct them manually.<br><br>"
      
      $mailMessage += stringArrayToMultiLineString -strArray $logAllErrors -lineSeparator "<br>"
      
      # Envoi du mail aux administrateurs 
      sendMailToAdmins -mailSubject "MyNAS service: ERRORS while renaming user folders" -mailMessage $mailMessage 
      
   }

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


