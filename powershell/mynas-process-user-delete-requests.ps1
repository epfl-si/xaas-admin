<#
   BUT : Traite les demandes de suppression de dossiers utilisateurs
   
   AUTEUR : Lucien Chaboudez
   DATE   : 19.10.2016

   PARAMETRES : Aucun
   
   PREREQUIS : 
	1. Module ActiveDirectory pour PowerShell.
		- Windows 10 - Dispo dans RSAT - https://www.microsoft.com/en-us/download/details.aspx?id=45520
		- Windows Server 2003, 2013, 2016:
			+ Solution 1 - Install automatique
			>> Add-WindowsFeature RSAT-AD-PowerShell

			+ Solution 2 - Install manuelle
			1. Start "Server Manager"
			2. Click "Manage > Add Roles and Features"
			3. Click "Next" until you reach "Features".
			4. Enable "Active Directory module for Windows PowerShell" in
				"Remote Server Administration Tools > Role Administration Tools > AD DS and AD LDS Tools".
   2. Autoriser les scripts powershell à s'exécuter sans signature
      Set-ExecutionPolicy Unrestricted
   3. Le script (ou la tâche planifiée qui le lance) doit être exécuté via un compte AD qui est :
      - dans le groupe BUILTIN\Administrators de la machine courante
      - dans le groupe "Backup Operators" des vServers MyNAS
      Dans le cas courant, un utilisateur "INTRANET\mynas-delete-user" a été créé dans AD
   
   MODIFS :
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


# ------------------------------------------------------------------------

<#
   BUT : Initialise un utilisateur comme supprimé en appelant le WebService 
         adéquat.
         
   IN  : $userSciper    -> Sciper de l'utilisateur qu'on veut initialiser comme renommé.
