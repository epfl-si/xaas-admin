<#
1   BUT : Ce script fait plusieurs choses
   - Récupération de la liste des nouveaux utilisateurs afin de créer leur dossier (via commande CMD)
   - Récupération des informations de quotas des utilisateurs afin de dire lesquels changer. Ces informations sont
     ensuite poussées dans la DB du site MyNAS (via un WebService)
   - Récupération de la liste des utilisateurs qui ont quittés l'école et qu'il faudra effacer dans le futur. Ces 
     informations sont ensuite poussées dans la base de données du site MyNAS (via un WebService)

   AUTEURS : Laurent Durrer (version initiale du script)
             Lucien Chaboudez (version améliorée du script)
   DATE   : Mai 2018
   
   REMARQUE :
   Pour que ce script fonctionne correctement, il faut qu'il puisse envoyer (via pscp) les fichiers adéquats
   sur le serveur ditex-web.epfl.ch. Il est nécessaire d'exécuter le script courant avec l'utilisateur
   INTRANET\mynas-delete-user (en lançant simplement le fichier BAT via CMDLINE) ceci afin d'accepter la clef
   (rsa2 key fingerprint) identifiant le serveur ditex-web dans le cache local de l'utilisateur INTRANET\mynas-delete-user.
   Si on ne fait pas ceci, le script sera en attente d'une entrée utilisateur lorsque l'on voudra faire la
   copie via pscp et il ne se terminera donc jamais. Il sera simplement tué lors de la prochaine exécution du
   script, 24h plus tard.
   Cette manipulation doit être à nouveau exécutée lorsque l'ID de la machine ditex-web change.

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base par Laurent Durrer
   0.2 - Version améliorée par Lucien Chaboudez
   0.3 - Ajout d'une condition dans la récupération des utilisateurs pour lequels créer le dossier afin de ne prendre
         que ceux dont la date de début de l'accréditation est passée (ou égale au jour courant)
   0.4 - Suppression de la condition pour ne prendre que les dates d'accréditation qui ont débuté il y a 120 jours. Si
         le stockage individuel était appliqué après 120 jours sur l'accréditation, l'utilisateur n'était pas remonté
         par la requête.
   0.5 - Ajout d'un check lorsqu'il faut créer un dossier utilisateur, ceci afin de ne pas arriver dans le cas de figure
         où on créé le dossier et que le compte AD de l'utilisateur n'existe pas... dans ce cas-là, on se retrouve avec 
         un dossier ayant des droits incorrects. Le fait de ne pas traiter les utilisateurs qui n'ont pas (encore) de 
         compte AD permet de les traiter lorsqu'ils auront un compte.
   0.6 - Utilisation de la classe MyNASACLUtils pour gérer les droits

#>


. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "NameGeneratorMyNAS.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "MyNASACLUtils.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# --------------------- CONSTANTES --------------------------



# Base pour ensuite construire l'URL qui va déclencher l'import des données sur le site web
$baseTriggerImporURL = "{0}/ws/DBDataImport-web.php?empty_tables={1}&configs={2}&exclude_cond={3}"


