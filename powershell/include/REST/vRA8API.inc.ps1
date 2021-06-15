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
        if(objectPropertyExists -obj $response -propertyName 'errorCode')
        {
			Throw ("vRA8API error: {0}" -f $response.message)
        }

		# Si une erreur a été renvoyée (vu qu'on peut aussi l'avoir dans un autre champ...)
        if(objectPropertyExists -obj $response -propertyName 'error')
        {
			Throw ("vRA8API error: {0}" -f $response.error)
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

		$res = ($this.callAPI($uri, "Get", $null))

		# Ces burnasses de développeurs vRA ne sont pas cohérents et parfois le résultat est dans "content" 
		# et parfois il n'y a pas de "content", c'est à la racine... (les cons...)
		if(objectPropertyExists -obj $res -propertyName "content")
		{
			return $res.content
		}
		return $res
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un objet simplement donné par son URI

        IN  : $uri     -> URI de l'objet à renvoyer

		RET : Objet demandé
                $null si pas trouvé
	#>
    hidden [PSCustomObject] getObject([string]$uri)
    {
		$uri = "{0}{1}" -f $this.baseUrl, $uri
        $res = ($this.callAPI($uri, "Get", $null)).content

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
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
		BUT : Renvoie la liste des projets d'un type donné

		IN  : $type	-> Le type dont les projets doivent êtres

		RET : La liste des projets correspondant au type demandé
	#>
    [Array] getProjectList([ProjectType]$type)
    {
		# Retour des projets dont la custom property correspond à ce qui est demandé niveau "type"
        return @($this.getProjectListQuery() | Where-Object { 
				(objectPropertyExists -obj $_.customProperties -propertyName $global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE) -and `
				($_.customProperties.($global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE) -eq $type.toString())
			})
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un projet donné par son nom

        IN  : $name     -> Nom du projet

		RET : Objet représentant le projet
                $null si pas trouvé
	#>
    [PSCustomObject] getProject([string]$name)
    {
        return $this.getObject(("/iaas/api/projects/?`$filter=name eq '{0}'" -f $name))
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
					$projectId = getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID
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
                (($_.customProperties | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name) -contains $global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID) `
                -and `
                # Check de la valeur de la custom property
                ($_.customProperties | Select-Object -ExpandProperty $global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID ) -eq $customId
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
        ForEach($group in $adminGroups)
		{
            $body.administrators += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $group})
        }

        # Ajout des Utilisateurs
        ForEach($group in $userGroups)
		{
            $body.members += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $group})
        }

        # Ajout des Zones
        ForEach($zone in $zoneList)
		{
            $body.zoneAssignmentConfigurations += $this.createObjectFromJSON("vra-project-zone.json", @{ zoneId = $zone.id})
        }

		# Création du Projet
		$this.callAPI($uri, "Post", $body) | Out-Null
		
		# Recherche et retour du Projet
		# On utilise $body.name et pas simplement $name dans le cas où il y aurait un préfixe ou suffixe de nom déjà hard-codé dans 
		# le fichier JSON template
		return $this.getProject($body.name)
	}


    <#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un Projet.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $project				-> Objet du Projet à mettre à jour
		IN  : $newName				-> (optionnel -> "") Nouveau nom
		IN  : $newDesc				-> (optionnel -> "") Nouvelle description
		IN  : $vmNamingTemplate  	-> (optionnel -> "") ID du prefix de machine à utiliser
		IN  : $customProperties		-> (optionnel -> $null) La liste des "custom properties" (et leur valeur) à mettre à
									   jour ou à ajouter. On n'a pas prévu de pouvoir supprimer des custom property
        IN  : $zoneList             -> Liste des objets représentants les Zones à mettre pour le projet
                                        $null si rien besoin de changer
        IN  : $adminGroups          -> Liste des groupes AD à mettre comme Admins
                                        $null si rien besoin de changer
        IN  : $userGroups           -> Liste des groupes AD à mettre comme Users
                                        $null si rien besoin de changer

		RET : Objet contenant le Projet mis à jour
	#>
	[PSCustomObject] updateProject([PSCustomObject]$project, [string] $newName, [string] $newDesc, [string]$vmNamingTemplate, [Hashtable]$customProperties)
	{
		return $this.updateProject($project, $newName, $newDesc, $vmNamingTemplate, $customProperties, $null, $null, $null)
	}
	[PSCustomObject] updateProject([PSCustomObject]$project, [string] $newName, [string] $newDesc, [string]$vmNamingTemplate, [Hashtable]$customProperties, [Array]$zoneList, [Array]$adminGroups, [Array]$userGroups)
	{
		$uri = "{0}/iaas/api/projects/{1}" -f $this.baseUrl, $project.id

		$updateNeeded = $false

		# S'il faut mettre le nom à jour,
		if(($newName -ne "") -and ($project.name -ne $newName))
		{
			$project.name = $newName
			$updateNeeded = $true
		}

		# S'il faut mettre la description à jour,
		if(($newDesc -ne "") -and ($project.description -ne $newDesc))
		{
			$project.description = $newDesc
			$updateNeeded = $true
		}

		if(($vmNamingTemplate -ne "") -and ($project.machineNamingTemplate -ne $vmNamingTemplate))
		{
			$project.machineNamingTemplate = $vmNamingTemplate
			$updateNeeded = $true
		}

		# S'il faut mettre à jour une ou plusieurs "custom properties"
		if($null -ne $customProperties)
		{

			# Parcour des custom properties à mettre à jour,
			$customProperties.Keys | ForEach-Object {

                $propValue = getProjectCustomPropValue -project $project -customPropName $_
				# Si une entrée a été trouvée
				if($null -ne $propValue)
				{
                    # Si la valeur a changé, 
                    if($propValue -ne $customProperties.Item($_))
                    {
                        # Mise à jour de la valeur
                        $project.customProperties.($_) = $customProperties.Item($_)
                        $updateNeeded = $true
                    }
                    
				}
				else # Aucune entrée n'a été trouvée
				{
					# Ajout des infos avec le template présent dans le fichier JSON
                    $project.customProperties | Add-Member -NotePropertyName $_ -NotePropertyValue $customProperties.Item($_)
                    $updateNeeded = $true
				}

			} # FIN BOUCLE de parcours des "custom properties" à mettre à jour

		}

        # Si on doit mettre à jour les zones
        if($null -ne $zoneList)
        {
            # On commence par vider la liste
            $project.zones = @()

            # Ajout des Zones
            $zoneList | ForEach-Object {
                $project.zones += $this.createObjectFromJSON("vra-project-zone.json", @{ zoneId = $_.id})
            }
            $updateNeeded = $true
        }

        # SI on doit mettre à jour les admins
        if($null -ne $adminGroups)
        {
            $project.administrators = @()

            # Ajout des admins
            $adminGroups | ForEach-Object {
                $project.administrators += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $_})
            }
            $updateNeeded = $true
        }

        # Si on doit mettre à jour les utilisateurs
        if($null -ne $userGroups)
        {
            $project.members = @()

            # Ajout des Utilisateurs
            $userGroups | ForEach-Object {
                $project.members += $this.createObjectFromJSON("vra-project-right-group.json", @{ groupShortName = $_})
            }
            $updateNeeded = $true
        }


		# Si on n'a pas besoin d'update quoi que ce soit, on ne le fait pas, sinon on risque de générer une erreur "(400) Bad Request" dans le cas où rien 
		# n'a été changé (ouais, c'est con mais c'est comme ça que vRA réagit... )
		if($updateNeeded -eq $false)
		{
			return $project
		}

		# Mise à jour des informations
		$this.callAPI($uri, "PATCH", $project) | Out-Null
		
		# On recherche l'objet mis à jour
		return $this.getProject($project.name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les custom properties d'un projet

        IN  : $project      	-> Objet représentant le projet à mettre à jour
		IN  : $customProperties	-> Tableau associatif avec les custom properties à mettre à jour
	#>
	[PSCustomObject] updateProjectCustomProperties([PSCustomObject]$project, [Hashtable]$customProperties)
	{
		return $this.updateProject($project, "", "", "", $customProperties, $null, $null, $null)
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
		BUT : Renvoie la liste des Cloud Zones selon des critères passés

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des Cloud Zones
	#>
    hidden [Array] getCloudZoneListQuery()
    {
        return $this.getCloudZoneListQuery("")
    }
    hidden [Array] getCloudZoneListQuery([string]$queryParams)
    {
        return $this.getObjectListQuery("/iaas/api/zones", $queryParams)
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Cloud Zones

		RET : La liste des Cloud Zones
	#>
    [Array] getCloudZoneList()
    {
        return $this.getCloudZoneListQuery()
    }


    <#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                	ENTITLEMENTS
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
    #>
	
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des entitlements d'un projet (peuvent être trouvés dans "Service Broker > Content & Policies > Content Sharing")
				Cela représente en fait la liste des projets contenant des CloudTemplates partageables et qui sont
				disponibles pour le projet passé en paramètre

        IN  : $project 	-> objet représentant le projet pour lequel on veut les entitlements

		RET : La liste des entitlements
	#>
    [Array] getProjectEntitlementList([PSCustomObject]$project)
    {
        return $this.getObjectListQuery("/catalog/api/admin/entitlements", ("projectId={0}" -f $project.id) )
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un entitlement de projet donné par son nom

        IN  : $project 	-> objet représentant le projet pour lequel on veut les entitlements
		IN  : $name		-> nom de l'entitlement recherché

		RET : Entitlement 
				$null si pas trouvé
	#>
    [PSCustomObject] getProjectEntitlement([PSCustomObject]$project, [string]$name)
    {
        $res = @($this.getProjectEntitlementList($project) | Where-Object { $_.definition.name -eq $name})

		if($res.count -eq 0)
		{
			return $null
		}
		return $res[0]
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un Entitlement

		IN  : $name				-> Nom de l'entitlement
		IN  : $description		-> Description de l'entitlement
		IN  : $contentSource	-> Objet représentant le Content Source qui référence le
									projet "Catalogue" qui contient les items de catalog 
									que l'on veut mettre à dispo pour le projet $project
		IN  : $project			-> Objet représentant le projet dans lequel on veut mettre à
									disposition les items qui se trouve dans le projet
									catalogue $catalogProject	

		RET : L'entitlement ajouté
	#>
    [PSCustomObject] addEntitlement([PSCustomObject]$contentSource, [PSCustomObject]$project)
    {
		$uri = "{0}/catalog/api/admin/entitlements" -f $this.baseUrl

		$replace = @{
			name = $contentSource.name # On peut mettre ce qu'on veut, c'est toujours l'équivalent de contentSource.name qui sera repris donc...
            contentSourceId = $contentSource.id
			projectId = $project.id
        }

		$body = $this.createObjectFromJSON("vra-content-sharing.json", $replace)

		# Création du Content Source et retour
		return $this.callAPI($uri, "Post", $body)
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Efface un Entitlement

		IN  : $entitlement	-> objet représentant l'Entitlement à effacer
	#>
	[void] deleteEntitlement([PSCustomObject]$entitlement)
	{
		$uri = "{0}/catalog/api/admin/entitlements/{1}" -f $this.baseUrl, $entitlement.id

		# Création de l'entitlement et retour
		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}

	<#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                CATALOG ITEMS
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
		FIXME: Pas forcément besoin de ces éléments. A priori on peut tout faire avec "content sources" en fait  (quelques lignes plus bas) 
    #>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des catalog items selon des critères passés

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des catalog items
	#>
    hidden [Array] getCatalogItemListQuery()
    {
        return $this.getCatalogItemListQuery("")
    }
    hidden [Array] getCatalogItemListQuery([string]$queryParams)
    {
        return $this.getObjectListQuery("/catalog/api/items", $queryParams)
    }

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Catalog Items disponibles

		RET : La liste des catalog items
	#>
    [Array] getCatalogItemList()
    {
        return $this.getCatalogItemListQuery()
    }


	<#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                CONTENT SOURCE
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
    #>


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des content sources selon des critères passés. Dans la GUI Web, il peuvent 
				être trouvé dans "Service Broker > Content & Policies > Content Sources"

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des Content Sources
	#>
    hidden [Array] getContentSourcesListQuery()
    {
        return $this.getContentSourcesListQuery("")
    }
    hidden [Array] getContentSourcesListQuery([string]$queryParams)
    {
        return $this.getObjectListQuery("/catalog/api/admin/sources", $queryParams)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Content Sources

		RET : La liste des Content Sources
	#>
    [Array] getContentSourcesList()
    {
        return $this.getContentSourcesListQuery()
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Content Sources pour un type de catalogue donné

		IN  : $catalogPrivacy	-> Le niveau de confidentialité du catalogue (Public ou privé)

		RET : La liste des Content Sources
	#>
    [Array] getContentSourcesList([CatalogProjectPrivacy]$catalogPrivacy)
    {
        return $this.getContentSourcesListQuery() | Where-Object { $_.name -match (".+({0})" -f $catalogPrivacy.toString())}
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un Content Source donné par son nom

		IN  : $name		-> Le nom du Content Source

		RET : La liste des Content Sources
	#>
    [PSCustomObject] getContentSource([string]$name)
    {
		return $this.getContentSourcesList() | Where-Object { $_.name -eq $name }

		# FIXME: On pourra utiliser la ligne suivante le jour où VMware aura corrigé le bug de l'API
		# return $this.getObject(("/catalog/api/admin/sources/?`$filter=name eq '{0}'" -f $name))
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajout un Content Source

		IN  : $name				-> Le nom du Content Source
		IN  : $catalogProject	-> Objet représentant le projet content les items de catalog 
									que l'on veut partager dans le Content Source

		RET : Le content source ajouté
	#>
    [PSCustomObject] addContentSources([string]$name, [PSCustomObject]$catalogProject)
    {
		$uri = "{0}/catalog/api/admin/sources" -f $this.baseUrl

		$replace = @{
            name = $name
            catalogProjectId = $catalogProject.id
        }

		$body = $this.createObjectFromJSON("vra-project-catalog-source.json", $replace)

		# Création du Content Source et retour
		return $this.callAPI($uri, "Post", $body)
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Efface un Content Source

		IN  : $contentSource	-> objet représentant le Content Source à effacer
	#>
	[void] deleteContentSource([PSCustomObject]$contentSource)
	{
		$uri = "{0}/catalog/api/admin/sources/{1}" -f $this.baseUrl, $contentSource.id

		# Création du Content Source et retour
		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}


	<#
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
                                                INTEGRATIONS
        ------------------------------------------------------------------------------------------------------
        ------------------------------------------------------------------------------------------------------
    #>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des content sources selon des critères passés. Dans la GUI Web, il peuvent 
				être trouvé dans "Service Broker > Content & Policies > Content Sources"

        IN  : $queryParams  -> filtres à appliquer à la recherche

		RET : La liste des Content Sources
	#>
	# FIXME: Aucune documentation pour avoir la liste des intérgrations...
    # hidden [Array] getIntegrationListQuery()
    # {
    #     return $this.getContentSourcesListQuery("")
    # }
    # hidden [Array] getIntegrationListQuery([string]$queryParams)
    # {
    #     return $this.getObjectListQuery("/catalog/api/admin/sources", $queryParams)
    # }


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la représentation "string" à utiliser pour créer une source pour un élément GitHub

		IN  : $contentType	-> Le type de contenu pour lequel on veut la représentation

		RET : La représentation "string"
	#>
	hidden [string] getGitHubContentTypeStringValue([GitHubContentType]$contentType)
	{
		$val = switch($contentType)
		{
			CloudTemplates { "BLUEPRINT" }
			ActionBasedScripts { "ABC_SCRIPTS" }
			TerraformConfigurations { "TERRAFORM_CONFIGURATION" }
		}
		return $val
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une source GitHub pour un projet Catalogue donné

		IN  : $name					-> Nom de la source GitHub
		IN  : $catalogProject		-> Objet représentant le projet "catalogue"
		IN  : $gitHubIntegrationId	-> ID de l'intégration GitHub
		IN  : $contentType			-> Type de contenu que l'on veut ajouter comme source
		IN  : $repository			-> sous la forme "<owner>/<repository>" tel qu'utilisé dans GitHub
		IN  : $path					-> Le chemin au sein du repository. 
										ATTENTION! Le chemin doit exister côté GitHub!
		IN  : $branch				-> La branche sur laquelle se mettre

		RET : Objet avec un champ, "id", qui représente l'ID de la source ajoutée

		https://vsissp-vra8-t-02.epfl.ch/content/api/swagger/swagger-ui.html#/Content_Source
	#>
	[PSCustomObject] addCatalogProjectGitHubSource([string]$name, [PSCustomObject]$catalogProject, [string]$gitHubIntegrationId, [GitHubContentType]$contentType, [string]$repository, [string]$path, [string]$branch)
	{
		Write-Warning "HARDCODED GITHUB INTEGRATION ID, PLEASE FIX IT AS SOON AS FUC***G API IS WELL DOCUMENTED !"
		
		$uri = "{0}/content/api/sources" -f $this.baseUrl

		$replace = @{
			name = $name
            projectName = $catalogProject.name
            projectId = $catalogProject.id
			path = $path
			branch = $branch
			repository = $repository
			contentType = $this.getGitHubContentTypeStringValue($contentType)
			integrationId = $gitHubIntegrationId
        }

		$body = $this.createObjectFromJSON("vra-project-github-source.json", $replace)

		# Création du Content Source et retour
		return $this.callAPI($uri, "Post", $body)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une source github pour un projet de type catalogue existant

		IN  : $name	-> Nom de la source github

		RET : Objet représentant la source github
	#>
	[PSCustomObject] getCatalogProjectGitHubSource([string]$name)
	{
		$res = @($this.getObjectListQuery("/content/api/sources", "") | Where-Object { $_.name -eq $name})		

		if($res.count -eq 0)
		{
			return $null
		}
		return $res[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime une source github pour un projet de type catalogue

		IN  : $source	-> Objet représentant la source à supprimer
	#>
	[void] deleteCatalogProjectGitHubSource([PSCustomObject]$source)
	{
		$uri = "{0}/content/api/sources/{1}" -f $this.baseUrl, $source.id

		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}
}