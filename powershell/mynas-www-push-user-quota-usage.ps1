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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "define.inc.ps1"))

# Inclusion des fonctions spécifiques à NetApp depuis un autre fichier
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func-netapp.inc.ps1"))

# Inclusion des fonctions générique depuis un autre fichier
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MyNAS", "func.inc.ps1"))

# Chargement des fichiers de configuration
$configMyNAS = [ConfigReader]::New("config-mynas.json")

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

# -------------------------------- PROGRAMME PRINCIPAL --------------------------------

# Chargement du module (si nécessaire)
loadDataOnTapModule 
Import-Module ActiveDirectory

# Si le dossier de sortie n'existe pas, on le créé
if(!(Test-Path -Path $global:FILES_TO_PUSH_FOLDER))
{
   New-Item -ItemType Directory -Path $global:FILES_TO_PUSH_FOLDER | Out-Null
}

# Effacement des fichiers de sortie pour ne pas appondre les données dedans. 
delOutputFilesIfExists $OUTPUT_QUOTAS

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

# Récupération de la date courante
$curDate = Get-Date -format yyyy-MM-dd

$somethingToPush=$false

# Parcours des No de FS à traiter,
#foreach($fsNo in @("8"))
for($fsNo=0; $fsNo -lt 10; $fsNo++)
{
   $somethingToPush=$true

   # Génération du nom du vServer et du FS
   $vserverName="files$fsNo"
   $volName="dit_files"+$fsNo+"_indiv"
   
   
   # Récupération du Vserver
   $onVServer = Get-NcVserver -Controller $connectHandle -Name $serverName   
   
   # Récupération de la liste des quotas 
   Write-Host -NoNewline "Getting quota list for $volName... "
   $quotaList = Get-NcQuotaReport -Controller $connectHandle -Volume $volName -Type user -Vserver $onVServer
   
   # Recherche du nombre d'éléments 
   $nbQuota = getNBElemInObject -inObject $quotaList
   
   # Si pas de quota, on passe au FS suivant 
   if($nbQuota -eq 0)
   {
      Write-Host "No quota found, skipping... "
      continue
   }
   
   # Parcours des quotas renvoyés 
   foreach($quotaInfos in $quotaList)
   {
   
         
      # Si le quota est bien défini pour un utilisateur, 
      # NOTE: On est obligé de contrôler plusieurs éléments car c'est un peu "foireux" comme c'est codé cette API.
      #       Il se peut que $quotaInfos.QuotaTarget soit $null alors que $quotaInfos.QuotaUsers ne le soit pas... ce qui est
      #       illogique. Et c'est sur le champ "$quotaInfos.QuotaTarget" que se base visiblement la commande "quota report"
      #       de NetApp. Donc il est pertinent de contrôler aussi la valeur de ce champ.
      # EDIT: 19.05.2015 - LC - Le raisonnement ci-dessus n'est pas toujours valable... donc mise en commentaire
      #       d'un check ajouté auparavant.
      if(($quotaInfos.QuotaUsers -ne $null) -and ($quotaInfos.QuotaUsers[0].QuotaUserName -ne $null)) # -and ($quotaInfos.QuotaTarget -ne $null) )
      {
         
      
         # Recherche de l'UID LDAP de l'utilisateur 
         $userUID = getUIDFromUsername -username $quotaInfos.QuotaUsers[0].QuotaUserName
         
         $uname = $quotaInfos.QuotaUsers[0].QuotaUserName
         Write-Host "$uname=$userUID"
         
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
         $quotaInfosOut = @()
         $quotaInfosOut += $userUID
         $quotaInfosOut += $userUID
         $quotaInfosOut += $curDate
         $quotaInfosOut += ( (getQuotaLimitValue -fromString $quotaInfos.DiskUsed)/1024) # usedMB
         $quotaInfosOut += $quotaInfos.FilesUsed # nbFiles
         $quotaInfosOut += [Math]::Floor((getQuotaLimitValue -fromString $quotaInfos.SoftDiskLimit)/1024) # SoftMB
         $quotaInfosOut += [Math]::Floor((getQuotaLimitValue -fromString $quotaInfos.DiskLimit)/1024) # HardMB
         
         ( $quotaInfosOut -join ',') | Out-File -Append -FilePath $OUTPUT_QUOTAS -Encoding Default
         
      }# FIN Si le quota est bien défini pour un utilisateur
   
   }# FIN De boucle de parcours des quotas définis pour le volume 
   
   Write-Host "done"
   
}# FIN Boucle de parcours des nos de FS à traiter 

if($somethingToPush)
{
   Write-Host -NoNewline "Pushing files... "
   
   # Push des fichiers sur le site web 
   pushFile -targetFolder $REMOTE_DIRECTORY -fileToPush $OUTPUT_QUOTAS
}

Write-Host "done"

