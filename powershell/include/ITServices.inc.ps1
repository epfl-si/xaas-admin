<#
   BUT : Classe permettant de gérer la liste des Service IT qui sont définis dans le fichier JSON itservices.json

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2020

   Prérequis:

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class ITServices
{
    hidden [PSObject] $serviceList


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

		RET : Instance de l'objet
	#>
    ITServices()
    {

        $itServiceJSONFile = ([IO.Path]::Combine($global:DATA_FOLDER, "itservices.json"))
		if(!(Test-Path $itServiceJSONFile ))
		{
			Throw ("JSON file with ITServices not found ! ({0})" -f $itServiceJSONFile)
		}

		# Chargement des données depuis le fichier 
		$this.serviceList = ((Get-Content -Path $itServiceJSONFile) -join "`n") | ConvertFrom-Json
		
		# Si on rencontre une erreur, 
		if(($this.serviceList -eq $false) -or ($null -eq $this.serviceList))
		{
			Throw ("Error getting Services list in file '{0}'" -f $itServiceJSONFile)
        }    
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des services pour un environnement donné
        
        IN  : $forTargetEnv    -> Nom de l'environnement pour lequel on veut la liste des services

		RET : Instance de l'objet
	#>
    [Array] getServiceList([string]$forTargetEnv)
    {
        return $this.serviceList.$forTargetEnv
    }

}