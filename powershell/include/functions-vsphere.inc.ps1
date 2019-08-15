<#
   BUT : Contient les fonctions propres à vSphere utilisées par les différents scripts

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2019

   ----------
   HISTORIQUE DES VERSIONS
   11.02.2019 - Version de base
   
#>

<#
   BUT : Charge (si besoin) les modules PowerCli permettant de se connecter à vSphere
#>
function loadPowerCliModules([parameter(Mandatory=$false)] [bool]$displayOutput=$true)
{
   

   #Save the current value in the $p variable.
   $p = [Environment]::GetEnvironmentVariable("PSModulePath")

   # Par défaut, le chemin où se trouvent les modules PowerCLI ne se trouve pas dans le Path. 
   # On ajoute donc le nécessaire pour chercher dans x86
   $p += ";C:\Program Files (x86)\VMware\Infrastructure\PowerCLI\Modules\"
   # et dans x64
   $p += ";C:\Program Files\WindowsPowerShell\Modules\"

   #Add the paths in $p to the PSModulePath value.
   [Environment]::SetEnvironmentVariable("PSModulePath",$p)

   # Si module pas encore chargé, 
   if(!(Get-Module VMware.VimAutomation.Core))
   {
      try
      {
         if($displayOutput)
         {
            Write-Host "Loading module 'VMware.VimAutomation.Core'... " -NoNewline
         }
         Import-Module VMware.VimAutomation.Core
         if($displayOutput)
         {
            Write-Host "done"
         }
      }
      catch
      {
         Write-Error "VMware.VimAutomation.Core module is not installed"
         exit
      }
   }
   else
   {
      if($displayOutput)
      {
         Write-Host "Module 'VMware.VimAutomation.Core' already loaded"
      }
   }
}