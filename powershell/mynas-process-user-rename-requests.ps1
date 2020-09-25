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

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# ------------------------------------------------------------------------
# ---------------------------- FONCTIONS ---------------------------------

<#
   BUT : Renomme un dossier utilisateur
   
   IN  : $controller    -> handle sur la connexion sur le contrôleur NetApp
   IN  : $onVserver     -> Handle sur le vServer concerné
   IN  : $curPath       -> Chemin actuel absolu jusqu'au dossier à renommer ("vol/<volName>/<pathToFolder>")
   IN  : $newPath       -> Nom du nouveau dossier. On doit donner le chemin complet également... ("vol/<volName>/<pathToFolder>")
   
   RET : 
   $true    -> Renommage OK
   Sinon, message d'erreur renvoyé.
#>
function renameFolder
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $curPath,
         [string] $newPath) 
         
   # Renommage du dossier + gestion des erreurs 
   $errorArray=@()
   Rename-NcFile -Controller $controller -VserverContext $vserver -Path $curPath -NewPath $newPath -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue | Out-Null
   # Si une erreur s'est produite, on retourne l'erreur
   if($errorArray.Count -gt 0)
   {
      return $errorArray[0].ToString()
   }   
   return $true
}

# ------------------------------------------------------------------------

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
   $res = getWebPageLines -url $url
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
   
   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

   # Chargement du module (si nécessaire)
   loadDataOnTapModule 
   
   checkEnvironment

   try 
   {
      $logHistory.addLineAndDisplay("Connecting... ")
      # Génération du mot de passe 
      $secPassword = ConvertTo-SecureString $configMyNAS.getConfigValue("nas", "password") -AsPlainText -Force
      # Création des credentials pour l'utilisateur
      $credentials = New-Object System.Management.Automation.PSCredential($configMyNAS.getConfigValue("nas", "user"), $secPassword)
      # Connexion au NetApp
      $connectHandle = Connect-NcController -Name $global:CLUSTER_COLL_IP -Credential $credentials -HTTPS
   }
   catch
   {
      Throw ("Error connecting to "+$global:CLUSTER_COLL_IP+"!")
   }

   $logHistory.addLineAndDisplay("Getting infos... ")
   # Récupération de la liste des renommages à effectuer
   $renameList = getWebPageLines -url ($global:WEBSITE_URL_MYNAS+"ws/get-users-to-rename.php?fs_mig_type=mig")

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
      # <cifsServerName>,<volName>,<pathToUserFolders>,<oldName>,<newName>,<Sciper>
      
      # Transformation en tableau puis mise dans des variables plus "parlantes"...
      $renameInfosArray    = $renameInfos.split(',')
      $vServerName         = $renameInfosArray[0]
      $volName             = $renameInfosArray[1]
      $pathToCurFolder     = ([string]::Concat("/data/",$renameInfosArray[2]))
      $pathToCurFolderFull = "$volName$pathToCurFolder"
      $pathToNewFolder     = ([string]::Concat("/data/",$renameInfosArray[3]))
      $pathToNewFolderFull = "$volName$pathToNewFolder"
      $curUsername         = $renameInfosArray[2]
      $newUsername         = $renameInfosArray[3]
      $userSciper          = $renameInfosArray[4]
      
      # Définition des UNC du dossier actuel et du nouveau pour les tests d'existence
      $uncPathCur = $nameGeneratorMyNAS.getUserUNCPath($vServerName, $curUsername)
      $uncPathNew = $nameGeneratorMyNAS.getUserUNCPath($vServerName, $newUsername)

      # Récupération du serveur CIFS (ou du vServer plutôt)
      $vserver = Get-NcVserver -Controller $connectHandle -Name $vServerName
         
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
            $logOwnerNotFound += $pathToCurFolder
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
               $result = renameFolder -controller $connectHandle -onVServer $vserver -curPath $pathToCurFolderFull -newPath $pathToNewFolderFull
               if($result -ne $true)
               {
                  # Ajout de l'erreur à la liste 
                  $logUsernameRenameErrors += ($curUsername+": "+$result)
                  $logHistory.addErrorAndDisplay("-> Error renaming folder")
                  
                  $counters.inc('nbRenameError')
               }
               else
               {
                  $logRenamedFolders += ($curUsername+" => "+$newUsername)
                  
                  $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                  
                  # On initialise l'utilisateur comme ayant été renommé.
                  setUserRenamed -userSciper $userSciper
                  
                  $counters.inc('nbRename')
               }# FIN Si pas d'erreur lors du renommage de dossier 
            }
            else # Le nouveau dossier existe déjà
            {
               $logHistory.addLineAndDisplay("-> New folder already exists... ")

               # Récupération de l'UID du nouveau dossier 
               $domain, $newFolderOwner = ((Get-Acl $uncPathNew).owner).Split('\')
               
               # Si le owner du nouveau dossier est incorrect (qu'il ne correspond pas à l'utilisateur)
               if( ($newFolderOwner -ne $newUsername) -and ($newFolderOwner -ne $curUsername))
               {
                  $logHistory.addErrorAndDisplay("-> New folder owner incorrect!")
                  
                  # Ajout des infos dans le "log" 
                  $logNewFolderExists += "Incorrect Owner on new folder: $curUsername ($curFolderOwner) => $newUsername ($newFolderOwner)"

                  $counters.inc('nbRenameError')
               }
               else # Le owner du nouveau dossier est correct
               {
                  $logHistory.addLineAndDisplay("-> Owner OK... ")
                  # Si l'ancien dossier est vide
                  if((isFolderEmpty -controller $connectHandle -onVServer $vserver -folderPath $pathToCurFolderFull) -eq $true)
                  {
                     $logHistory.addLineAndDisplay("-> Old empty, deleting... ")
                     
                     # Suppression de "l'ancien" dossier
                     $nbDel = removeDirectory -controller $connectHandle -onVServer $vserver -dirPathToRemove $pathToCurFolderFull
                     
                     $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                     # On initialise l'utilisateur comme ayant été renommé.
                     setUserRenamed -userSciper $userSciper
                     
                     $counters.inc('nbRename')

                  }
                  else # L'ancien dossier n'est pas vide
                  {
                     $logHistory.addLineAndDisplay("-> Old folder not empty... ")

                     # Si le nouveau dossier est vide, 
                     if((isFolderEmpty -controller $connectHandle -onVServer $vserver -folderPath $pathToNewFolderFull) -eq $true)
                     {
                        # Ancien avec donnée  +  nouveau vide  => suppression nouveau vide + renommage ancien
                        $logHistory.addLineAndDisplay("-> Deleting new... ")
                        
                        $nbDel = removeDirectory -controller $connectHandle -onVServer $vserver -dirPathToRemove $pathToNewFolderFull
                        
                        $logHistory.addLineAndDisplay("-> Renaming old... ")

                        # Renommage de l'ancien dossier + gestion des erreurs 
                        $result = renameFolder -controller $connectHandle -onVServer $vserver -curPath $pathToCurFolderFull -newPath $pathToNewFolderFull
                        if($result -ne $true)
                        {
                           # Ajout de l'erreur à la liste 
                           $logUsernameRenameErrors += ($curUsername+": "+$result)
                           $logHistory.addErrorAndDisplay("-> Error renaming folder")
                        }
                        else
                        {
                           $logRenamedFolders += ($curUsername+" => "+$newUsername+ "  (New existed but empty so was deleted)")
                           
                           $logHistory.addLineAndDisplay("-> Setting as renamed... ")
                           
                           # On initialise l'utilisateur comme ayant été renommé.
                           setUserRenamed -userSciper $userSciper
                           
                           $counters.inc('nbRename')
                        }# FIN Si pas d'erreur lors du renommage de dossier 
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
            
            $logOldFolderIncorrectOwner += "Owner incorrect on $pathToCurFolder : Is '$curFolderOwner' and should be '$curUsername' or '$curUsername'"
            
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
            
            $logNothingFound += "Nothing found for folders: '$pathToCurFolder' and '$pathToNewFolder'"
            
            $counters.inc('nbRenameError')
         
         } # FIN Si le nouveau dossier n'existe pas 
         
      } # FIN SI l'ancien dossier n'existe plus      
      
      # ---------------- QUOTAS ---------------
      
      # Génération du nom actuel du user avec le domaine devant 
      $curUserFullName = ([string]::Concat("INTRANET\",$curUsername))
      # Génération du nouveau nom du user
      $newUserFullName = ([string]::Concat("INTRANET\",$newUsername))
      
      # Récupération des infos de quota pour l'ancien nom
      $quotaInfos = Get-NcQuota -Controller $connectHandle -Volume $volName -Vserver $vserver -Target $curUserFullName
      
      $errorArray=@()
      # Suppression de l'entrée de quota avec l'ancien nom
      Remove-NcQuota -Controller $connectHandle -Volume $volName -VserverContext $vserver -Target $curUserFullName -Qtree "" -Type user -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue
      
      # Transformation des quotas. On les a en "KB" avec le get-NcQuota mais il faut les passer en Bytes pour le Set-NcQuota... ceci depuis que 
      # les PowerShell Toolkit version 4.4 ont été installés. Avant, fallait simplement spécifier l'unité...
      $softQuota = ([int]$quotaInfos.SoftDiskLimit) *1024
      $hardQuota = ([int]$quotaInfos.DiskLimit) *1024
      
      # Si pas d'erreur 
      if($errorArray.Count -eq 0)
      {
      
         # Resize du volume pour appliquer la modification 
         $res = resizeQuota -controller $connectHandle -onVServer $vserver -volumeName $volName
         
         # Si ça a foiré
         if($res.JobState -eq "failure")
         {
            # Envoi d'un mail aux admins 
            sendMailToAdmins -mailMessage ([string]::Concat("Error doing 'quota resize' on volume $volName<br><b>Error:</b><br>", $res.JobCompletion)) `
                              -mailSubject "MyNAS Service: Error processing username rename requests"

            # On remet en place la règle qu'on a voulu supprimer
            
            try
            {
               # On essaie de chercher l'utilisateur dans AD
               $val = Get-ADUser -Identity $curUserFullName -Properties * 

               Set-NcQuota -Controller $connectHandle -VserverContext $vserver -Volume $volName `
                        -Target $curUserFullName -Type user -Qtree "" `
                        -DiskLimit $hardQuota `
                        -SoftDiskLimit $softQuota
            }
            catch
            {
               $logHistory.addErrorAndDisplay(("-> No AD user found for '{0}'"  -f $curUserFullName))
            }
                              
            # On sort
            exit 1
         }
      }# FIN Si pas d'erreur dans la suppression de l'entrée de quota 
      
      try
      {
         # On essaie de chercher l'utilisateur dans AD
         $val = Get-ADUser -Identity $newUserFullName -Properties * 

         # Remise de l'entrée de quota mais avec le nouveau nom
         Set-NcQuota -Controller $connectHandle -VserverContext $vserver -Volume $volName `
         -Target $newUserFullName -Type user -Qtree "" `
         -DiskLimit $hardQuota `
         -SoftDiskLimit $softQuota
      }
      catch
      {
            $logHistory.addErrorAndDisplay(("-> No AD user found for '{0}'"  -f $newUserFullName))
      }
      
      
      
      # Resize du volume pour appliquer la modification 
      $res = resizeQuota -controller $connectHandle -onVServer $vserver -volumeName $volName
      
      
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


