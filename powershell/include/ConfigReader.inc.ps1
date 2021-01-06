<#
   BUT : Contient une classe permetant d'accéder au fichier de configuration JSON. Elle
         fourni des fonctions permettant d'accéder aux données

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2019

   ----------
   HISTORIQUE DES VERSIONS
   20.08.2019 - 1.0 - Version de base
#>
class ConfigReader
{
   hidden [PSObject]$config
   hidden [string]$JSONfile
   
   <#
	-------------------------------------------------------------------------------------
      BUT : Créer une instance de l'objet 

      IN  : $filename   -> Nom du fichier JSON à charger
	#>
   ConfigReader([string]$filename)
   {
      # Chemin complet jusqu'au fichier à charger
		$this.JSONfile = (Join-Path $global:CONFIG_FOLDER $filename)

		# Si le fichier n'existe pas
		if(-not( Test-Path $this.JSONfile))
		{
			Throw ("Config file not found ! ({0})`nPlease create it from 'sample' file" -f $this.JSONfile)
      }
      
      # Lecture du fichier, suppression des commentaires et transformation en JSON 
      $this.config = ((Get-Content -Path $this.JSONfile -raw) -replace '(?m)\s*//.*?$' -replace '(?ms)/\*.*?\*/') | ConvertFrom-Json

   }


   <#
	-------------------------------------------------------------------------------------
      BUT : Permet de savoir si une propriété d'objet existe
      
      IN  : $object     -> L'objet dans lequel il faut chercher
      IN  : $property   -> Propriété de l'objet dont on veut savoir si elle existe

      RET : $true|$false
	#>
   hidden [bool] propertyExists([PSObject]$object, [string]$property)
   {
      return $property -in $object.PSobject.Properties.name.split([Environment]::NewLine)
   }


   <#
	-------------------------------------------------------------------------------------
      BUT : Renvoie une valeur de configuration pour un élément donné par son nom. Il
            se trouve donc à la racine
      
      IN  : $rootElement  -> Nom de l'élément à la racine

      RET : Valeur demandée
	#>
   [PSObject]getConfigValue([string]$rootElement)
   {
      return $this.getConfigValue(@($rootElement))
   }

   <#
	-------------------------------------------------------------------------------------
      BUT : Renvoie une valeur de configuration pour un élément donné par son chemin
      
      IN  : $pathToVal  -> Tableau avec le chemin jusqu'à la valeur recherchée

      RET : Valeur demandée
	#>
   [PSObject]getConfigValue([Array]$pathToVal)
   {
      $currentElement= $this.config
      $pathDone = @()

      # Parcours des éléments du chemin 
      $pathToVal | ForEach-Object {
         $pathDone += $_

         if(!($this.propertyExists($currentElement, $_)))
         {
            Throw "ConfigReader: Path '{0}' doesn't exists in '{1}'" -f ($pathDone -join ">"), $this.JSONfile
         }
         # On descend d'un niveau
         $currentElement = $currentElement.$_
      }

      # Si on arrive ici, c'est qu'on a trouvé ce qu'on cherchait, on peut le retourner
      return $currentElement
   }

}