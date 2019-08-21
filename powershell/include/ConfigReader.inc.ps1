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
      BUT : Renvoie une valeur de configuration pour un élément donné
      
      IN  : $scope      -> Scope dans lequel on travaille.
                           peut être: Test, Dev, Prod, ...
      IN  : $element    -> Nom de la valeur que l'on veut récupérer
	#>
   [String]getConfigValue([string]$scope, [string]$element)
   {
      # On commence par contrôler que le scope existe 
      if(!($this.propertyExists($this.config, $scope)))
      {
         Throw "ConfigReader: Scope '{0}' doesn't exists in '{1}'" -f $scope, $this.JSONfile
      }

      # On regarde ensuite si l'élément demandé dans le scope exist aussi.
      if(!($this.propertyExists($this.config.$scope, $element)))
      {
         Throw "ConfigReader: Element '{0}' for scope '{1}' doesn't exists in '{2}'" -f $element, $scope, $this.JSONfile
      }

      # Retour de ce qui est demandé
      return $this.config.$scope.$element
   }

   <#
	-------------------------------------------------------------------------------------
      BUT : Renvoie une valeur de configuration pour un élément donné
      
      IN  : $scope      -> Scope dans lequel on travaille.
                           peut être: Test, Dev, Prod, ...
      IN  : $element    -> Nom de l'élément dans lequel se trouve le sous-élément dont on veut la valeur
      IN  : $subElement -> Nom de l'élément dont on veut la valeur
	#>
   [String]getConfigValue([string]$scope, [string]$element, [string]$subElement)
   {
      # On commence par contrôler que le scope existe 
      if(!($this.propertyExists($this.config, $scope)))
      {
         Throw "ConfigReader: Scope '{0}' doesn't exists in '{1}'" -f $scope, $this.JSONfile
      }

      # On regarde ensuite si l'élément demandé dans le scope exist aussi.
      if(!($this.propertyExists($this.config.$scope, $element)))
      {
         Throw "ConfigReader: Element '{0}' for scope '{1}' doesn't exists in '{2}'" -f $element, $scope, $this.JSONfile
      }

      # On regarde ensuite si le sous-élément demandé dans l'élément exist aussi.
      if(!($this.propertyExists($this.config.$scope.$element, $subElement)))
      {
         Throw "ConfigReader: Sub element '{0}' for element '{1} and scope '{2}' doesn't exists in '{3}'" -f $subElement, $element, $scope, $this.JSONfile
      }

      # Retour de ce qui est demandé
      return $this.config.$scope.$element.$subElement
   }

}