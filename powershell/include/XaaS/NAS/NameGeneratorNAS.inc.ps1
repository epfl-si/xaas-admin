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

class NameGeneratorNAS: NameGeneratorBase
{
   hidden [NASStorageType] $type
   
   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $env      -> Environnement sur lequel on travaille
                           $TARGET_ENV_DEV
                           $TARGET_ENV_TEST
                           $TARGET_ENV_PROD
        IN  : $tenant   -> Tenant sur lequel on travaille
                           $VRA_TENANT_DEFAULT
                           $VRA_TENANT_EPFL
                           $VRA_TENANT_ITSERVICES

		RET : Instance de l'objet
	#>
   NameGeneratorNAS([string]$env, [string]$tenant): base($env, $tenant)
   {
   }

   <#
		-------------------------------------------------------------------------------------
		BUT : Initialise les détails pour un volume de type Collaboratif

      IN  : $bgName  -> Nom du BG
	#>
   [void] setCollaborativeDetails([string]$bgName)
   {
      $this.type = [NASStorageType]::Collaborative

      $details = $this.getDetailsFromBGName($bgName)

      $this.details = @{
         faculty = $details.faculty.toLower()
         # On reformate le nom d'unité
         unit = ($details.unit.toLower() -replace "-", "")
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
		BUT : Renvoie le nom d'un volume (dans ce cas c'est très probablement applicatif)

      RET : Le nom du volume
	#>
   [string] getVolName()
   {
      return ("{0}_{1}_app" -f $this.details.faculty, $this.details.desiredVolName)
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le chemin de montage d'un volume en fonction de son protocol

      IN  : $volName       -> Le nom du volume
      IN  : $svm           -> Nom de la SVM
      IN  : $protocol      -> Protocol d'accès
                              voir dans include/XaaS/NAS/define.inc.ps1
                              $global:ACCESS_TYPE_*

      RET : Le chemin de montage
	#>
   [string] getVolMountPath([string]$volName, [string]$svm, [string]$protocol)
   {
      $mountPath = switch($protocol)
      {
         $global:ACCESS_TYPE_CIFS
         {
            "\\{0}\{1}" -f $svm, $volName
         }

         $global:ACCESS_TYPE_NFS3
         {
            "{0}:/{1}" -f $svm, $volName
         }

         default
         {
            Throw ("Protcol '{0}' not handled" -f $protocol)
         }
      }

      return $mountPath
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom de l'export policy à utiliser pour le volume

      IN  : $forVolumeName -> Nom du volume pour lequel on veut le nom de l'export policy

      RET : Le nom de l'export policy
	#>
   [string] getExportPolicyName([string]$forVolumeName)
   {
      return $forVolumeName
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