<#
   BUT : Récupère les quotas des différents FS et push les informations sur le serveur web
   
   AUTEUR : Lucien Chaboudez
   DATE   : Août 2014
   
   PARAMETRES : Aucun
   
   REMARQUE  : Pour que ce script fonctionne, il faut installer le module ActiveDirectory. Prendre le bon fichier d'install
		         dans ..\Interne_DIT\_EX\SDS\Services\MyNAS\Scripts\Recherche des utilisateurs mal effacés dans LDAP\
               et suivre la procédure qui est ici : 
               http://blogs.msdn.com/b/rkramesh/archive/2012/01/17/how-to-add-active-directory-module-in-powershell-in-windows-7.aspx

 		      Si le programme d'install vous dit "This update is not applicable to this computer" c'est qu'il ne reste 
            probablement plus qu'à activer la Feature.
            Vous pouvez ensuite tester que le module est bien présent avec :
            Get-Module -ListAvailable
      
   DEPENDANCES :
   - Fichier exécutable "pscp.exe" pour la copie via SSH
   
    - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
   SI EXECUTION PAR TACHE PLANIFIEE
   Ajouter les clefs de registre de Putty concernant les machines distantes HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\SshHostKeys
   dans HKEY_USER\.DEFAULT\Software\SimonTatham\PuTTY\SshHostKeys. Pour ce faire, exporter la clef 
   HKEY_CURRENT_USER\Software\SimonTatham\PuTTY\SshHostKeys, modifier le fichier *.reg pour
   mettre le chemin jusqu'à HKEY_USER\.DEFAULT..., exécuter le *.reg et c'est bon :-)
   
   - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - 
   !! AVANT D'EXECUTER LE SCRIPT !!
   - Exécuter une fois pscp.exe en tentant de se connecter à ditex-web pour ajouter la clef SSH en local.   
   
   
   MODIFS :
   11.03.2015 - LC - Correction de 2 bugs: 
                     1. Formatage des données incorrect lors de la mise dans le fichier. Il y avait des " entre les valeurs
                     2. Mauvais paramètre récupéré pour le nombre de fichiers utilisés (FileUsed au lieu de FilesUsed)
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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "NameGeneratorMyNAS.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")
$configGlobal = [ConfigReader]::New("config-global.json")

# -------------------------------- CONSTANTES -----------------------------

$REMOTE_DIRECTORY="/www/mynas/web/upload/"
$OUTPUT_QUOTAS    = ([IO.Path]::Combine($global:FILES_TO_PUSH_FOLDER, "mynas_user_size_usage"))


# -------------------------------- FONCTIONS ---------------------------

<#
   BUT : Renvoie la valeur "adéquate" pour une limite de quota. Il se peut en 
         effet que l'on ai un "-" s'il n'y a pas de valeur. Dans ce cas-là, on renvoie 0
         
   IN  : $fromString    -> Chaine de caractères depuis laquelle récupérer la valeur
   
   RET : La valeur
#>
function getQuotaLimitValue
{
   param([string] $fromString)
   
   if($fromString -eq "-")
   {
      return 0
   }
   return $fromString
}



# ------------------------------------------------------------------

<#
   BUT : Renvoie l'UID de l'utilisateur dont on a passé le nom en paramètre. 
         
   IN  : $username   -> Nom d'utilisateur
                        Le nom peut être passé sous les formes suivantes :
                        <domain>\<username>
                        <username>
   
   RET : l'uid
#>
function getUIDFromUsername 
{
   param([string] $username)
   
   # Extraction du nom court de l'utilisateur (sans le domaine devant)
   $usernameShort = extractUsername -fromDomainUserString $username
   
   
   # Retour du résultat 
   return (Get-ADUser -Filter {uid -like $usernameShort} -Properties uidNumber).uidNumber

}

# ------------------------------------------------------------------

<#
   BUT : Extrait le nom d'utilisateur depuis une chaine "domain\username" et le renvoie
   
   IN  : $fromDomainUserString -> Chaine de caractères sous la forme "domain\username" ou "username"
   
   RET : Le nom d'utilisateur
#> 

function extractUsername
{ 
   param([string] $fromDomainUserString)
   
   $split = $fromDomainUserString.Split("\\")
   
   return $split[$split.Count-1]
}

# ----------------------------------------------------------------------

<#
   BUT : Renvoie le numéro du filesystem (ou serveur) sur lequel devra 
         se trouver l'utilisateur dont le UID est passé en paramètre
         
   IN  : $uid     -> UID de l'utilisateur.
#>
function getFSNoFromUID 
{
   param([string] $uid)
   
   return $uid.substring($uid.Length-1,1)
}

# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
   # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
   $logHistory = [LogHistory]::new('mynas-push-user-quota-usage', (Join-Path $PSScriptRoot "logs"), 30)

   # Objet pour pouvoir envoyer des mails de notification
   $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "MyNAS", "")
   
   $nameGeneratorMyNAS = [NameGeneratorMyNAS]::new()

   # Création de l'objet pour se connecter aux clusters NetApp
   $netapp = [NetAppAPI]::new($configMyNAS.getConfigValue("nas", "serverList"), `
                              $configMyNAS.getConfigValue("nas", "user"), `
                              $configMyNAS.getConfigValue("nas", "password"))


   # Chargement du module (si nécessaire)
   Import-Module ActiveDirectory

   # Si le dossier de sortie n'existe pas, on le créé
   if(!(Test-Path -Path $global:FILES_TO_PUSH_FOLDER))
   {
      New-Item -ItemType Directory -Path $global:FILES_TO_PUSH_FOLDER | Out-Null
   }

   # Effacement des fichiers de sortie pour ne pas appondre les données dedans. 
   delOutputFilesIfExists $OUTPUT_QUOTAS

   checkEnvironment

   # Récupération de la date courante
   $curDate = Get-Date -format yyyy-MM-dd

   $somethingToPush=$false

   # Parcours des No de FS à traiter,
   #foreach($fsNo in @("8"))
   for($fsNo=0; $fsNo -lt 10; $fsNo++)
   {
      $somethingToPush=$true

      # Génération du nom du vServer et du FS
      $volName = $nameGeneratorMyNAS.getVolumeName($fsNo)
      
      # Récupération de la liste des quotas 
      $logHistory.addLineAndDisplay("Getting quota list for $volName... ")
      $volume = $netapp.getVolumeByName($volName)
      $quotaList = $netapp.getVolumeQuotaReportList($volume)
      
      # Recherche du nombre d'éléments 
      $nbQuota = getNBElemInObject -inObject $quotaList
      
      # Si pas de quota, on passe au FS suivant 
      if($nbQuota -eq 0)
      {
         $logHistory.addLineAndDisplay("No quota found, skipping... ")
         continue
      }
      
      $logHistory.addLineAndDisplay(("{0} quota entries found" -f $nbQuota))

      # Parcours des quotas renvoyés 
      foreach($quotaInfos in $quotaList)
      {
         # Recherche de l'UID LDAP de l'utilisateur 
         $userUID = getUIDFromUsername -username $quotaInfos.users[0].name
         $logHistory.addLineAndDisplay(("{0}={1}" -f $quotaInfos.users[0].name, $userUID))
         
         # On skip si :
         # - Pas d'UID trouvé, c'est que ce n'est pas un utilisateur du domaine
         # - UID = 0 donc pas un "vrai" compte utilisateur mais plutôt un compte de service
         if( ($null -eq $userUID) -or ($userUID -eq 0)) 
         {
            continue
         }
         
         <# Si le quota que l'on traite ne devrait pas se trouver sur le volume courant,
            on le skip car sinon cela faussera les informations importées dans le site web #>
         if( (getFSNoFromUID -uid $userUID) -ne $fsNo)
         {
            continue
         }
         
         
         # liste pour les informations à mettre dans le fichier de sortie 
         # Pour coller à l'ancien NAS EMC, les données doivent être formatées comme suit :
         # $uidNAS,$uid,$MDATE,$used_mb,$nb_files,$soft_mb,$hard_mb
         $quotaInfosOut = @(
            $userUID
            $userUID
            $curDate
            ([Math]::Floor((getQuotaLimitValue -fromString $quotaInfos.space.used.total)/1024/1024)) # usedMB
            $quotaInfos.files.used.total # nbFiles
            ([Math]::Floor((getQuotaLimitValue -fromString $quotaInfos.space.soft_limit)/1024/1024)) # SoftMB
            ([Math]::Floor((getQuotaLimitValue -fromString $quotaInfos.space.hard_limit)/1024/1024)) # HardMB
         )
         
         ( $quotaInfosOut -join ',') | Out-File -Append -FilePath $OUTPUT_QUOTAS -Encoding Default

      
      }# FIN De boucle de parcours des quotas définis pour le volume 
      
   }# FIN Boucle de parcours des nos de FS à traiter 

   if($somethingToPush)
   {
      $logHistory.addLineAndDisplay("Pushing files... ")
      
      # Push des fichiers sur le site web 
      pushFile -targetFolder $REMOTE_DIRECTORY -fileToPush $OUTPUT_QUOTAS
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