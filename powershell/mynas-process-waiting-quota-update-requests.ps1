<#
   BUT : Permet de procéder à une extension de quota qui a été demandée par l'utilisateur
         et validée par l'admin de faculté
         
   
   AUTEUR : Lucien Chaboudez
   DATE   : Novembre 2014
   
   PARAMETRES :
   - Aucun -   
   
   REMARQUE : Ce script pourrait être amélioré en enregistrant, pendant l'exécution, la liste des volumes/vserver
              sur lesquels faire un "resize" et faire ceux-ci à la fin du script. Cela permettrait de gagner du temps.
              Cependant, cette possibilité n'a pas été implémentée dans le script courant car à priori, plus aucune
              augmentation de quota ne sera autorisée (ou alors cela sera des cas isolés). Du coup, la performance
              du script devient plus que relative...
   
   MODIFS:
   15.04.2015 - LC - Modification de la gestion des "resize" de volumes. Regroupage au lieu d'en faire un après 
                     chaque augmentation pour un utilisateur. Ceci diminue la durée d'exécution du script.
                   - Ajout d'envoi de mail pour informer de ce qui a été effectué.
   16.06.2017 - LC - Modification de la commande pour initialiser le quota. Depuis PowerShell Toolkit 4.4, il faut 
                     passer le chiffre en bytes et plus un chiffre avec une unité.
   21.08.2017 - LC - Il y avait une erreur quand on multipliait le quota par 1024 pour avoir des bytes... C'était un
                     string qui était multiplié 1024x ... correction. 
   
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

# ------------------------------------------------------------------------

<#
   BUT : Initialise un utilisateur comme ayant eu une update de quota en appelant le WebService 
         adéquat.
         
   IN  : $userSciper    -> Sciper de l'utilisateur pour lequel le quota a été mis à jour
#>
function setQuotaUpdateDone 
{
   param($userSciper)
   
   # Création de l'URL 
   $url = $global:WEBSITE_URL_MYNAS+"ws/set-quota-update-done.php?sciper="+$userSciper
   
   # Appel de l'URL pour initialiser l'utilisateur comme renommé 
   $res = getWebPageLines -url $url
}




# -------------------------------- PROGRAMME PRINCIPAL --------------------------------

# Chargement du module (si nécessaire)
loadDataOnTapModule 


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

$quotaUpdateList = getWebPageLines -url ("$global:WEBSITE_URL_MYNAS/ws/get-quota-updates.php?fs_mig_type=mig")

#$quotaUpdateList = @("dit_filesx_indiv,svonsieb,filesx,123456,4194304,4194304")

if($quotaUpdateList -eq $false)
{
   Write-Host -ForegroundColor:Red "Error getting quota update list!"
   exit 1
}

# Recherche du nombre de mises à jour de quota à effectuer 
$nbUpdates=getNBElemInObject -inObject $quotaUpdateList

Write-Host "$nbUpdates quota(s) to update"

# Si rien à faire,
if($nbUpdates -eq 0)
{  
   Write-Host "Nothing to do, exiting..."
   exit 0
}

# le format des lignes renvoyées est le suivant :
# <volumeName>,<usernameShort>,<vServerName>,<Sciper>,<softQuotaKB>,<hardQuotaKB>



# La liste des utilisateurs par vServer
$userPervServer=@{}
# Nouveau quotas des utilisateurs 
$userNewQuotaMessage=@{}

$doneMailMessage="Users updated:<br><table border='1' style='border-collapse:collapse;padding:3px;'><tr><td><b>Username</b></td><td><b>Old quota [MB]</b></td><td><b>New quota [MB]</b></td></tr>"

$oneQuotaUpdateDone=$false

