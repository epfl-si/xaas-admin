<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API de ServiceNow pour 
        faire du End-2-End monitoring pour un service donné à l'instanciation de l'objet

        On fait une classe enfant de SnowAPI car les appels ne sont pas fait avec un compte "générique" 
        qui permettrait d'accéder à tous les services mais il faut par contre s'authentifier spécifiquement
        pour un service...

   AUTEUR : Lucien Chaboudez
   DATE   : Mars 2021

   Sites pour l'état des services:
   Test: https://support-test.epfl.ch/epfl?id=epfl_services_status
   Prod: https://support.epfl.ch/epfl?id=epfl_services_status
#>

# Priorités possibles
enum E2EStatusPriority {
    Outage
    Degradation
    Up
    DescriptionUpdate
}

class E2EAPI: RESTAPICurl
{
    hidden [Array] $serviceList

    <#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server			-> Nom DNS du serveur
        IN  : $serviceList      -> Liste des services. Une liste d'objet avec chacun les entrées suivantes:
                                        .svcId
                                        .user
                                        .password
	#>
	E2EAPI([string]$server, [Array]$serviceList): base($server)
	{
        # Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )
        
        $this.serviceList = $serviceList

        $this.baseUrl = "{0}/api/now/" -f $this.baseUrl

        $this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')
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
        $id = switch($priority)
        {
            Outage { 1 }
            Degradation { 2 }
            Up { 5 }
            DescriptionUpdate { 6 }
        }
        return $id
    }
    
    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
							 Si $null, on ne passe rien.
		IN  : $extraAgrs -> Arguments supplémentaires pouvant être passés à Curl

		RET : Retour de l'appel
	#>
    hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$extraArgs)
    {
        $response = ([RESTAPICurl]$this).callAPI($uri, $method, $body, $extraArgs)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'error')
        {
			Throw ("E2EAPI error: {0}" -f $response.error.message
			)
        }

        return $response
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Initialise le statut du service
        
        IN  : $serviceId            -> ID du service à changer (svcXXXX)
        IN  : $priority			    -> priorité pour laquelle on veut l'ID
        IN  : $shortDescription     -> Description courte
        IN  : $description          -> Description
	#>
    [void] setServiceStatus([string]$serviceId, [E2EStatusPriority]$priority, [string]$shortDescription, [string]$description)
    {
        # Recherche des infos du service
        $serviceInfos = $this.serviceList | Where-Object { $_.svcId -eq $serviceId }

        # Si le service n'existe pas
        if($null -eq $serviceInfos)
        {
            Throw ("Service '{0}' not found in services list" -f $serviceId)
        }

        # Mise à jour des "extra args" pour pouvoir exécuter la requête correctement
        $extraArgs = "-u {0}:{1}" -f $serviceInfos.user, $serviceInfos.password

        $uri = "{0}/import/u_event_api" -f $this.baseUrl

        $replace = @{
            svcId = $serviceId
            priority = $this.getPriorityId($priority)
            shortDescription = $shortDescription
            description = $description
        }

        $body = $this.createObjectFromJSON("e2e-set-service-status.json", $replace)

        $this.callAPI($uri, "POST", $body, $extraArgs) | Out-Null
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Met à jour la description du service
        
        IN  : $serviceId            -> ID du service à changer (svcXXXX)
        IN  : $shortDescription     -> Description courte
        IN  : $description          -> Description
	#>
    [void] updateServiceDescription([string]$serviceId, [string]$shortDescription, [string]$description)
    {
        $this.setServiceStatus($serviceId, [E2EStatusPriority]::DescriptionUpdate, $shortDescription, $description)
    }


}