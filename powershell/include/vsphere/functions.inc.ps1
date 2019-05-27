<# 
    BUT : Contient des fonctions utilisant vSphere qui sont utilisées par beaucoup de scripts PowerShell différents.
        Elles ont été regroupées dans un seul et même fichier afin d'éviter les copier-coller dans
        chaque script les nécessitant.
 
  AUTEUR : Lucien Chaboudez
  DATE   : 27.05.2019
 
 UTILISATION : Il suffit d'ajouter une ligne comme ceci au début du script qui a besoin des fonctions :
 . "<pathToScript>func.inc.ps1"
 
 ------
 HISTORIQUE DES VERSIONS
 1.0 - Version de base
 
 
#>


<#
   BUT : Charge (si besoin) les modules PowerCli permettant de se connecter à vSphere
#>
function loadPowerCliModules
{
   #Save the current value in the $p variable.
   $p = [Environment]::GetEnvironmentVariable("PSModulePath")

   # Par défaut, le chemin où se trouvent les modules PowerCLI ne se trouve pas dans le Path. 
   # On ajoute donc le nécessaire.
   $p += ";C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules\"

   #Add the paths in $p to the PSModulePath value.
   [Environment]::SetEnvironmentVariable("PSModulePath",$p)

   # Si module pas encore chargé, 
   if(!(Get-Module VMware.VimAutomation.Core))
   {
      try
      {
         Write-Host "Loading module 'VMware.VimAutomation.Core'... " -NoNewline
         Import-Module VMware.VimAutomation.Core
         Write-Host "done"
      }
      catch
      {
         Write-Error "VMware.VimAutomation.Core module is not installed"
         exit
      }
   }
   else
   {
      Write-Host "Module 'VMware.VimAutomation.Core' already loaded"
   }
}