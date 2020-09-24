<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS NAS

   AUTEUR : Lucien Chaboudez
   DATE   : Septembre 2020

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/functions.inc.ps1
   

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>

enum NASStorageType
{
   Applicative
   Collaborative
}

class NameGeneratorNAS
{
   hidden [NASStorageType] $type
   hidden [Hashtable] $details
   
   <#
		-------------------------------------------------------------------------------------
      BUT : Constructeur de classe pour un volume de type Collaboratif
      
      RET : Instance de l'objet
	#>
   NameGeneratorNAS() { }

   <#
		-------------------------------------------------------------------------------------
		BUT : Initialise les détails pour un volume de type Collaboratif

      IN  : $faculty   -> Nom de la faculté
      IN  : $unitName  -> Nom de l'unité
	#>
   [void] setCollaborativeDetails([string]$faculty, [string]$unit)
   {
      $this.type = [NASStorageType]::Collaborative

      $this.details = @{
         faculty = $faculty.toLower()
         # On reformate le nom d'unité
         unit = ($unit.toLower() -replace "-", "")
      }
   }

   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe pour un volume de type Applicatif

      IN  : $faculty        -> Nom de la faculté
      IN  : $desiredVolName -> nom de volume désiré
	#>
   [void] setApplicativeDetails([string]$faculty, [string]$desiredVolName)
   {
      $this.type = [NASStorageType]::Applicative

      $this.details = @{
         faculty = $faculty.toLower()
         desiredVolName = $desiredVolName.toLower()
      }
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom d'un volume collaboratif (vu qu'il y a le numéro passé en paramètre)

      IN  : $volNumber     -> Numéro du volume
   I  IN  : $isNFSVolume   -> $true|$false pour dire si c'est un Volume accédé en NFS
      
      RET : Le nom du volume
	#>
   [string] getVolName([int]$volNumber, [bool]$isNFSVolume)
   {
      $volName = ("{0}_{1}_{2}_files" -f $this.details.faculty, $this.details.unit, $volNumber)

      if($isNFSVolume)
      {
         $volName = "{0}_nfs" -f $volName
      }

      return $volName
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom d'un volume applicatif

      RET : Le nom du volume
	#>
   [string] getVolName()
   {
      return ("{0}_{1}_app" -f $this.details.faculty, $this.details.desiredVolName)
   }

   
   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la regex à utiliser pour chercher un nom de volume Collaboratif

      IN  : $isNFS   -> pour dire si c'est pour un accès NFS ou pas.

      RET : La regex
	#>
   [string] getCollaborativeVolRegex([bool]$isNFS)
   {
      $regex = ("{0}_{1}_[0-9]_files" -f $this.details.faculty, $this.details.unit)

      if($isNFS)
      {
         $regex = "{0}_nfs" -f $regex
      }

      return $regex
   }
        
}