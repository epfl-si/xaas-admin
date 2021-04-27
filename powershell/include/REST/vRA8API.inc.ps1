<#
   BUT : Contient les fonctions donnant accès à l'API vRA8

   AUTEUR : Lucien Chaboudez
   DATE   : Avril 2021


	REMARQUES :
	- Il semblerait que le fait de faire un update d'élément sans que rien ne change
	mette un verrouillage sur l'élément... donc avant de faire un update, il faut
	regarder si ce qu'on va changer est bien différent ou pas.

	Documentation:
	Une description des fichiers JSON utilisés peut être trouvée sur Confluence.
	https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-vRA

	https://vsissp-vra8-t-02.epfl.ch/automation-ui/api-docs/


#>
class vRA8API: RESTAPICurl
{
	hidden [string]$token
	hidden [Hashtable]$projectCustomIdMappingCache


    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $tenant			-> Nom du tenant auquel se connecter
		IN  : $user         	-> Nom d'utilisateur (sans le nom du domaine)
		IN  : $password			-> Mot de passe

        https://vra4u.com/2020/06/26/vra-8-1-quick-tip-api-authentication/
	#>
	vRA8API([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{

		# Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )

		# Cache pour le mapping entre l'ID custom d'un BG et celui-ci
		$this.projectCustomIdMappingCache = $null

		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')

        # --- Etape 1 de l'authentification
		$replace = @{username = $user
						 password = $password}

		$body = $this.createObjectFromJSON("vra-auth-step1.json", $replace)

		$uri = "{0}/csp/gateway/am/api/login?access_token" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

        $refreshToken = ($this.callAPI($uri, "POST", $body)).refresh_token
        

        # --- Etape 2 de l'authentification
        $replace = @{refreshToken = $refreshToken }

        $body = $this.createObjectFromJSON("vra-auth-step2.json", $replace)

        # https://code.vmware.com/apis/978#/Login/retrieveAuthToken
        $uri = "{0}/iaas/api/login" -f $this.baseUrl

        $this.token = ($this.callAPI($uri, "POST", $body)).token

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Bearer {0}" -f $this.token))

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
	hidden [PSCustomObject] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		$response = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'errors')
        {
			Throw ("vRA8API error: {0}" -f $response.serverMessage
			)
        }

        return $response
	}


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une liste d'objets (type défini en fonction du paramètre $uri) et qui 
                correspondent à des critères de recherche donnés.

		IN  : $uri		    -> URL à appeler
		IN  : $queryParams  -> paramètres à ajouter à la requête. Peut être vide ""
	#>	
    hidden [Array] getObjectListQuery([string]$uri, [string]$queryParams)
    {
        $uri = "{0}{1}/?size=9999&page=0" -f $this.baseUrl, $uri

        if($queryParams -ne "")
        {
            $uri = "{0}&{1}" -f $uri, $queryParams
        }

		return ($this.callAPI($uri, "Get", $null)).content
    }

    <#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                    PROJECTS
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
    #>


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des projets selon des critères passés

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des projets
	#>
    hidden [Array] getProjectListQuery()
    {
        return $this.getProjectListQuery("")
    }
    hidden [Array] getProjectListQuery([string]$queryParams)
    {
        return $this.getObjectListQuery("/iaas/api/projects", $queryParams)
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des projets

		RET : La liste des projets
	#>
    [Array] getProjectList()
    {
        return $this.getProjectListQuery()
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un projet donné par son nom

        IN  : $name     -> Nom du projet

		RET : Objet représentant le projet
                $null si pas trouvé
	#>
    [PSCustomObject] getProjectByName([string]$name)
    {
        $res = $this.getProjectListQuery(("`$filter=name eq '{0}'" -f $name))

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un projet donné par son ID custom

        IN  : $customId     -> ID custom du projet

		RET : Objet représentant le projet
                $null si pas trouvé
	#>
    [PSCustomObject] getProjectByCustomId([string] $customId)
	{
		return $this.getProjectByCustomId($customId, $false)
	}
	[PSCustomObject] getProjectByCustomId([string] $customId, [bool]$useCache)
	{
		$list = @()
		# Si on doit utiliser le cache ET qu'il est vide
		# OU 
		# On ne doit pas utiliser le cache
		if( ($useCache -and ($null -eq $this.projectCustomIdMappingCache)) -or !$useCache)
		{
			$list = $this.getProjectListQuery()

			if($list.Count -eq 0){return $null}
		}
		
		# Si on doit utiliser le cache
		if($useCache)
		{
			# Si on n'a pas encore initilisé le cache, on le fait, ce qui va prendre quelques secondes
			if($null -eq $this.projectCustomIdMappingCache)
			{
				$this.projectCustomIdMappingCache = @{}

                ForEach($project in $list)
				{
					$projectId = getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID
					# Si on est bien sur un BG "correcte", qui a donc un ID
					if($null -ne $projectId)
					{
						$this.projectCustomIdMappingCache.add($projectId, $project)
					}
				}        
			}# FIN Si on n'a pas initialisé le cache

			# Arrivé ici, le cache est initialisé donc on peut rechercher avec l'Id demandé
			return $this.projectCustomIdMappingCache.item($customId)
		}
		else # On ne veut pas utiliser le cache (donc ça va prendre vraiment du temps!)
		{
			# Retour en cherchant avec le custom ID
			return $list| Where-Object { 
                # Check si la custom property existe
                (($_.customProperties | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -contains $global:VRA_CUSTOM_PROP_EPFL_BG_ID) `
                -and `
                # Check de la valeur de la custom property
                ($_.customProperties | Select-Object -ExpandProperty ch.epfl.vra.bg.id ) -eq $customId
            }
		}
	
	}

    
    <#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un BG

		IN  : $name					-> Nom du BG à ajouter
		IN  : $desc					-> Description du BG
		IN  : $vmNamingTemplate     -> Chaîne de caractères représentant le template pour le nommage des VM
		IN  : $customProperties		-> Dictionnaire avec les propriétés custom à ajouter
        IN  : $zoneList             -> Liste des objets représentants les Zones à mettre pour le projet
        IN  : $adminGroups          -> Liste des groupes AD à mettre comme Admins
        IN  : $userGroups           -> Liste des groupes AD à mettre comme Users

		RET : Objet contenant le Projet
	#>
	[PSCustomObject] addProject([string]$name, [string]$desc, [string]$vmNamingTemplate, [Hashtable] $customProperties, [Array]$zoneList, [Array]$adminGroups, [Array]$userGroups)
	{
		$uri = "{0}/iaas/api/projects" -f $this.baseUrl

		# Valeur à mettre pour la configuration du BG
		$replace = @{
            name = $name
            description = $desc
        }

		# Si on a passé un template de nommage
		if($vmNamingTemplate -ne "")						 
		{
			$replace.vmNamingTemplate = $vmNamingTemplate
		}
		else 
		{
			$replace.vmNamingTemplate = $null
		}

		$body = $this.createObjectFromJSON("vra-project.json", $replace)

		# Ajout des éventuelles custom properties
		$customProperties.Keys | ForEach-Object {
            $body.customProperties | Add-Member -NotePropertyName $_ -NotePropertyValue $customProperties.Item($_)
		}

        # Ajout des admins
        $adminGroups | ForEach-Object {
            $body.administrators += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $_})
        }

        # Ajout des Utilisateurs
        $userGroups | ForEach-Object {
            $body.members += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $_})
        }

        # Ajout des Zones
        $zoneList | ForEach-Object {
            $body.zoneAssignmentConfigurations += $this.createObjectFromJSON("vra-project-zone.json", @{ zoneId = $_.id})
        }

		# Création du Projet
		$this.callAPI($uri, "Post", $body) | Out-Null
		
		# Recherche et retour du Projet
		# On utilise $body.name et pas simplement $name dans le cas où il y aurait un préfixe ou suffixe de nom déjà hard-codé dans 
		# le fichier JSON template
		return $this.getProjectByName($body.name)
	}


    <#
		-------------------------------------------------------------------------------------
		BUT : Efface un projet

        IN  : $project      -> Objet représentant le projet à effacer
	#>
    [void] deleteProject([PSCustomObject] $project)
    {
        $uri = "{0}/iaas/api/projects/{1}" -f $this.baseUrl, $project.id

		($this.callAPI($uri, "DELETE", $null)).content | Out-Null
    }


    <#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                    ZONES
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
    #>


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Zones selon des critères passés

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des Zones
	#>
    hidden [Array] getZoneListQuery()
    {
        return $this.getZoneListQuery("")
    }
    hidden [Array] getZoneListQuery([string]$queryParams)
    {
        return $this.getObjectListQuery("/iaas/api/zones", $queryParams)
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Zones

		RET : La liste des Zones
	#>
    [Array] getZoneList()
    {
        return $this.getZoneListQuery()
    }


}