<#
   BUT : Traite les actions demandées par le HelpDesk via le portail MyNAS.epfl.ch
   
   AUTEUR : Lucien Chaboudez
   DATE   : 17.08.2018

   PARAMETRES : Aucun
   
   PREREQUIS : 1. Installer la version appropriée (x86 ou x64) de Quest ActiveRolesManagement 
               2. Autoriser les scripts powershell à s'exécuter sans signature
                  Set-ExecutionPolicy Unrestricted
               3. Le script (ou la tâche planifiée qui le lance) doit être exécuté via un compte AD qui est :
                  - dans le groupe BUILTIN\Administrators de la machine courante
                  - dans le groupe "Backup Operators" des vServers MyNAS
               4. S'assurer que l'exécutable "fileacl.exe" soit dans le même dossier que le script. 
                  Celui-ci peut être trouvé ici : http://www.gbordier.com/gbtools/fileacl.asp
                  
   
   MODIFS :
#>

# Inclusion des constantes
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))

# Inclusion des fonctions génériques depuis un autre fichier
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))

# Nécessaire pour reconstruire les droits des dossiers 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "MyNASACLUtils.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")

# --------------------- CONSTANTES --------------------------


# Liste des actions supportées 
$ACTION_REBUILD_USER_RIGHTS = "rebuild-user-rights"
$supportedActions = @($ACTION_REBUILD_USER_RIGHTS)


# Statuts possibles pour les actions
# A reprendre depuis 'define.inc.php' sur mynas.epfl.ch
$ACTION_STATUS_RUNNING = "running"
$ACTION_STATUS_DONE    = "done"


# Décommenter cette ligne pour les tests 
# $global:WEBSITE_URL_MYNAS="https://ditex-web.epfl.ch/mynas-dev/"

# ------------------------------------------------------------------------
# ---------------------------- FONCTIONS ---------------------------------


# ------------------------------------------------------------------------

<#
   BUT : Change l'état d'une action
         
   IN  : $actionId   -> ID de l'action
   IN  : $status     -> Statut de l'action 
                        'running' 
                        'done'
   IN  : $error      -> Eventuel message d'erreur
#>
function setActionStatus 
{
   param($actionId, $status, $errorMsg)
   
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-hd-action-status.php?action_id="+$actionId+"&status="+$status
   
   if($errorMsg -ne "")
   {
      $url += "&error="+$errorMsg
   }
   
   #Write-Host "setUserDeleted: $url"
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
   $logHistory = [LogHistory]::new('mynas-process-hd-actions', (Join-Path $PSScriptRoot "logs"), 30)

   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)
   
   # Création de l'objet pour gérer les ACLs
   $myNASAclUtils = [MyNASACLUtils]::new($global:LOGS_FOLDER, $global:BINARY_FOLDER)

   $logHistory.addLineAndDisplay("Getting infos... ")

   # Récupération de la liste des actions à effectuer
   $actionList = getWebPageLines -url ($global:WEBSITE_URL_MYNAS+"ws/get-hd-actions.php") 

   # Contrôle d'erreurs
   if($actionList -eq $false)
   {
      Throw "Error getting action list"
   }

   # Transformation en tableau
   $actionList = $actionList | ConvertFrom-Json 

   $logHistory.addLineAndDisplay(("{0} action(s) to process" -f $actionList.Count))

   # Si rien à faire,
   if($actionList.count -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }


   # Compteurs 
   $nbProcessed=0

   # Parcours des actions à effectuer
   foreach($actionInfos in $actionList)
   {
      if($supportedActions -notcontains $actionInfos.action)
      {
         $logHistory.addLineAndDisplay(("Unsupported requested action : {0}" -f $actionInfos.action))
         
         continue
      }
      
      # On note comme quoi on démarre l'action
      setActionStatus -actionId $actionInfos.action_id -status $ACTION_STATUS_RUNNING
      
      if($actionInfos.action -eq $ACTION_REBUILD_USER_RIGHTS)
      {
      
         # Création du chemin jusqu'au dossier
         $filesNo = $actionInfos.action_data.sciper.Substring($actionInfos.action_data.sciper.length -1)
         $server = "files{0}" -f $filesNo
         $pathToFolder = getUserUNCPath -server $server -username $actionInfos.action_data.username

         $logHistory.addLineAndDisplay( ("Rebuilding rights for user {0} ({1})" -f $actionInfos.action_data.username, $server) )

         # Message d'erreur vide pour la suite.
         $errorMessage = ""

         # Si le dossier n'existe pas 
         if(!(Test-Path -Path $pathToFolder))
         {
            $errorMessage = "Folder for user '{0}' ({1}) doesn't exists" -f $actionInfos.action_data.username, $server
         
         }
         else  # Le dossier existe donc il peut être reconstruit 
         {
            
            try
            {
            
               # Reconstruction des droits 
               $myNASAclUtils.rebuildUserRights($server, $actionInfos.action_data.username,  $actionInfos.action_data.username)
               $logHistory.addLineAndDisplay("Rebuild done!")
            }
            catch # Si erreur
            {
               $errorMessage = $_.Exception.Message
            }
            
         }
         
         if($errorMessage -ne "")
         {
            $logHistory.addLineAndDisplay($errorMessage)
         }
         
         # Action terminée 
         setActionStatus -actionId $actionInfos.action_id -status $ACTION_STATUS_DONE -errorMsg $errorMessage
      }
      
      $nbProcessed += 1
      

   }# FIN BOUCLE de parcours des éléments à renommer

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
