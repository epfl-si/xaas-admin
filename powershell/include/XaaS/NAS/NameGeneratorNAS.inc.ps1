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

# Nombre de digits présents dans les volumes collaboratifs
$global:XAAS_NAS_COL_VOL_NB_DIGITS = 3

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
      IN  : $unitId  -> ID de l'unité
	#>
   [void] setCollaborativeDetails([string]$bgName, [string]$unitId)
   {
      $this.type = [NASStorageType]::Collaborative

      $details = $this.getDetailsFromBGName($bgName)

      $this.details = @{
         faculty = $details.faculty.toLower()
         # On garde le nom de l'unité "original"
         origUnitName = $details.unit.toLower()
         # On reformate le nom d'unité
         unitName = ($details.unit.toLower() -replace "-", "")
         unitId = $unitId
      }
   }

   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe pour un volume de type Applicatif

      IN  : $svcId            -> ID du service ITServices
      IN  : $desiredVolName   -> nom de volume désiré
	#>
   [void] setApplicativeDetails([string]$svcId, [string]$desiredVolName)
   {
      $this.type = [NASStorageType]::Applicative

      $this.details = @{
         svcId = $svcId.toLower()
         desiredVolName = $desiredVolName.toLower()
      }
   }

   
   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le Type d'un volume en fonction de son nom

      IN  : $volName       -> Le nom du volume
      
      RET : Le type de volume
	#>
   hidden [XaaSNASVolType] getVolType($volName)
   {
      # Si collaboratif
      if($volName -match '_files(_nfs)?')
      {
         return [XaaSNASVolType]::col
      }
      elseif($volName -match '_app$')
      {
         return [XaaSNASVolType]::app
      }
      else
      {
         Throw ("Impossible to find Volume Type for '{0}'" -f $volName)
      }
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom d'un volume collaboratif (vu qu'il y a le numéro passé en paramètre)

      IN  : $volNumber     -> Numéro du volume
      IN  : $isNFSVolume   -> $true|$false pour dire si c'est un Volume accédé en NFS
      
      RET : Le nom du volume
	#>
   [string] getVolName([int]$volNumber, [bool]$isNFSVolume)
   {
      # Ajout des zéro nécessaires au début du nom du volume
      $volNum = $volNumber.ToString().PadLeft($global:XAAS_NAS_COL_VOL_NB_DIGITS,"0")
      
      $volName = ("u{0}_{1}_{2}_{3}_files" -f $this.getDetail('unitId'), $this.getDetail('faculty'), $this.getDetail('unitName'), $volNum)

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
      return ("{0}_{1}_app" -f $this.getDetail('svcId'), $this.getDetail('desiredVolName'))
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du share CIFS par défaut pour un volume donné

      IN  : $volName    -> le nom du volume, sous la forme définie par getVolName($volNumber, $isNFSVolume) plus haut

      RET : Le nom du volume
	#>
   [string] getVolDefaultCIFSShareName([string]$volName)
   {
      $shareName = ""
      # En fonction du type du volume
      switch($this.getVolType($volName))
      {
         # Collaboratif
         col
         {
            $dummy, $volNo = [Regex]::Match($volName, ".*?_([0-9]+)_files").Groups | Select-Object -ExpandProperty value

            if($null -eq $volNo)
            {
               Throw ("Impossible to determine volume number for '{0}'" -f $volName)
            }

            $shareName = "{0}-{1}" -f $this.getDetail('origUnitName'), $volNo
         }

         # Applicatif
         app
         {
            $shareName = $volName
         }
      }

      return $shareName
      
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le chemin de montage d'un volume en fonction de son protocol

      IN  : $volName       -> Le nom du volume
      IN  : $svm           -> Nom de la SVM
      IN  : $protocol      -> Protocol d'accès. Tel que défini dans le fichier de la classe
                              [NetAppAPI] 

      RET : Le chemin de montage
	#>
   [string] getVolMountPath([string]$volName, [string]$svm, [NetAppProtocol]$protocol)
   {
      $mountPath = switch($protocol)
      {
         cifs
         {
            "\\{0}\{1}" -f $svm, $this.getVolDefaultCIFSShareName($volName)
         }

         nfs3
         {
            "{0}:/{1}" -f $svm, $volName
         }

         default
         {
            Throw ("Protcol '{0}' not handled" -f $protocol.toString())
         }
      }

      return $mountPath
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le junction path (point de montage interne à NetApp) pour un volume

      IN  : $forVolumeName -> Nom du volume pour lequel on veut le nom de l'export policy

      RET : Le chemin du junction path
	#>
   [string] getJunctionPath([string]$forVolumeName)
   {
      return ("/{0}" -f $forVolumeName)
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
   [string] getCollaborativeVolDetailedRegex([bool]$isNFS)
   {
      $regex = ("u{0}_{1}_[a-z]+_[0-9]{{{2},{2}}}_files" -f $this.getDetail('unitId'), $this.getDetail('faculty'), $global:XAAS_NAS_COL_VOL_NB_DIGITS)

      if($isNFS)
      {
         $regex = "{0}_nfs" -f $regex
      }

      return ("^{0}$" -f $regex)
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le type d'un volume en fonction de son nom

      IN  : $volName -> Nom du volume

      RET : Type du volume
	#>
   [XaaSNASVolType] getVolumeType([string]$volName)
   {
      # Collaboratif
      if([Regex]::Match($volName, '^(.*?)_files(_nfs)?$').Success)
      {
         return [XaaSNASVolType]::col
      }

      # Applicatif¨
      if([Regex]::Match($volName, '^(.*?)_app$'))
      {
         return [XaaSNASVolType]::app
      }
      
      Throw ("Impossible to determine volume type for volume name '{0}'" -f $volName)
   }
        
}