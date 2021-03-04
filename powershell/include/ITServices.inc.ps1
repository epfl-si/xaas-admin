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

        $itServiceJSONFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "itservices.json"))
		if(!(Test-Path $itServiceJSONFile ))
		{
			Throw ("JSON file with ITServices not found ! ({0})" -f $itServiceJSONFile)
		}

		# Chargement des données depuis le fichier 
		$this.serviceList = loadFromCommentedJSON -jsonFile $itServiceJSONFile
		
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

		RET : Tableau avec la liste des services
	#>
    [Array] getServiceList([string]$forTargetEnv)
    {
        # On contrôle que le shortname du service n'existe pas déjà pour l'environnement courant
        $svcIDList = @()
        $svcShortNameList = @()
        Foreach($service in $this.serviceList.$forTargetEnv)
        {
            if($svcIDList -notcontains $service.snowId)
            {
                $svcIDList += $service.snowId
            }
            else
            {
                Throw ("Duplicate ITServices snowId found ({0}) for '{1}' environment!" -f $service.snowId, $forTargetEnv)
            }

            if($svcShortNameList -notcontains $service.shortName)
            {
                $svcShortNameList += $service.shortName
            }
            else
            {
                Throw ("Duplicate ITServices short name found ({0}) for '{1}' environment!" -f $service.shortName, $forTargetEnv)
            }
        }

        return $this.serviceList.$forTargetEnv
    }

}