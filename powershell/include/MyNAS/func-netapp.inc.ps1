<# BUT : Contient des fonctions utilisant le NetApp qui sont utilisées par beaucoup de scripts PowerShell différents.
        Elles ont été regroupées dans un seul et même fichier afin d'éviter les copier-coller dans
        chaque script les nécessitant.
 
  AUTEUR : Lucien Chaboudez
  DATE   : 22.07.2014 
 
 UTILISATION : Il suffit d'ajouter une ligne comme ceci au début du script qui a besoin des fonctions :
 . "<pathToScript>func-netapp.inc.ps1"
 
 ------
 HISTORIQUE DES VERSIONS
 1.0 - Version de base
 
 
#>

# ------------------------------------------------------------------------

<#
   BUT : Permet de savoir si un fichier ou dossier existe sur le NetApp
   
   IN  : $fileOrDir     -> Chemin jusqu'au fichier/dossier dont on veut savoir s'il existe.
                           Le chemin doit être sous la forme "<volName>/path/toFile"
   IN  : $controller    -> Handle sur le contrôleur NetApp sur lequel faire la requête
   IN  : $onVServer     -> Handle sur le VServer sur lequel le fichier/dossier 'fileOrDir' se trouve
   
   RET : TRUE|FALSE
#>
function fileOrFolderExists
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $fileOrDir)

   
   # Recherche des infos sur le dossier que l'on doit supprimer 
   $errorArray=@()
   $res = Get-NcFile -Controller $controller -VserverContext $onVServer -Path $fileOrDir -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue
   
   # Si le dossier n'existe pas, on quitte
   if($errorArray.Count -gt 0)
   {
      return $false
   }
   else
   {
      return $true
   }
}


# ------------------------------------------------------------------------



<#
   BUT : Renvoie le nom du OWNER d'un dossier/fichier donné
   
   IN  : $controller    -> Handle sur le contrôleur NetApp sur lequel on est connecté
   IN  : $onVServer     -> Handle sur le vServer sur lequel se trouve le Volume dans lequel se trouve
                           le fichier/dossier pour lequel on veut le OWNER. Le chemin doit être sous la forme
                           /path/to/folder mais il ne faut pas mettre le nom du point de montage au début.
   IN  : $onVolume      -> Nom du volume sur lequel chercher
   IN  : $fileOrDir     -> Chemin jusqu'au fichier/dossier dont on veut le OWNER.
                           Le chemin doit être sous la forme "/path/toFile"
                           
   RET : Nom du OWNER (shortname)
         $null si pas trouvé
         
#>
function getFileOrFolderOwner
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $onVolume,
         [string] $fileOrDir) 
         
    
   # Recherche des informations de sécurité   
   $errorArray=@()
   $securityInfos = Get-NcFileDirectorySecurity -Controller $controller -VserverContext $onVServer -Volume $onVolume -Path $fileOrDir -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue
   # Si une erreur s'est produite, on retourne $null
   if($errorArray.Count -gt 0)
   {
      return $null
   }

   # Parcours des ACLs
   foreach($acl in $securityInfos.Acls)
   {
      # Si on est sur l'ACL qui définit le OWNER
      # Ressemble à: Owner:INTRANET\chaboude
      if($acl -match '^Owner:')
      {
         # Retour du OWNER uniquement
         return ($acl.split('\'))[1]
      }
   }# FIN BOUCLE de parcours des ACLs
   
   # Si on arrive ici, c'est qu'on n'a pas trouvé
   return $null
}

# ------------------------------------------------------------------------

<#
   BUT : Charge (si besoin) le module DataOnTap permettant de se connecter
         au NetApp
#>
function loadDataOnTapModule
{
   
   if(!(Get-Module DataONTAP))
   {
      try
      {
         Write-Host "Loading module 'DataOnTap'... " -NoNewline
         Import-Module DataOntap
         Write-Host "done"
      }
      catch
      {
         Write-Error "DataOntap module is not installed"
         exit
      }
   }
   else
   {
      Write-Host "Module 'DataOnTap' already loaded"
   }
}

# ------------------------------------------------------------------------

<#
   BUT : Permet de savoir si un dossier se trouvant sur un vServer est vide ou pas.
   
   IN  : $controller       -> Handle sur la connexion au système NetApp
   IN  : $onVServer        -> Handle sur le vServer sur lequel se trouve le dossier à contrôler
   IN  : $folderPath       -> Chemin absolu jusqu'au dossier (/vol/<vol_name>/<path_to_folder>)
   
   RET : $true|$false
#>
function isFolderEmpty
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $folderPath) 

   $file = Get-NcFile -Controller $connectHandle -VserverContext $vserver -Path $folderPath
   
   return $file.IsEmpty
}

# ------------------------------------------------------------------------

