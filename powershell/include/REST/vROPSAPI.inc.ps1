<#
   BUT : Contient les fonctions donnant accès à l'API vROPS

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021

	Des exemples d'utilsiation des API via Postman peuvent être trouvés ici :
    https://github.com/vmware-samples/vrops-restapi-samples


	Documentation:
	https://vsissp-vrops-t-01.epfl.ch/suite-api 


#>

$global:VROPS_RESOURCE_PROPERTY_BASE_PATH = "EPFL|"

class vROPSAPI: RESTAPICurl
{
    
	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $localUser	    -> Nom d'utilisateur (doit être local))
		IN  : $password			-> Mot de passe
	#>
	vROPSAPI([string] $server, [string] $localUser, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')

		$replace = @{username = $localUser
					password = $password}

		$body = $this.createObjectFromJSON("vrops-user-credentials.json", $replace)

        $this.baseUrl = "{0}/suite-api/api" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $uri = "{0}/auth/token/acquire" -f $this.baseUrl
        $token = ($this.callAPI($uri, "POST", $body)).token

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("vRealizeOpsToken {0}" -f $token))

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Surcharge la fonction qui fait l'appel à l'API pour simplement ajouter un
				check des erreurs

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel

	#>	
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		$response = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'message')
        {
			Throw ("vROPSAPI error: {0}" -f $response.message
			)
        }

        return $response
    }

    
    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Resources

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau de Resources
	#>
    hidden [Array] getResourceListQuery([string] $queryParams)
	{
		$uri = "{0}/resources?pageSize=9999" -f $this.baseUrl

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return ($this.callAPI($uri, "Get", $null)).resourceList

    }
    hidden [Array] getResourceListQuery()
	{
		return $this.getResourceListQuery("")
	}
    

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Resources

        IN  : $resourceKind     -> Le type de resource tel qu'identifié dans vROPS

		RET : Tableau de resource
	#>
	[Array] getResourceList([string]$resourceKind)
	{
		return $this.getResourceListQuery(("resourceKind={0}" -f $resourceKind))
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une ressource donnée par son nom et son type

        IN  : $resourceKind     -> Le type de resource tel qu'identifié dans vROPS
        IN  : $resourceName     -> Le nom de la ressource

        RET : Objet avec la resource
            $null si pas trouvé
	#>
	[PSObject] getResource([string]$resourceKind, [string]$resourceName)
	{
        $res = $this.getResourceListQuery(("resourceKind={0}&name={1}" -f $resourceKind, $resourceName))
        
        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une ressource donnée par son ID

        IN  : $resourceId     -> ID de la ressource

        RET : Objet avec la ressource
            $null si pas trouvé
	#>
	[PSObject] getResourceById([string]$resourceId)
	{
        $uri = "{0}/resources/{1}" -f $this.baseUrl, $resourceId

        return $this.callAPI($uri, "GET", $null)
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
										RESOURCE PROPERTIES
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des property pour une resource

        IN  : $resource         -> Objet représentant la ressource

		RET : Tableau avec la liste
	#>
    [Array] getResourcePropertyList([PSObject]$resource)
    {
        $uri = "{0}/resources/{1}/properties" -f $this.baseUrl, $resource.identifier

        return ($this.callAPI($uri, "GET", $null)).property
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Permet de savoir si une property existe sur une resource

        IN  : $resource         -> Objet représentant la ressource
        IN  : $propertyPath     -> Chemin jusqu'à la propriété, sous la forme:
                                    <niveau1>[|<niveau2>[|<niveau3>...]]|<propertyName>
									Ce chemin sera ajouté à la suite de $global:VROPS_RESOURCE_PROPERTY_BASE_PATH

		RET : $true|$false
	#>
	[bool] resourcePropertyExists([PSObject]$resource, [string]$propertyPath)
	{
		return $null -ne ($this.getResourcePropertyList($resource) | Where-Object { $_.name -eq ("{0}{1}" -f $global:VROPS_RESOURCE_PROPERTY_BASE_PATH, $propertyPath) })
	}


    <#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une propriété à une ressource

        IN  : $resource         -> Objet représentant la ressource
        IN  : $propertyPath     -> Chemin jusqu'à la propriété, sous la forme d'un tableau avec la liste
									des dossiers jusqu'à la propriété à ajouter
									Ce chemin sera ajouté à la suite de $global:VROPS_RESOURCE_PROPERTY_BASE_PATH
        IN  : $propertyValue    -> Valeur de la propriété

        RET : Objet avec la ressource modifiée
	#>
    [PSObject] addResourceProperty([PSObject]$resource, [Array]$propertyPath, [string]$propertyValue)
    {
        $uri = "{0}/resources/{1}/properties" -f $this.baseUrl, $resource.identifier
        # Valeur à mettre pour la configuration du BG
		$replace = @{
            propertyPath = ("{0}{1}" -f $global:VROPS_RESOURCE_PROPERTY_BASE_PATH, ($propertyPath -join "|"))
            timestamp = @(((getUnixTimestamp) * 1000), $true)
            value = $propertyValue
        }

        $body = $this.createObjectFromJSON("vrops-resource-property.json", $replace)

        $this.callAPI($uri, "POST", $body) | Out-Null

        return $this.getResourceById($resource.identifier)
    }
    



    



}