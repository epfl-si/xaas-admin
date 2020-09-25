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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))

# Inclusion des fonctions spécifiques à NetApp depuis un autre fichier
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))

# Inclusion des fonctions générique depuis un autre fichier
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "MyNASACLUtils.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")

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



# ------------------------------------------------------------------------
# ------------------------ PROGRAMME PRINCIPAL ---------------------------

# Chargement du module (si nécessaire)
loadDataOnTapModule 

checkEnvironment

try 
{
   Write-Host -NoNewline "Connecting... "
   # Génération du mot de passe 
   $secPassword = ConvertTo-SecureString $configMyNAS.getConfigValue("nas", "password") -AsPlainText -Force
   # Création des credentials pour l'utilisateur
   $credentials = New-Object System.Management.Automation.PSCredential($configMyNAS.getConfigValue("nas", "user"), $secPassword)
   # Connexion au NetApp
   $connectHandle = Connect-NcController -Name $global:CLUSTER_COLL_IP -Credential $credentials -HTTPS
   #$connectHandle
   Write-Host "OK"
}
catch
{
   Write-Error "Error connecting to "+$global:CLUSTER_COLL_IP+"!"
   exit 1
}

Write-Host "Getting infos... " -NoNewline
# Récupération de la liste des suppressions à effectuer
$deleteList = getWebPageLines -url ($global:WEBSITE_URL_MYNAS+"ws/get-users-to-delete.php")


if($deleteList -eq $false)
{
   Write-Host "Error getting delete list"
   Write-Host -ForegroundColor:Red "Error getting delete list!"
   exit 1
}

#$deleteList = $deleteList[-200..-1]


# Recherche du nombre de suppression à effectuer 
$nbToDelete = getNBElemInObject -inObject $deleteList

Write-Host "$nbToDelete folder(s) to delete"

# Si rien à faire,
if($nbToDelete -eq 0)
{  
   Write-Host "Nothing to do, exiting..."
   exit 0
}


# Tableau pour mettre la liste des vServers concernés
$vServersQuotaToRebuild=@{}

# Compteurs 
$nbDeleted=0

# Création de l'objet pour gérer les ACLs
$myNASAclUtils = [MyNASACLUtils]::new($global:LOGS_FOLDER, $global:BINARY_FOLDER)

# Parcours des éléments à supprimer 
foreach($deleteInfos in $deleteList)
{
   # les infos contenues dans $deleteInfos ont la structure suivante :
   # <vServerName>,<username>,<sciper>,<fullDataPath>,<volumeName>
   
   # Extraction des infos renvoyées
   $serverName,$username,$userSciper,$fullDataPath,$volumeName = $deleteInfos.split(',')

   # Recherche de l'UNC où se trouvent les fichiers à rebuild 
   $directory = getUserUNCPath -server $serverName -username $username

   Write-Host ("[{0}/{1}] Deleting directory for user {2}... " -f ($nbDeleted+1), $nbToDelete, $username) -BackgroundColor:White -ForegroundColor:Black

   # Test de l'existance du dossier.
   if(!(Test-Path $directory -pathtype container)) 
   {
      Write-Host "User directory $directory already deleted"

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
            Write-Warning ("Wrong owner ({0}) on directory! Skipping" -f $owner)

            # On peut donc initialiser l'utilisateur comme "effacé" du côté MyNAS afin de ne pas retomber dans ce cas de figure la prochaine fois
            setUserDeleted -userSciper $userSciper

            # On passe au suivant
            Continue
         }

         # Récupération du Vserver
         $onVServer = Get-NcVserver -Controller $connectHandle -Name $serverName

         Write-Host "Using fileacl.exe..."

         try
         {
            # Ajout des droits pour les admins
            $myNASAclUtils.grantAdminAccess($serverName, $username)
            Write-Host "Deleting files..."
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
            Write-Host "Deletion failed using fileacl.exe... trying with NetApp cmdlets!"

            # On détermine le chemin jusqu'au dossier à supprimer au format <volname>/path/to/dir
            $dirPathToRemove = "{0}{1}" -f $volumeName, ([Regex]::Match($fullDataPath, '\\files[0-9](.*)')).Groups[1].Value

            # Pour essayer d'effacer depuis les commandes NetApp, plus lent mais peut fonctionner..
            $nbDeleted = removeDirectory -controller $connectHandle -onVServer $onVServer -dirPathToRemove $dirPathToRemove -nbDelTot $nbDeleteTot
         }
         

         # Suppression de l'entrée de quota 
         Write-Host "Removing quota entry... "

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

         Write-Host "User deleted"

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
         Write-Error ("Error deleting user folder {0}" -f $fullDataPath)
      }

   } # FIN Si le dossier à effacer existe

   $nbDeleted++

}# FIN BOUCLE de parcours des éléments à renommer

# S'il y a des vServer pour lesquels il faut rebuild le quota, 
if($vServersQuotaToRebuild.Count -gt 0)
{
   Write-Host "Rebuilding quota for vServers... " -NoNewline

   # Parcours des vServers
   foreach($serverName in $vServersQuotaToRebuild.Keys)
   {
      Write-Host "$serverName "     
      # Recherche des infos du vServer
      $vserver = Get-NcVserver -Controller $connectHandle -Name $serverName
      
      Write-Host "Resizing quota on vServer $serverName"
      
      # Resize du volume pour appliquer la modification 
      $res = resizeQuota -controller $connectHandle -onVServer $vserver -volumeName $vServersQuotaToRebuild.Get_Item($serverName)
      
      
   }# FIN BOUCLE de parcours des vServers
   
   Write-Host "done"
}

Write-Host ("{0} users have been deleted" -f $nbDeleted)