#>
function setUserDeleted 
{
   param($userSciper)
   
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-user-deleted.php?sciper="+$userSciper
   
   #Write-Host "setUserDeleted: $url"
   # Appel de l'URL pour initialiser l'utilisateur comme renommé 
   getWebPageLines -url $url | Out-Null
}



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

   # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
   $logHistory = [LogHistory]::new(@('mynas', 'process-user-delete'), $global:LOGS_FOLDER, 120)

   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MYNAS_MAIL_TEMPLATE_FOLDER, $global:MYNAS_MAIL_SUBJECT_PREFIX, @{})
   
   # Création de l'objet pour se connecter aux clusters NetApp
   $netapp = [NetAppAPI]::new($configMyNAS.getConfigValue(@("nas", "serverList")),
                              $configMyNAS.getConfigValue(@("nas", "user")),
                              $configMyNAS.getConfigValue(@("nas", "password")))

   # Chargement du module (si nécessaire)
   loadDataOnTapModule 

   # Génération du mot de passe pour plus tard
   $secPassword = ConvertTo-SecureString $configMyNAS.getConfigValue(@("nas", "password")) -AsPlainText -Force
   # Création des credentials pour l'utilisateur
   $credentials = New-Object System.Management.Automation.PSCredential($configMyNAS.getConfigValue(@("nas", "user")), $secPassword)


   $logHistory.addLineAndDisplay("Getting infos... ")
   # Récupération de la liste des suppressions à effectuer
   $deleteList = downloadPage -url ($global:WEBSITE_URL_MYNAS+"ws/v2/get-users-to-delete.php") | ConvertFrom-JSON

   if($deleteList -eq $false)
   {
      Throw "Error getting delete list"
   }

   $logHistory.addLineAndDisplay(("{0} folder(s) to delete" -f $deleteList.count))

   # Si rien à faire,
   if($deleteList.count -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }

   # Compteurs 
   $nbUsersDeleted=0

   # La liste des volumes/vServer, pour éviter de faire trop de requêtes du côté du NetApp
   $volumeList = @{}
   $vServerList = @{}
   $netAppHostConnectionList = @()

   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

   # Parcours des éléments à supprimer 
   foreach($deleteInfos in $deleteList)
   {

      # Recherche de l'UNC où se trouvent les fichiers à rebuild 
      $directory = $nameGeneratorMyNAS.getUserUNCPath($deleteInfos.vserver, $deleteInfos.username)

      $logHistory.addLineAndDisplay(("[{0}/{1}] Deleting directory for user {2}... " -f ($nbUsersDeleted+1), $deleteList.count, $deleteInfos.username), "black", "white")

      # Test de l'existance du dossier.
      if(!(Test-Path $directory -pathtype container)) 
      {
         $logHistory.addLineAndDisplay("User directory $directory already deleted")

         # On dit que le dossier est effacé sinon on va à nouveau le retrouver à la prochaine exécution du script
         setUserDeleted -userSciper $deleteInfos.sciper
      }
      else # Si le dossier existe
      {
         try
         {
            
            # Utilisateurs pour déterminer que c'est le bon owner
            $allowedOwners = @(
               "INTRANET\{0}" -f $deleteInfos.username
               "INTRANET\{0}" -f $deleteInfos.sciper # On teste aussi le sciper dans le cas où il y aurait eu un problème et que ça aurait trainé jusqu'à ce que l'utilisateur soit "désactivé" dans AD
            )
            $owner = (Get-Acl $directory).owner
            # Si ce n'est pas le bon owner sur le dossier
            if($allowedOwners -notcontains $owner)
            {
               <# Si on arrive là, c'est qu'un dossier avec le nom d'utilisateur existe sur le BON volume MAIS que les droits sont incorrects.
               On peut arriver dans ce cas de figure si le dossier utilisateur aurait dû être effacé du volume mais que pour une raison X cela
               n'a pas pu être fait. Et si par la suite le username a été recyclé ET qu'en plus on se retrouve sur le même serveur, il ne faut
               pas prendre le risque d'effacer des données incorrectes.
               #>
               $logHistory.addWarningAndDisplay( ("Wrong owner ({0}) on directory! Skipping" -f $owner))

               # On peut donc initialiser l'utilisateur comme "effacé" du côté MyNAS afin de ne pas retomber dans ce cas de figure la prochaine fois
               setUserDeleted -userSciper $deleteInfos.sciper

               # On passe au suivant
               Continue
            }

            $logHistory.addLineAndDisplay(("Deleting files ({0})..." -f $deleteInfos.fullDataPath))
            
            # On détermine le chemin jusqu'au dossier à supprimer au format <volname>/path/to/dir
            $dirPathToRemove = "{0}{1}" -f $deleteInfos.volumeName, (([Regex]::Match($deleteInfos.fullDataPath, '\\files[0-9](.*)')).Groups[1].Value -replace "\\", "/")

            # Si on n'a pas encore l'objet représentant le vServer, on le recherche
            if($vServerList.Keys -notcontains $deleteInfos.vserver)
            {
               # On regarde sur quel cluster NetApp se trouve le vServer

               $svm = $netapp.getSVMByName($deleteInfos.vserver)
               $netappHost = $netapp.getSVMClusterHost($svm)

               # Si on n'a pas encore de connexion sur le host netapp retourné
               if(($netAppHostConnectionList | Where-Object { $_.host -eq $netappHost}).count -eq 0)
               {
                  # Ajout des infos de connexion (et accessoirement connexion)
                  $netAppHostConnectionList += @{
                     host = $netappHost
                     connection = Connect-NcController -Name $netappHost -Credential $credentials -HTTPS
                  }
               }

               # Enregistrement des infos pour les récupérer juste après
               $vServerList.($deleteInfos.vserver) = @{
                  server = Get-NcVserver -Controller $connectHandle -Name $deleteInfos.vserver
                  clusterHost = ($netAppHostConnectionList | Where-Object { $_.host -eq $netappHost}).connection
               }
            }# Fin si on n'a pas encore l'objet représentant le vServer

            
            <# Pour essayer d'effacer depuis les commandes NetApp, plus lent mais ça fonctionne dans tous les cas. On peut en effet se retrouver avec des fichiers "lock"
               qui ne sont pas visibles avec les commandes Get-ChildItem de PowerShell et donc impossibles à effacer... et ils empêchent l'effacement des dossiers
               via Remove-Item vu que les dossiers ne sont pas considérés comme "vides".  #>
            removeDirectory -controller $vServerList.($deleteInfos.vserver).clusterHost -onVServer $vServerList.($deleteInfos.vserver).server -dirPathToRemove $dirPathToRemove
         
            # Suppression de l'entrée de quota 
            $logHistory.addLineAndDisplay("Removing quota rule... ")

            # Si on n'a pas encore l'objet représentant le volume, on le recherche
            if($volumeList.Keys -notcontains $deleteInfos.volumeName)
            {
               $volumeList.($deleteInfos.volumeName) = $netapp.getVolumeByName($deleteInfos.volumeName)
            }

            # Parcours des owners possibles
            ForEach($owner in $allowedOwners)
            {
               $logHistory.addLineAndDisplay(("> Looking for quota rule for username {0}..." -f $owner))
               # Recherche de la règle de quota avec le nom d'utilisateur courant
               $quotaRule = $netapp.getUserQuotaRule($volumeList.($deleteInfos.volumeName), $owner)
               # On ne trouvera de règle de quota que si l'utilisateur n'a pas le quota par défaut appliqué sur le volume (comme c'est le cas pour les étudiants)
               if($null -ne $quotaRule)
               {
                  $logHistory.addLineAndDisplay("> Rule exists, deleting it...")
                  $netapp.deleteUserQuotaRule($volumeList.($deleteInfos.volumeName), $quotaRule)
               }
            }# FIN BOUCLE de parcours des règles de quota

            $logHistory.addLineAndDisplay("User deleted")

            # On note l'utilisateur comme effacé
            setUserDeleted -userSciper $deleteInfos.sciper
            
         }
         catch
         {
            $logHistory.addErrorAndDisplay(("Error deleting user folder {0}" -f $deleteInfos.fullDataPath))
         }

      } # FIN Si le dossier à effacer existe

      $nbUsersDeleted++

   }# FIN BOUCLE de parcours des éléments à renommer


   $logHistory.addLineAndDisplay( ("{0} users have been deleted" -f $nbUsersDeleted))

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

