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
   
   <#
	-------------------------------------------------------------------------------------
      BUT : Créer une instance de l'objet 
	#>
   ConfigReader()
   {
      # Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:CONFIG_FOLDER "all-config.json")

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("ConfigReader: JSON config file not found ({0})" -f $filepath)
      }
      
      # Lecture du fichier, suppression des commentaires et transformation en JSON 
      $this.config = ((Get-Content -Path $filepath -raw) -replace '(?m)\s*//.*?$' -replace '(?ms)/\*.*?\*/') | ConvertFrom-Json

   }



   <#
	-------------------------------------------------------------------------------------
      BUT : Renvoie une valeur de configuration pour un élément donné
      
      IN  : $scope      -> Scope dans lequel on travaille.
                           Test, Dev, Prod, Global
      IN  : $category   -> Catégorie de la valeur
      IN  : $valueName  -> Nom de la valeur que l'on veut récupérer
	#>
   [String]getConfigValue([string]$scope, [string]$category, [string]$valueName)
   {
      return ""
   }

}