<#
   BUT : Supprime le contenu d'un dossier donné. On est obligé de passer par une fonction spécifique pour faire
         ceci car le CmdLet d'effacement Remove-NcDirectory ne permet que de supprimer les dossiers vide... on 
         doit donc manuellement aller supprimer les fichiers contenus dans un dossier avant de supprimer le dossier
         en question. De plus, cette fonction s'appelle récursivement afin d'effacer toute l'arborescence donnée 

   IN  : $dirPathToRemove  -> Chemin à supprimer (chemin absolu, /vol/<volumeName>/<PathToDirToRemove>
   IN  : $controller       -> Handle sur le contrôleur NetApp sur lequel faire la requête
   IN  : $onVServer        -> Handle sur le vServer sur lequel le fichier/dossier 'fileOrDir' se trouve

   RET : Le nombre d'éléments effacés
   
   REMARQUE !!! Cette fonction marche mais son utilisation est déconseillée car les performances sont vraiment
                nulles... 
#>
function removeDirectory
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $dirPathToRemove,[int]$nbDelTot)
   
   $DISPLAY_STEP=250
   
   $nbDel = 0

   # Si le dossier n'existe pas, on quitte 
   if((fileOrFolderExists -fileOrDir $dirPathToRemove -controller $controller -onVServer $onVServer) -eq $false)
   {
      return $nbDel
   }
   
   # Recherche de la liste des fichiers qui sont dans le dossier (on masque les erreurs car expérience faite, ça fonctionne quand même.
   # C'est juste un peu plus agréable pour les yeux sans celles-ci)
   $filesList = Read-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -ErrorAction:SilentlyContinue  | Where-Object  {$_.FileType -eq "file"}
   # Si on a trouvé des fichiers
   if($null -ne $filesList)
   {
      # Parcours des fichiers se trouvant dans le dossier et suppression
      foreach($fileInDir in $filesList)
      {
         $errorArray = @()
         # Tentative de suppression du fichier + gestion des erreurs 
         Remove-NcFile -Controller $controller -VserverContext $onVServer -Path $fileInDir.Path -Confirm:$false -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue
         # Si pas d'erreur 
         if($errorArray.Count -eq 0)
         {
            $nbDel++
            $nbDelTot++
            # Affichage de l'avancement tous les $DISPLAY_STEP éléments
            if(($nbDelTot % $DISPLAY_STEP)-eq 0){Write-Host "$nbDelTot " -NoNewline}
         }
      }# FIN BOUCLE de parcours des fichiers 
   }# FIN Si on a trouvé des fichiers 
   
   # Parcours des dossiers se trouvant dans le dossier courant 
   # (on masque les erreurs. ça fonctionne quand même sans. Et ce sont souvent des erreurs dues à des états gardés par l'API Powershell)
   foreach($dirInDir in (Read-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -ErrorAction:SilentlyContinue |
                        Where-Object  {$_.FileType -eq "directory" -and $_.Name -ne "." -and $_.Name -ne ".."}))
   {
      #$dirInDir.Path
      # Récursivité dans le dossier courant 
      $nbDel += removeDirectory -controller $controller -onVServer $onVServer -dirPathToRemove $dirInDir.Path -nbDelTot $nbDelTot
   }
   $errorArray = @()
   
   # Suppression du dossier courant 
   Remove-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -Confirm:$false -ErrorVariable "errorArray"  -ErrorAction:SilentlyContinue
   # Si pas d'erreur 
   if($errorArray.Count -eq 0)
   {
      $nbDel++
      $nbDelTot++
      # Affichage de l'avancement tous les $DISPLAY_STEP éléments
      if(($nbDelTot%$DISPLAY_STEP)-eq 0){Write-Host "$nbDelTot " -NoNewline}
   }
   
   
   return $nbDel
}

# ------------------------------------------------------------------------

<# 
   BUT : Effectue un "resize" sur un volume pour appliquer les modifications faites dans les règles de quota.
         La fonction ne rend la main qu'une fois que le resize est terminé.
   
   IN  : $controller       -> Handle sur le contrôleur NetApp sur lequel faire la requête
   IN  : $onVServer        -> Handle sur le vServer sur lequel le fichier/dossier 'fileOrDir' se trouve
   IN  : $volumeName       -> Nom du volume sur lequel faire le resize.
#>
function resizeQuota
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $volumeName)
   
   $res = Start-NcQuotaResize -Controller $controller -VserverContext $onVServer -Volume $volumeName 

   # On attend que le job soit terminé
   while( ($res.JobState -eq "running") -or ($res.JobState -eq "queued"))
   {
      Start-Sleep -Milliseconds 2000
      $res = Get-NcJob -Controller $controller -Id $res.JobId
   }
   
   return $res
}

# ------------------------------------------------------------------------

<# 
   BUT : Ajoute un membre dans un groupe local de serveur CIFS si celui-ci ne s'y trouve pas déjà
   
   IN  : $controller       -> Handle sur le contrôleur NetApp sur lequel faire la requête
   IN  : $onVServer        -> Handle sur le vServer CIFS concerné par l'action
   IN  : $groupName        -> Nom du groupe auquel ajouter le membre 
                              EX: BUILTIN\Administrators
   IN  : $memberName       -> Nom du membre à ajouter
                              EX: INTRANET\ditex-adminsU
#>
function addMemberToLocalCIFSGroup
{
   param([NetApp.Ontapi.Filer.C.NcController] $controller, 
         [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, 
         [string] $groupName, [string] $memberName)
   
   # On commence par rechercher les membres du groupe concerné
   $groupMembers = Get-NcCifsLocalGroupMember -Controller $controller -Vserver $onVServer -Name $groupName
   
   # Pour dire si on a trouvé ou pas le membre
   $memberFound=$false
   
   # Parcours des membres
   foreach($member in $groupMembers)
   {
      if($member.Member -eq $memberName)
      {
         $memberFound = $true
         break
      }
   }# FIN Boucle de parcours des membres
   
   # Si le membre n'a pas été trouvé, on doit l'ajouter 
   if(!$memberFound)
   {
      $res = Add-NcCifsLocalGroupMember -Controller $controller -VserverContext $onVServer -Name $groupName -Member $memberName 
   }# FIN SI membre pas trouvé dans le groupe 
   
}