#------------------------- FONCTIONS -----------------------
function displayPart([string]$title)
{
   $size = 60
   
   $logHistory.addLineAndDisplay("-".PadLeft($size,"-"))
   $logHistory.addLineAndDisplay((" {0} " -f $title).PadLeft($size/2+([Math]::Floor($title.length/2)),"-").PadRight($size,"-"))
   $logHistory.addLineAndDisplay("-".PadLeft($size,"-"))
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

   # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
   $logHistory = [LogHistory]::new('mynas-process-info-from-cadi', (Join-Path $PSScriptRoot "logs"), 30)

   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MYNAS_MAIL_TEMPLATE_FOLDER, $global:MYNAS_MAIL_SUBJECT_PREFIX, @{})
   
   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

   # Création de l'objet pour gérer les ACLs
   $myNASAclUtils = [MyNASACLUtils]::new($global:LOGS_FOLDER, $global:BINARY_FOLDER, $nameGeneratorMyNAS, $logHistory)

   # Création de l'objet pour faire les requêtes dans CADI
   $mysql_cadi = [SQLDB]::new([DBType]::MySQL, `
                              $configMyNAS.getConfigValue(@("cadi", "host")),
                              $configMyNAS.getConfigValue(@("cadi", "db")),
                              $configMyNAS.getConfigValue(@("cadi", "user")),
                              $configMyNAS.getConfigValue(@("cadi", "password")),
                              $configMyNAS.getConfigValue(@("cadi", "port")))

   # Création du dossier si n'existe pas
   if(!(Test-path $global:FILES_TO_PUSH_FOLDER))
   {
      New-Item  $global:FILES_TO_PUSH_FOLDER -ItemType "directory" | Out-null
   }

   checkEnvironment

   
   # ---- TESTS
   # Pour récupérer les utilisateurs qui sont à la fois dans départ et arrivée...
   #$incorrectUsers = "SELECT Personnes.sciper, username FROM Accreds INNER JOIN Personnes ON Accreds.sciper = Personnes.sciper WHERE (Accreds.ordre = '1') AND (Accreds.stockindiv = 'y')  AND (Accreds.comptead = 'y') AND (DATE(Accreds.datedeb) <= CURDATE()) AND (username IS NOT NULL) AND Personnes.sciper IN (SELECT sciper FROM Departs WHERE date_add(datedepart, INTERVAL 190 day) < curdate() AND  datedepart > date_add(curdate(), INTERVAL -365 day))"
   $usersToDeleteRequest = "SELECT sciper, date_add(datedepart, interval 190 day)AS 'whenToDelete' FROM Departs WHERE datedepart < curdate() AND  datedepart > date_add(curdate(), INTERVAL -365 day);"
   #$users = $mysql_cadi.execute($usersToDeleteRequest)

   #$users | Export-Csv -Path D:\scripts\incorrect.csv

   <# -------------------------------------------------------------------------------
   1 - Création des dossiers utilisateurs
   ------------------------------------------------------------------------------- #>
   # dateDebut
   displayPart -title "USER FOLDER CREATION"

   # Requête pour chercher les utilisateurs qui doivent avoir un dossier sur MyNAS
   $request = "SELECT Personnes.sciper, username FROM Accreds INNER JOIN Personnes ON Accreds.sciper = Personnes.sciper WHERE (Accreds.ordre = '1') AND (Accreds.stockindiv = 'y')  AND (Accreds.comptead = 'y') AND (DATE(Accreds.datedeb) <= CURDATE()) AND (username IS NOT NULL)"
   #$request = "SELECT Personnes.sciper, username FROM Accreds INNER JOIN Personnes ON Accreds.sciper = Personnes.sciper WHERE (Accreds.ordre = '1') AND (Accreds.stockindiv = 'y')  AND (Accreds.comptead = 'y') AND (DATE(Accreds.datedeb) <= CURDATE()) AND (username IS NOT NULL) and Personnes.sciper='292334'"

   $logHistory.addLineAndDisplay("Getting users to create on CADI...")
   $users = $mysql_cadi.execute($request)
   $nbCreated = 0
   ForEach($user in $users)
   {
      # Création du chemin jusqu'au dossier
      $filesNo = $nameGeneratorMyNAS.getServerNo($user.sciper)
      $server = "files{0}" -f $filesNo
      $pathToFolder = $nameGeneratorMyNAS.getUserUNCPath($server, $user.username)

      # Si le dossier n'existe pas 
      if(!(Test-Path -Path $pathToFolder))
      {
         
         # On regarde si l'utilisateur se trouve dans AD. Si ce n'est pas le cas, on passe au suivant, tout en ayant loggué la chose.
         try
         {
            $ADuser = Get-ADUser -Identity $user.username -Properties *
         }
         catch
         {
            # Si on arrive ici, c'est que l'utilisateur n'existe pas dans AD
            $logHistory.addWarningAndDisplay(("User account for '{0}' not found in Active Directory" -f $user.username))
            Continue
         }
         
      
         $logHistory.addLineAndDisplay(("Folder for user '{0}' ({1}) doesn't exists -> creation" -f $user.username, $server) )
         
         # Création du dossier 
         New-Item $pathToFolder -ItemType directory | Out-Null

         $myNASAclUtils.rebuildUserRights($server, $user.username, $user.username)
         
         $nbCreated += 1
      }
   }
   $logHistory.addLineAndDisplay( ("{0} user(s) folder(s) created" -f $nbCreated) )
   

   <# -------------------------------------------------------------------------------
   2 - Mise à jour des quotas
   ------------------------------------------------------------------------------- #>

   displayPart -title "QUOTA UPDATE REQUEST"

   # Fichier CSV pour enregistrer les infos de quotas à ajouter dans la DB 
   $quotaUpdateCSV = ([IO.Path]::Combine($global:FILES_TO_PUSH_FOLDER, "mynas_user_quota_update_request"))

   $quotaUpdateRequestResult =  ([IO.Path]::Combine($global:LOGS_FOLDER, "IMPORT_mynas_user_quota_update_request.log"))

   # Suppression du fichier s'il existe
   if(Test-Path $quotaUpdateCSV) {Remove-Item $quotaUpdateCSV}

   # Association entre statut de l'utilisateur et le quota auquel il a droit
   $userStatusToQuota = @{"1" = 25600  # collaborateurs
                        "2" = 5120}  # hôtes

   # Requête dont on va se service pour construire la requête de recherche pour les utilisateur d'un statut donné
   $baseSearchRequest = "SELECT Personnes.sciper, username FROM Accreds INNER JOIN Personnes ON Accreds.sciper = Personnes.sciper WHERE (statut = '{0}') AND (ordre = '1') AND (Accreds.stockindiv = 'y')  AND (Accreds.comptead = 'y')  AND (Accreds.datedeb <= CURDATE())"

   # Parcours des statuts
   ForEach($userStatus in $userStatusToQuota.Keys)
   {  
      # Construction de la requête 
      $request = $baseSearchRequest -f $userStatus
      
      $users = $mysql_cadi.execute($request)
      
      # Parcours des utilisateurs renvoyés et ajout dans le fichier CSV
      $users | ForEach-Object {
         #<sciper>,<username>,<soft_quota_mb>,<hard_quota_mb>
         ("{0},{1},{2},{2}" -f $_.sciper, $_.username, $userStatusToQuota[$userStatus]) | Out-File -Append -Encoding Default -FilePath $quotaUpdateCSV
      }
      
      $logHistory.addLineAndDisplay(("{0} users found with quota of {1}MB" -f $users.Count, $userStatusToQuota[$userStatus]) )
   }

   # Envoi du fichier contenant les infos sur le serveur Web.
   $logHistory.addLineAndDisplay( ("Pushing file '{0}' on ditex-web..." -f $quotaUpdateCSV) )
   # !! Si ça bloque sur cette commande dans le fichier log, voir entête du fichier, section "Remarque"
   pushFile -targetFolder "/www/mynas/web/upload/mynas_user_quota_update_request/" -fileToPush $quotaUpdateCSV


   # Déclenchement de l'import des données dans la DB (avec vidage de la table juste avant)
   $logHistory.addLineAndDisplay( ("Triggering import for pushed file ({0})..." -f $quotaUpdateCSV) )
   Invoke-WebRequest -Uri ($baseTriggerImporURL -f $global:WEBSITE_URL_MYNAS, "mynas_user_quota_update_request", "userQuotaUpdateRequest", "") -Method Get -OutFile $quotaUpdateRequestResult
   
   
   


   <# -------------------------------------------------------------------------------
   3 - Liste des utilisateurs à supprimer
   ------------------------------------------------------------------------------- #>

   displayPart -title "USER DELETE REQUEST"

   # Fichier CSV pour enregistrer les infos de quotas à ajouter dans la DB 
   $userDeleteCSV = ([IO.Path]::Combine($global:FILES_TO_PUSH_FOLDER, "mynas_user_delete_request"))

   $userDeleteRequestResult =  ([IO.Path]::Combine($global:LOGS_FOLDER, "IMPORT_mynas_user_delete_request.log"))

   # Suppression du fichier s'il existe
   if(Test-Path $userDeleteCSV) {Remove-Item $userDeleteCSV}
      
   # Requête pour récupérer la liste des utilisateurs à supprimer dans le futur
   $usersToDeleteRequest = "SELECT sciper, date_add(datedepart, interval 190 day)AS 'whenToDelete' FROM Departs WHERE datedepart < curdate() AND  datedepart > date_add(curdate(), INTERVAL -365 day);"
   
   $logHistory.addLineAndDisplay("Getting users to delete on CADI...")
   $users = $mysql_cadi.execute($usersToDeleteRequest)
      
   # Parcours des utilisateurs renvoyés et ajout dans le fichier CSV
   $users | ForEach-Object {
      #<sciper>,<when_to_delete>,<because_inactive>
      # Le dernier champ, c'est pour dire que l'utilisateur ne va pas être effacé parce qu'il est inactif
      $deleteDate = $_.whenToDelete.ToString("yyyy-MM-dd")
      ("{0},{1},0" -f $_.sciper, $deleteDate) | Out-File -Append -Encoding Default -FilePath $userDeleteCSV
   }
   $logHistory.addLineAndDisplay( ("{0} users to delete" -f $users.Count) )

   # Envoi du fichier contenant les infos sur le serveur Web.
   $logHistory.addLineAndDisplay( ("Pushing file '{0}' on ditex-web..." -f $userDeleteCSV) )
   # !! Si ça bloque sur cette commande dans le fichier log, voir entête du fichier, section "Remarque"
   pushFile -targetFolder "/www/mynas/web/upload/mynas_user_delete_request/" -fileToPush $userDeleteCSV
   
   # Déclenchement de l'import des données dans la DB (avec vidage de la table juste avant)
   $logHistory.addLineAndDisplay( ("Triggering import for pushed file ({0})..." -f $userDeleteCSV))

   # On créé et on encode la condition pour les champs à ne pas effacer dans la table "mynas_user_delete_request". On est obligé d'encoder vu 
   # que ça va être passé en query string à une URL.
   #$deleteExcludeCond = [System.Web.HttpUtility]::UrlEncode("because_inactive=1");
   # 2019-07-09 - LC - On encode manuellement parce que l'appel à HttpUtility ne fonctionne plus, ça lève une exception et on peut se permettre de
   # hard-coder la condition et de ne pas utiliser un encodage à la volée
   #$deleteExcludeCond = "because_inactive%3D1"
   # 2020-10-11 - LC - Strictement aucune idée pourquoi cette condition de "because inactive" avait été ajoutée ici et dans la DB !?! bref, elle posait
   # problème dans certains cas et faisait que des dossiers étaient créés et effacés à répétition... donc suppression de ça.s
   $deleteExcludeCond = ""

   Invoke-WebRequest -Uri ($baseTriggerImporURL -f $global:WEBSITE_URL_MYNAS, "mynas_user_delete_request", "userDeleteRequest", $deleteExcludeCond) -Method Get -OutFile $userDeleteRequestResult


   $logHistory.addLineAndDisplay( "All done!" )

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
