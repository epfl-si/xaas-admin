<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API de ServiceNow pour 
        faire du End-2-End monitoring pour un service donné à l'instanciation de l'objet

        On fait une classe enfant de SnowAPI car les appels ne sont pas fait avec un compte "générique" 
        qui permettrait d'accéder à tous les services mais il faut par contre s'authentifier spécifiquement
        pour un service...

   AUTEUR : Lucien Chaboudez
   DATE   : Mars 2021
#>

# Priorités possibles
enum E2EStatusPriority {
    Outage
    Degradation
    Up
    DescriptionUpdate
}

class E2EAPI: SnowAPI
{
    hidden [string] $serviceId

    <#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server			-> Nom DNS du serveur
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
        IN  : $serviceId        -> ID du service
	#>
	E2EAPI([string]$server, [string]$username, [string]$password, [string]$serviceId): base($server, $username, $password) 
	{
        # Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )
        
        $this.serviceId = $serviceId.toUpper()
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Initialise le statut d'un service
        
        IN  : $priority			    -> priorité pour laquelle on veut l'ID

        RET : Identifiant numérique de la priorité
            1 : Outage
            2 : Degradation
            5 : Up
            6 : Modification de la Short Description (visible des utilisateurs) 
	#>
    hidden [int] getPriorityId([E2EStatusPriority]$priority)
    {
        return switch($priority)
        {
            Outage { 1 }
            Degradation { 2 }
            Up { 5 }
            DescriptionUpdate { 6 }
        }
    }

    
    <#
	-------------------------------------------------------------------------------------
        BUT : Initialise le statut du service
        
        IN  : $priority			    -> priorité pour laquelle on veut l'ID
        IN  : $shortDescription     -> Description courte
        IN  : $description          -> Description
	#>
    [void] setServiceStatus([E2EStatusPriority]$priority, [string]$shortDescription, [string]$description)
    {
        $uri = "{0}/import/u_event_api" -f $this.baseUrl

        $replace = @{
            svcId = $this.serviceId
            priority = $this.getPriorityId($priority)
            shortDescription = $shortDescription
            description = $description
        }

        $body = $this.createObjectFromJSON("e2e-set-service-status.json", $replace)

        $this.callAPI($uri, "POST", $body) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Met à jour la description du service
        
        IN  : $shortDescription     -> Description courte
        IN  : $description          -> Description
	#>
    [void] updateServiceDescription([string]$shortDescription, [string]$description)
    {
        $this.setServiceStatus([E2EStatusPriority]::DescriptionUpdate, $shortDescription, $description)
    }


}