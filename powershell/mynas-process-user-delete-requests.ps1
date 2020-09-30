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
   $logHistory = [LogHistory]::new('mynas-process-user-delete', (Join-Path $PSScriptRoot "logs"), 30)

   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MYNAS_MAIL_TEMPLATE_FOLDER, $global:MYNAS_MAIL_SUBJECT_PREFIX, @{})
   
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
      #$connectHandle
      $logHistory.addLineAndDisplay("Connected")
   }
   catch
   {
      Throw "Error connecting to "+$global:CLUSTER_COLL_IP+"!"
   }

   $logHistory.addLineAndDisplay("Getting infos... ")
   # Récupération de la liste des suppressions à effectuer
   $deleteList = getWebPageLines -url ($global:WEBSITE_URL_MYNAS+"ws/get-users-to-delete.php")


   if($deleteList -eq $false)
   {
      Throw "Error getting delete list"
   }

   $deleteList = $deleteList[-100..-1]


   # Recherche du nombre de suppression à effectuer 
   $nbToDelete = getNBElemInObject -inObject $deleteList

   $logHistory.addLineAndDisplay("$nbToDelete folder(s) to delete")

   # Si rien à faire,
   if($nbToDelete -eq 0)
   {  
      $logHistory.addLineAndDisplay("Nothing to do, exiting...")
      exit 0
   }


   # Tableau pour mettre la liste des vServers concernés
   $vServersQuotaToRebuild=@{}

   # Compteurs 
   $nbUsersDeleted=0

   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

   # Parcours des éléments à supprimer 
   foreach($deleteInfos in $deleteList)
   {
      # les infos contenues dans $deleteInfos ont la structure suivante :
      # <vServerName>,<username>,<sciper>,<fullDataPath>,<volumeName>
      
      # Extraction des infos renvoyées
      $serverName,$username,$userSciper,$fullDataPath,$volumeName = $deleteInfos.split(',')

      # Recherche de l'UNC où se trouvent les fichiers à rebuild 
      $directory = $nameGeneratorMyNAS.getUserUNCPath($serverName, $username)

      $logHistory.addLineAndDisplay(("[{0}/{1}] Deleting directory for user {2}... " -f ($nbUsersDeleted+1), $nbToDelete, $username), "black", "white")

      # Test de l'existance du dossier.
      if(!(Test-Path $directory -pathtype container)) 
      {
         $logHistory.addLineAndDisplay("User directory $directory already deleted")

         # On dit que le dossier est effacé sinon on va à nouveau le retrouver à la prochaine exécution du script
         setUserDeleted -userSciper $userSciper
      }
      else
      {
         try
         {
            
            # Utilisateurs pour déterminer que c'est le bon owner
            $allowedOwners = @(
               "INTRANET\{0}" -f $username
               "INTRANET\{0}" -f $userSciper # On teste aussi le sciper dans le cas où il y aurait eu un problème et que ça aurait trainé jusqu'à ce que l'utilisateur soit "désactivé" dans AD
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
               setUserDeleted -userSciper $userSciper

               # On passe au suivant
               Continue
            }

            $logHistory.addLineAndDisplay("Using fileacl.exe...")

            try
            {
               $logHistory.addLineAndDisplay("Deleting files...")
               # Pour s'affranchir des longs noms de fichiers
               $fullDataPathLong = "\\?\UNC{0}" -f $fullDataPath.substring(1)
               Remove-Item -Recurse -Force $fullDataPathLong -ErrorVariable processError -ErrorAction SilentlyContinue
            }
            catch
            {
               # Initialise la variable pour "simuler" une erreur qui aura probablement eu lieu durant le "grantAdminAccess" 
               # afin de forcer à effacer le dossier de la 2e manière
               $processError = $true
            }
            

            # Si on n'a pas pu effacer le dossier via la manière "classique"
            if($processError)
            {
               $logHistory.addLineAndDisplay("Deletion failed using fileacl.exe... trying with NetApp cmdlets!")

               # On détermine le chemin jusqu'au dossier à supprimer au format <volname>/path/to/dir
               $dirPathToRemove = "{0}{1}" -f $volumeName, (([Regex]::Match($fullDataPath, '\\files[0-9](.*)')).Groups[1].Value -replace "\\", "/")

               # Récupération du Vserver
               $onVServer = Get-NcVserver -Controller $connectHandle -Name $serverName

               # Pour essayer d'effacer depuis les commandes NetApp, plus lent mais peut fonctionner..
               removeDirectory -controller $connectHandle -onVServer $onVServer -dirPathToRemove $dirPathToRemove -nbDelTot $nbDeleteTot | Out-Null
            }
            

            # Suppression de l'entrée de quota 
            $logHistory.addLineAndDisplay("Removing quota entry... ")

            # Si l'entrée de quota existe, on la supprime. Dans le cas où l'entrée avait les valeurs de la règle de quota par défaut,
            # elle sera supprimée automatiquement après suppressio des données utilisateurs.
            if($null -ne (Get-NcQuota -Controller $connectHandle -Vserver $onVServer -Volume $volumeName -Target ("INTRANET\"+$username)))
            {
               Remove-NcQuota -Controller $connectHandle -VserverContext $onVServer -Volume $volumeName -Target ("INTRANET\"+$username) -Type user -Qtree ""
            }


            # On check aussi l'entrée de quota pour l'entrée INTRANET\sciper
            if($null -ne (Get-NcQuota -Controller $connectHandle -Vserver $onVServer -Volume $volumeName -Target ("INTRANET\"+$sciper)))
            {
               Remove-NcQuota -Controller $connectHandle -VserverContext $onVServer -Volume $volumeName -Target ("INTRANET\"+$sciper) -Type user -Qtree ""
            }

            $logHistory.addLineAndDisplay("User deleted")

            # On note l'utilisateur comme effacé
            setUserDeleted -userSciper $userSciper
            
            # Si on n'a pas encore traité le vServer courant, on l'ajoute à la liste de ceux pour lesquels il faudra rebuild le quota.
            if(!$vServersQuotaToRebuild.ContainsKey($serverName)) 
            {
               # Ajout des infos pour après 
               $vServersQuotaToRebuild.Add($serverName, $volumeName)
            }
         }
         catch
         {
            $logHistory.addErrorAndDisplay(("Error deleting user folder {0}" -f $fullDataPath))
         }

      } # FIN Si le dossier à effacer existe

      $nbUsersDeleted++

   }# FIN BOUCLE de parcours des éléments à renommer

   # S'il y a des vServer pour lesquels il faut rebuild le quota, 
   if($vServersQuotaToRebuild.Count -gt 0)
   {
      $logHistory.addLineAndDisplay( ("Rebuilding quota for {0} vServers... " -f $vServersQuotaToRebuild.count) )

      # Parcours des vServers
      foreach($serverName in ($vServersQuotaToRebuild.Keys | Sort-Object) )
      {
         # Recherche des infos du vServer
         $vserver = Get-NcVserver -Controller $connectHandle -Name $serverName
         
         $logHistory.addLineAndDisplay("Resizing quota on vServer $serverName")
         
         # Resize du volume pour appliquer la modification 
         resizeQuota -controller $connectHandle -onVServer $vserver -volumeName $vServersQuotaToRebuild.Get_Item($serverName) | Out-Null
         
         
      }# FIN BOUCLE de parcours des vServers
      
   }

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