# Parcours des éléments à renommer 
foreach($updateInfos in $quotaUpdateList)
{
   $quotaInfosArray = $updateInfos.split(',')

   # Génréation des informations 
   $volumeName=$quotaInfosArray[0]
   $username = $quotaInfosArray[1]
   $usernameAndDomain="INTRANET\"+$quotaInfosArray[1]
   $vserverName =$quotaInfosArray[2]
   $sciper = $quotaInfosArray[3]
   # Changemenet de la manière de "set" le quota depuis PowerShell Toolkit 4.4. Il faut maintenant passer des bytes au lieu 
   # d'un chiffre suivi de l'unité (ex: 25GB)
   $softKB=([int]$quotaInfosArray[4])*1024
   $hardKB=([int]$quotaInfosArray[5])*1024   
#   $softKB=$quotaInfosArray[4]+"KB"
#   $hardKB=$quotaInfosArray[5]+"KB"
   # Extraction du no du vServer 
   $vserverNo = $vserverName.Substring($vserverName.Length-1)

   # Recherche des infos du vServer sur lequel se trouve l'entrée de quota à modifier 
   $vserver = Get-NcVserver -Controller $connectHandle -Name $vserverName
   
   
   Write-Host -NoNewline "Changing quota for $usernameAndDomain "
   
   # Recherche du quota actuel 
   $currentQuota = Get-NcQuotaReport -Controller $connectHandle -Vserver $vserver -Volume $volumeName -Target $usernameAndDomain
   
   # Si pas trouvé, c'est que l'utilisateur a le quota par défaut
   if($null -eq $currentQuota)
   {
      $currentQuota = "'default'"
   }
   else
   {
      $currentQuota = ([Math]::Floor($currentQuota.DiskLimit/1024))
   }
   
   Write-Host -NoNewline ("(current: "+$currentQuota+" MB - New: "+([Math]::Floor($quotaInfosArray[5]/1024))+" MB)... ") 
   # Exécution de la requête 
   $res = Set-NcQuota -Controller $connectHandle -VserverContext $vserver -Volume $volumeName -Target $usernameAndDomain -Type user -Qtree "" -DiskLimit $hardKB -SoftDiskLimit $softKB

   Write-Host "done"
   
   # Si on n'a pas encore traité ce no de volume, 
   if($userPervServer.Keys -notcontains $vserverNo)
   {
      # Création d'une liste pour le vServer courant et ajout 
      $userPervServer.$vserverNo = @()
   }
   
   # Ajout du Sciper de l'utilisateur dans la liste 
   $userPervServer.$vserverNo += $sciper
   
   # Enregistrement du nouveau quota pour l'utilisateur
   $userNewQuotaMessage.$sciper = ([string]::Concat("<tr><td>",$username ,"</td><td>", $currentQuota, "</td><td>", ([Math]::Floor($quotaInfosArray[5]/1024)), "</td></tr>"))
   

}# FIN BOUCLE de parcours des quotas à modifier

<# 
   Une fois que toutes les modifications de quota on été effectuées sur les X volumes concernés,
   on peut faire les "resize" sur les volumes en question. Et ce n'est que quand un "resize" se 
   termine correctement que l'on initialise les utilisateurs du volume concerné comme ayant leur
   demande d'augmentation de quota traitée. Et c'est aussi à ce moment-là qu'on les ajoute dans
   le message qui sera envoyé par mail à la fin de l'exécution du script
#>



# Parcours des no de vServer sur lequels des extensions de quota ont été effectuées
foreach($vserverNo in $userPervServer.Keys)
{
   $volumeName = "dit_files"+$vserverNo+"_indiv"
   $vserverName = "files"+$vserverNo
   
   # Recherche des infos du vServer sur lequel on doit faire le resize
   $vserver = Get-NcVserver -Controller $connectHandle -Name $vserverName
   
   Write-Host "Resizing volume $volumeName... " -NoNewline
   # Démarrage du Resize pour le volume 
   $res = resizeQuota -controller $connectHandle -onVServer $vserver -volumeName $volumeName
   
   # Si erreur dans le traitement 
   if($res.JobState -eq "failure")
   {
      # Envoi d'un mail aux admins 
      sendMailToAdmins -mailMessage ([string]::Concat("Error doing 'quota resize' on volume $volumeName<br><b>Error:</b><br>", $res.JobCompletion, `
            "<br>There is several possibilities:<ul>", `
            "<li>There is probably some users delete requests that not have been processed. Process them and wait until the next quota update process.</li>", `
            "<li>It is possible that the user will be renamed tomorrow. The account is probably already renamed in AD and the folder has to be renamed.</li>", `
            "</ul>")) `
            -mailSubject "MyNAS Service: Error processing quota update requests for volume $volumeName"   
                           
      Write-Host "Error doing resize, skipping this volume..."
      
   }
   else # Pas d'erreur dans le traitement 
   {
      Write-Host "done"
      Write-Host -NoNewline "Setting update as done for users on volume $volumeName... "
      # Parcours des Sciper se trouvant sur le volume que l'on vient de "resize"
      foreach($sciper in $userPervServer.$vserverNo)
      {
         # On initialise la requête comme ayant été traitée
         setQuotaUpdateDone -userSciper $sciper
         
         # Ajout de l'info au message qu'on aura dans le mail 
         $doneMailMessage += $userNewQuotaMessage.$sciper
         
         $oneQuotaUpdateDone=$true
      }
      Write-Host "done"
   }# FIN SI pas d'erreur dans le traitement
   
}# FIN BOUCLE DE parcours de vServer


# Si on a fait au moins une extension de quota
if($oneQuotaUpdateDone)
{
   $doneMailMessage += "</table>"

   # Envoi d'un mail pour dire que tout s'est bien passé
   sendMailToAdmins -mailMessage $doneMailMessage -mailSubject ([string]::Concat("MyNAS Service: Quota updated for ",$nbUpdates ," users"))
}
