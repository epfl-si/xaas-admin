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
function fileOrFolderExists([NetApp.Ontapi.Filer.C.NcController] $controller, [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, [string] $fileOrDir)
{

   # Recherche des infos sur le dossier que l'on doit supprimer 
   Get-NcFile -Controller $controller -VserverContext $onVServer -Path $fileOrDir -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue | Out-Null
   
   return ($errorArray.Count -eq 0)
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
   BUT : Supprime le contenu d'un dossier donné. On est obligé de passer par une fonction spécifique pour faire
         ceci car le CmdLet d'effacement Remove-NcDirectory ne permet que de supprimer les dossiers vide... on 
         doit donc manuellement aller supprimer les fichiers contenus dans un dossier avant de supprimer le dossier
         en question. De plus, cette fonction s'appelle récursivement afin d'effacer toute l'arborescence donnée 

   IN  : $dirPathToRemove  -> Chemin à supprimer (chemin absolu, /vol/<volumeName>/<PathToDirToRemove>
   IN  : $controller       -> Handle sur le contrôleur NetApp sur lequel faire la requête
   IN  : $onVServer        -> Handle sur le vServer sur lequel le fichier/dossier 'fileOrDir' se trouve

   REMARQUE !!! Cette fonction marche mais son utilisation est déconseillée car les performances sont vraiment
                nulles... 
#>
function removeDirectory([NetApp.Ontapi.Filer.C.NcController] $controller, [DataONTAP.C.Types.Vserver.VserverInfo] $onVServer, [string] $dirPathToRemove)
{
   
   # Si le dossier n'existe pas, on quitte 
   if((fileOrFolderExists -fileOrDir $dirPathToRemove -controller $controller -onVServer $onVServer) -eq $false)
   {
      return 
   }
   
   # Recherche de la liste des fichiers qui sont dans le dossier (on masque les erreurs car expérience faite, ça fonctionne quand même.
   # C'est juste un peu plus agréable pour les yeux sans celles-ci)
   $filesList = Read-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -ErrorAction:SilentlyContinue  | Where-Object  { $_.FileType -ne "directory"}
   # Si on a trouvé des fichiers
   if($null -ne $filesList)
   {
      # Parcours des fichiers se trouvant dans le dossier et suppression
      foreach($fileInDir in $filesList)
      {
         # Tentative de suppression du fichier + gestion des erreurs 
         Remove-NcFile -Controller $controller -VserverContext $onVServer -Path $fileInDir.Path -Confirm:$false -ErrorVariable "errorArray" -ErrorAction:SilentlyContinue
         
      }# FIN BOUCLE de parcours des fichiers 
   }# FIN Si on a trouvé des fichiers 
   
   # Parcours des dossiers se trouvant dans le dossier courant 
   # (on masque les erreurs. ça fonctionne quand même sans. Et ce sont souvent des erreurs dues à des états gardés par l'API Powershell)
   foreach($dirInDir in (Read-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -ErrorAction:SilentlyContinue |
                        Where-Object  {$_.FileType -eq "directory" -and $_.Name -ne "." -and $_.Name -ne ".."}))
   {
      #$dirInDir.Path
      # Récursivité dans le dossier courant 
      removeDirectory -controller $controller -onVServer $onVServer -dirPathToRemove $dirInDir.Path
   }
   
   # Suppression du dossier courant 
   Remove-NcDirectory -Controller $controller -VserverContext $onVServer -Path $dirPathToRemove -Confirm:$false -ErrorVariable "errorArray"  -ErrorAction:SilentlyContinue
   
}
