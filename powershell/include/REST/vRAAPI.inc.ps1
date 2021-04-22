<#
   BUT : Contient les fonctions donnant accès à l'API vRA

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2018

	Des exemples d'utilsiation des API via Postman peuvent être trouvés ici :
	https://github.com/vmwaresamples/vra-api-samples-for-postman


	REMARQUES :
	- Il semblerait que le fait de faire un update d'élément sans que rien ne change
	mette un verrouillage sur l'élément... donc avant de faire un update, il faut
	regarder si ce qu'on va changer est bien différent ou pas.

	Documentation:
	Une description des fichiers JSON utilisés peut être trouvée sur Confluence.
	https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-vRA

	https://code.vmware.com/apis/39/vrealize-automation?p=vrealize-automation


#>
class vRAAPI: RESTAPICurl
{
	hidden [string]$token
	hidden [string]$tenant
	hidden [Hashtable]$bgCustomIdMappingCache

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $tenant			-> Nom du tenant auquel se connecter
		IN  : $userAtDomain	-> Nom d'utilisateur (user@domain)
		IN  : $password			-> Mot de passe

	#>
	vRAAPI([string] $server, [string] $tenant, [string] $userAtDomain, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.tenant = $tenant

		# Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )

		# Cache pour le mapping entre l'ID custom d'un BG et celui-ci
		$this.bgCustomIdMappingCache = $null

		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')

		$replace = @{username = $userAtDomain
						 password = $password
						 tenant = $tenant}

		$body = $this.createObjectFromJSON("vra-user-credentials.json", $replace)

		$uri = "{0}/identity/api/tokens" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.token = (Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)).id

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
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		$response = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'errors')
        {
			Throw ("vRAAPI error: {0}" -f $response.errors[0].systemMessage
			)
        }

        return $response
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		$uri = "{0}/identity/api/tokens/{1}" -f $this.baseUrl, $this.token

		$this.callAPI($uri, "Delete", $null)
	}



	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
											Business Groups
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau de BG
	#>
	hidden [Array] getBGListQuery([string] $queryParams)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants/?page=1&limit=9999" -f $this.baseUrl, $this.tenant

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return ($this.callAPI($uri, "Get", $null)).content

	}
	hidden [Array] getBGListQuery()
	{
		return $this.getBGListQuery($null)
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG

		RET : Tableau de BG
	#>
	[Array] getBGList()
	{
		return $this.getBGListQuery()
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des BG dont le nom contient la chaine de caractères passée
				en paramètre

		IN  : $str	-> la chaine de caractères qui doit être contenue dans le nom du BG

		RET : Tableau de BG
	#>
	[Array] getBGListMatch([string]$str)
	{
		return $this.getBGListQuery(("`$filter=substringof('{0}', name)" -f $str))
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un BG donné par son nom

		IN  : $name	-> Le nom du BG que l'on désire

		RET : Objet contenant le BG
				$null si n'existe pas
	#>
	[PSCustomObject] getBG([string] $name)
	{
		$list = $this.getBGListQuery(("`$filter=name eq '{0}'" -f $name))

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un BG donné par son ID custom, défini dans la custom property ch.epfl.vra.bg.id

		IN  : $customId	-> ID custom du BG que l'on désire
		IN  : $useCache -> (optionnel) pour dire si on doit utiliser un cache pour faire la requête

		RET : Objet contenant le BG
				$null si n'existe pas
	#>
	[PSCustomObject] getBGByCustomId([string] $customId)
	{
		return $this.getBGByCustomId($customId, $false)
	}
	[PSCustomObject] getBGByCustomId([string] $customId, [bool]$useCache)
	{
		$list = @()
		# Si on doit utiliser le cache ET qu'il est vide
		# OU 
		# On ne doit pas utiliser le cache
		if( ($useCache -and ($null -eq $this.bgCustomIdMappingCache)) -or !$useCache)
		{
			$list = $this.getBGList()

			if($list.Count -eq 0){return $null}
		}
		
		# Si on doit utiliser le cache
		if($useCache)
		{
			# Si on n'a pas encore initilisé le cache, on le fait, ce qui va prendre quelques secondes
			if($null -eq $this.bgCustomIdMappingCache)
			{
				$this.bgCustomIdMappingCache = @{}
				ForEach($bg in $list)
				{
					$bgId = getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID
					# Si on est bien sur un BG "correcte", qui a donc un ID
					if($null -ne $bgId)
					{
						$this.bgCustomIdMappingCache.add($bgId, $bg)
					}
					
				}
			}# FIN Si on n'a pas initialisé le cache

			# Arrivé ici, le cache est initialisé donc on peut rechercher avec l'Id demandé
			return $this.bgCustomIdMappingCache.item($customId)
		}
		else # On ne veut pas utiliser le cache (donc ça va prendre vraiment du temps!)
		{
			# Retour en cherchant avec le custom ID, y'a pas mal de Where-Object imbriqués pour faire le job mais ça fonctionne. Par contre, 
			# ça risque d'être un peu galère à debug par la suite ^^'
			return $list| Where-Object { 
				($_.extensionData.entries | Where-Object {
					$null -ne ($_.key -eq $global:VRA_CUSTOM_PROP_EPFL_BG_ID) -and ( $null -ne ($_.value.values.entries | Where-Object { 
						($null -ne $_.value.value) -and ($_.value.value -is [System.String]) -and ($_.value.value -eq $customId) } ) ) `
														} `
				)}
		}
	
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un BG

		IN  : $name					-> Nom du BG à ajouter
		IN  : $desc					-> Description du BG
		IN  : $capacityAlertsEmail	-> Adresse mail où envoyer les mails de capacity alert
									  (champ "send capacity alert emails to:")
		IN  : $machinePrefixId  	-> ID du prefix de machine à utiliser
									   Si on veut prendre le préfixe par défaut de vRA, on
									   peut passer "" pour ce paramètre.
		IN  : $customProperties		-> Dictionnaire avec les propriétés custom à ajouter


		RET : Objet contenant le BG
	#>
	[PSCustomObject] addBG([string]$name, [string]$desc, [string]$capacityAlertsEmail, [string]$machinePrefixId, [System.Collections.Hashtable] $customProperties)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants" -f $this.baseUrl, $this.tenant

		# Valeur à mettre pour la configuration du BG
		$replace = @{name = $name
						 description = $desc
						 tenant = $this.tenant
						 capacityAlertsEmail = $capacityAlertsEmail}

		# Si on a passé un ID de préfixe de machine,
		if($machinePrefixId -ne "")						 
		{
			$replace.machinePrefixId = $machinePrefixId
		}
		else 
		{
			$replace.machinePrefixId = $null
		}

		
		$body = $this.createObjectFromJSON("vra-business-group.json", $replace)

		# Ajout des éventuelles custom properties
		$customProperties.Keys | ForEach-Object {

			$body.extensionData.entries += $this.createObjectFromJSON("vra-business-group-extension-data-custom.json", `
															 			 @{"key" = $_
															 			  "value" = $customProperties.Item($_)})
		}

		# Création du BG
		$this.callAPI($uri, "Post", $body) | Out-Null
		
		# Recherche et retour du BG
		# On utilise $body.name et pas simplement $name dans le cas où il y aurait un préfixe ou suffixe de nom déjà hard-codé dans 
		# le fichier JSON template
		return $this.getBG($body.name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un BG.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $bg					-> Objet du BG à mettre à jour
		IN  : $newName				-> (optionnel -> "") Nouveau nom
		IN  : $newDesc				-> (optionnel -> "") Nouvelle description
		IN  : $machinePrefixId  	-> (optionnel -> "") ID du prefix de machine à utiliser
		IN  : $customProperties		-> (optionnel -> $null) La liste des "custom properties" (et leur valeur) à mettre à
									   jour

		RET : Objet contenant le BG mis à jour
	#>
	[PSCustomObject] updateBG([PSCustomObject] $bg, [string] $newName, [string] $newDesc, [string]$machinePrefixId, [System.Collections.IDictionary]$customProperties)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}" -f $this.baseUrl, $this.tenant, $bg.id

		$updateNeeded = $false

		# S'il faut mettre le nom à jour,
		if(($newName -ne "") -and ($bg.name -ne $newName))
		{
			$bg.name = $newName
			$updateNeeded = $true
		}

		# S'il faut mettre la description à jour,
		if(($newDesc -ne "") -and ($bg.description -ne $newDesc))
		{
			$bg.description = $newDesc
			$updateNeeded = $true
		}

		if(($machinePrefixId -ne "") -and ($null -ne $customProperties) -and ($customProperties['iaas-machine-prefix'] -ne $machinePrefixId))
		{
			$customProperties['iaas-machine-prefix'] = $machinePrefixId
			$updateNeeded = $true
		}

		# S'il faut mettre à jour une ou plusieurs "custom properties"
		if($null -ne $customProperties)
		{

			# Parcour des custom properties à mettre à jour,
			$customProperties.Keys | ForEach-Object {

				$customPropertyKey = $_

				# Recherche de l'entrée pour la "Custom property" courante à modifier
				$entry = $bg.extensionData.entries | Where-Object { $_.key -eq $customPropertyKey}

				# Si une entrée a été trouvée
				if($null -ne $entry)
				{
					# Mise à jour de sa valeur en fonction du type de la custom propertie
					switch($entry.value.type)
					{
						'complex'
						{
							($entry.value.values.entries | Where-Object {$_.key -eq "value"}).value.value = $customProperties.Item($customPropertyKey)
							break
						}

						'string'
						{
							$entry.value.value = $customProperties.Item($customPropertyKey)
							break
						}

						default:
						{
							Write-Warning ("Custom property type '{0}' not supported!" -f $entry.value.type)
						}
					}

				}
				else # Aucune entrée n'a été trouvée
				{
					# Ajout des infos avec le template présent dans le fichier JSON
					$bg.ExtensionData.entries += $this.createObjectFromJSON("vra-business-group-extension-data-custom.json", `
																			@{"key" = $customPropertyKey
																			"value" = $customProperties.Item($customPropertyKey)})
				}

			} # FIN BOUCLE de parcours des "custom properties" à mettre à jour

			$updateNeeded = $true
		}

		# Si on n'a pas besoin d'update quoi que ce soit, on ne le fait pas, sinon on risque de générer une erreur "(400) Bad Request" dans le cas où rien 
		# n'a été changé (ouais, c'est con mais c'est comme ça que vRA réagit... )
		if($updateNeeded -eq $false)
		{
			return $bg
		}

		# Mise à jour des informations
		$this.callAPI($uri, "Put", $bg) | Out-Null
		
		# On recherche l'objet mis à jour
		return $this.getBG($bg.name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime une Custom Property dans un Business Group

		IN  : $bg		-> Business Group dans lequel supprimer la custom property 
	#>
	[PSCustomObject] deleteBGCustomProperty([PSCustomObject]$bg, [string]$customPropertyName)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}" -f $this.baseUrl, $this.tenant, $bg.id

		# Filtrage de la custom property à supprimer
		$entries = $bg.extensionData.entries | Where-Object {$_.key -ne $customPropertyName}

		# Si rien n'a été supprimé car la custom property n'existait pas,
		if($entries.Count() -eq $bg.extensionData.entries.Count())
		{
			# on retourn le BG tel quel 
			return $bg
		}
		
		$bg.extensionData.entries = $entries
		# Mise à jour des informations
		$this.callAPI($uri, "Put", $bg) | Out-Null

		# On recherche l'objet mis à jour
		return $this.getBG($bg.name)
		
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un business group

		IN  : $BGID		-> ID du Business Group à supprimer
	#>
	[void] deleteBG($bgId)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}" -f $this.baseUrl, $this.tenant, $bgId

		# Mise à jour des informations
		$this.callAPI($uri, "Delete", $null) | Out-Null
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
											Business Groups Roles
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Retourne le contenu d'un rôle pour un BG

		IN  : $BGID		-> ID du BG auquel supprimer le rôle
		IN  : $role		-> Nom du rôle auquel ajouter le groupe/utilisateur AD
								Group manager role 	=> CSP_SUBTENANT_MANAGER
								Support role 			=> CSP_SUPPORT
								Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
								User role				=> CSP_CONSUMER

		RET : Tableau avec la liste des admins au format "admin@domain"	
	#>
	[Array] getBGRoleContent([string] $BGID, [string] $role)
	{
		$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/principals/" -f $this.baseUrl, $this.tenant, $BGID, $role

		# Récupération de la liste d'objets
		$res = ($this.callAPI($uri, "Get", $null)).content
		
		# On remet le tout dans un tableau en récupérant ce qui nous intéresse
		$resArray = @()
		$res | ForEach-Object { $resArray += "{0}@{1}" -f $_.principalId.name, $_.principalId.domain }

		return $resArray
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime le contenu d'un rôle pour un BG

		IN  : $BGID		-> ID du BG auquel supprimer le rôle
		IN  : $role		-> Nom du rôle auquel ajouter le groupe/utilisateur AD
								Group manager role 	=> CSP_SUBTENANT_MANAGER
								Support role 			=> CSP_SUPPORT
								Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
								User role				=> CSP_CONSUMER
	#>
	[Void] deleteBGRoleContent([string] $BGID, [string] $role)
	{
		# S'il y a du contenu pour le rôle
		if(($this.getBGRoleContent($BGID, $role)).count -gt 0)
		{
			$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/" -f $this.baseUrl, $this.tenant, $BGID, $role

			# Suppression du contenu du rôle
			$this.callAPI($uri, "Delete", $null) | Out-Null
		}

	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Ajouter un élément (groupe/utilisateur AD) à un rôle donné d'un BG

		IN  : $BGID							-> ID du BG auquel ajouter le rôle
		IN  : $role							-> Nom du rôle auquel ajouter le groupe/utilisateur AD
													Group manager role 	=> CSP_SUBTENANT_MANAGER
													Support role 			=> CSP_SUPPORT
													Shared access role	=> CSP_CONSUMER_WITH_SHARED_ACCESS
													User role				=> CSP_CONSUMER
		IN  : $userOrGroupAtDomain		-> Utilisateur/groupe AD à ajouter
													<user>@<domain>
													<group>@<domain>

		RET : Rien
	#>
	[Void] addRoleToBG([string] $BGID, [string] $role, [string] $userOrGroupAtDomain)
	{
		# Séparation des informations
		$userOrGroup, $domain = $userOrGroupAtDomain.split('@')

		$uri = "{0}/identity/api/tenants/{1}/subtenants/{2}/roles/{3}/principals" -f $this.baseUrl, $this.tenant, $BGID, $role


		# ******
		# Pour cette fois-ci on ne charge pas depuis le JSON car c'est un tableau contenant un dictionnaire.
		# Et dans cette version de PowerShell, si le JSON commence par un tableau, le reste est mal interprêté.
		# Dans le cas courant, ce qui est dans le tableau (un dictionnaire), ce n'est pas un objet IDictionnary
		# qui sera créé mais un PSCustomObject basique...
		# Le problème est corrigé dans la version 6.0 De PowerShell mais celle-ci s'installe par défaut en parallèle
		# de la version 5.x de PowerShell et donc les éditeurs de code ne la prennent pas en compte... donc pas
		# possible de faire du debugging.
		# Valeurs à remplacer
		<#
		$replace = @{name = $userOrGroup
						 domain = $domain}

		$body = vRALoadJSON -file "vra-business-group-role-principal.json"  -valToReplace $replace
		#>
		# ******

		$body = @(
			@{
				name = $userOrGroup
				domain = $domain
			}
		)

		# Ajout du rôle
		$this.callAPI($uri, "Post", $body) | Out-Null
		
	}




	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
													Entitlements
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des entitlements basée sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des entitlements
	#>
	hidden [Array] getEntListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/entitlements/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return ($this.callAPI($uri, "Get", $null)).content

	}
	hidden [Array] getEntListQuery()
	{
		return $this.getEntListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie l'entitlement d'un BG

		IN  : $BGID 	-> ID du BG pour lequel on veut l'entitlement

		RET : L'entitlement ou $null si pas trouvé
	#>
	[PSCustomObject] getBGEnt([string]$BGID)
	{
		$uri = "{0}/catalog-service/api/entitlements/?page=1&limit=9999&`$filter=organization/subTenant/id eq '{1}'" -f $this.baseUrl, $BGID

		$ent = ($this.callAPI($uri, "Get", $null)).content

		if($ent.Count -eq 0){return $null}
		return $ent[0]

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des entitlements

		RET : Liste des entitlements
	#>
	[Array] getEntList()
	{
		return $this.getEntListQuery()
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Entitlements dont le nom contient la chaine de caractères
				passée en paramètre

		IN  : $str	-> la chaine de caractères qui doit être contenue dans le nom de l'entitlement

		RET : Tableau de Entitlements
	#>
	[Array] getEntListMatch([string]$str)
	{
		return $this.getEntListQuery(("`$filter=substringof('{0}', name)" -f $str))
	}

	
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un entitlement donné par son nom

		IN  : $name -> le nom

		RET : Liste des entitlements
	#>
	[PSCustomObject] getEnt([string]$name)
	{
		$list = $this.getEntListQuery(("`$filter=name eq '{0}'" -f $name))

		if($list.Count -eq 0){return $null}
		return $list[0]

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un entitlement

		IN  : $name		-> Nom
		IN  : $desc		-> Description
		IN  : $BGID		-> ID du Business Group auquel lier l'entitlement
		IN  : $bgName	-> Nom du Business Group auquel lier l'entitlement

		RET : L'entitlement ajouté
	#>
	[PSCustomObject] addEnt([string]$name, [string]$desc, [string]$BGID, [string]$bgName)
	{
		$uri = "{0}/catalog-service/api/entitlements" -f $this.baseUrl

		# Valeur à mettre pour la configuration du BG
		$replace = @{name = $name
						 description = $desc
						 tenant = $this.tenant
						 bgID = $BGID
						 bgName = $bgName}

		$body = $this.createObjectFromJSON("vra-entitlement.json", $replace)

		$this.callAPI($uri, "Post", $body) | Out-Null
		
		# Retour de l'entitlement
		# On utilise $body.name et pas simplement $name dans le cas où il y aurait un préfixe ou suffixe de nom déjà hard-codé dans 
		# le fichier JSON template
		return $this.getEnt($body.name)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un Entitlement.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $ent			-> Objet de l'entitlement à mettre à jour
		IN  : $newName		-> (optionnel -> "") Nouveau nom
		IN  : $newDesc		-> (optionnel -> "") Nouvelle description
		IN  : $activated	-> Pour dire si l'Entitlement doit être activé ou pas.

		RET : Objet contenant l'entitlement mis à jour
	#>
	[PSCustomObject] updateEnt([PSCustomObject] $ent, [string] $newName, [string] $newDesc, [bool]$activated)
	{
		$uri = "{0}/catalog-service/api/entitlements/{1}" -f $this.baseUrl, $ent.id


		# S'il faut mettre le nom à jour,
		if($newName -ne "")
		{
			$ent.name = $newName		
		}

		# S'il faut mettre la description à jour,
		if($newDesc -ne "")
		{
			$ent.description = $newDesc
		}

		# En fonction de s'il faut activer ou pas
		if($activated)
		{
			$ent.status = "ACTIVE"
			$ent.statusName = "Active"
			
		}
		else
		{
			$ent.status = "INACTIVE"
			$ent.statusName = "Inactive"

		}

		# Mise à jour des informations
		$this.callAPI($uri, "Put", $ent) | Out-Null
		
		# on retourne spécifiquement l'objet qui est dans vRA et pas seulement celui qu'on a utilisé pour faire la mise à jour. Ceci
		# pour la simple raison que dans certains cas particuliers, on se retrouve avec des erreurs "409 Conflicts" si on essaie de
		# réutilise un élément pas mis à jour depuis vRA
		return $this.getEnt($ent.name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour les infos d'un Entitlement.
				Pour faire ceci, on met tout simplement à jour les informations de l'objet que l'on a
				et on réencode ensuite celui-ci en JSON afin de le passer en BODY pour la mise à jour.
				C'est l'ID qui sera utilisé pour faire le match et seules les informations qui auront
				changé seront mises à jour. Du coup, en reprenant la totalité de celles-ci et en
				changeant juste celles dont on a besoin, on est sûr de ne rien modifier qu'il ne
				faudrait pas

		IN  : $ent			-> Objet de l'entitlement à mettre à jour (et contenant les infos
								mises à jour)
		IN  : $activated	-> Pour dire si l'Entitlement doit être activé ou pas.

		RET : Objet contenant l'entitlement mis à jour
	#>
	[PSCustomObject] updateEnt([PSCustomObject] $ent, [bool]$activated)
	{
		# Réutilisation de la méthode en passant des paramètres vides.
		return $this.updateEnt($ent, $null, $null, $activated)
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un entitlement

		IN  : $entId	-> ID de l'Entitlement à supprimer
	#>
	[void] deleteEnt([string]$entID)
	{
		$uri = "{0}/catalog-service/api/entitlements/{1}" -f $this.baseUrl, $entId

		$this.callAPI($uri, "Delete", $null) | Out-Null
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
													Service
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Services basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des Services
	#>
	hidden [Array] getServiceListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/services/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		$result = ($this.callAPI($uri, "Get", $null))

		# Ajout dans le cache
		$this.addInCache($result, $uri)

		return $result.content
	}
	hidden [Array] getServiceListQuery()
	{
		return $this.getServiceListQuery($null)
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Services contenant une chaine de caractères donnée

		IN  : $str		-> (optionnel) Chaine de caractères que doit contenir le nom

		RET : Liste des Services
	#>
	[Array] getServiceListMatch([string] $str)
	{
		return $this.getServiceListQuery("`$filter=substringof('{0}', name)" -f $str)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Préparer un objet contenant un Entitlement en lui ajoutant le service passé
				en paramètre.
				Afin de réellement ajouter les services pour l'Entitlement dans vRA, il faudra
				appeler la méthode updateEnt() en passant l'objet en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel ajouter le service
		IN  : $service			-> Objet représentant le service à ajouter
		IN  : $approvalPolicy	-> Objet de l'approval policy
									$null si pas besoin d'approval policy

		RET : Objet contenant Entitlement avec le nouveau service
	#>
	[PSCustomObject] prepareAddEntService([PSCustomObject] $ent, [PSCustomObject]$service, [PSCustomObject]$approvalPolicy)
	{
		# Définition de l'ID d'approval policy en fonction de ce qui est passé
		if($null -eq $approvalPolicy)
		{
			$approvalPolicyId = ""
		}
		else
		{
			$approvalPolicyId = $approvalPolicy.id
		}
		
		# Valeur à mettre pour la configuration du Service
		$replace = @{id = $service.id
					label = $service.name
					approvalPolicyId = $approvalPolicyId}

		# Création du nécessaire pour le service à ajouter
		$service = $this.createObjectFromJSON("vra-entitlement-service.json", $replace)

		# Ajout du service à l'objet
		$ent.entitledServices += $service

		# Retour de l'entitlement avec le nouveau Service.
		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Préparer un objet contenant un Entitlement en lui enlevant le service dont le
				nom est passé en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel enlever le service
		IN  : $service			-> Objet représentant le service à enlever		

		RET : Objet contenant Entitlement avec le service retiré
	#>
	[PSCustomObject] prepareRemoveEntService([PSCustomObject]$ent, [PSCustomObject]$service)
	{
		# On supprime le service par son nom
		$ent.entitledServices = @($ent.entitledServices | Where-Object { $_.serviceRef.label -ne $service.name})
		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Préparer un objet contenant un Entitlement en lui ajoutant l'élément de catalogue passé
				en paramètre.
				Afin de réellement ajouter les éléments de catalogue pour l'Entitlement dans vRA, il faudra
				appeler la méthode updateEnt() en passant l'objet en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel ajouter le service
		IN  : $catalogItem		-> Objet représentant l'élément de catalogue à ajouter
		IN  : $approvalPolicy	-> Objet de l'approval policy.

		RET : Objet contenant Entitlement avec le nouvel élément de catalogue
	#>
	[PSCustomObject] prepareAddEntCatalogItem([PSCustomObject] $ent, [PSCustomObject]$catalogItem, [PSCustomObject]$approvalPolicy)
	{
		# Définition de l'ID d'approval policy en fonction de ce qui est passé
		if($null -eq $approvalPolicy)
		{
			$approvalPolicyId = ""
		}
		else
		{
			$approvalPolicyId = $approvalPolicy.id
		}

		# Si c'est un élément de catalogue qui fait déjà partie d'un entitlement,
		if(objectPropertyExists -obj $catalogItem -propertyName "catalogItem")
		{
			# Valeur à mettre pour la configuration du Service
			$replace = @{id = $catalogItem.catalogItem.id
				label = $catalogItem.catalogItem.name
				approvalPolicyId = $approvalPolicyId}
		}
		else # l'élément de catalogue ne fait pas partie d'un entitlement
		{
			# Valeur à mettre pour la configuration du Service
			$replace = @{id = $catalogItem.id
				label = $catalogItem.name
				approvalPolicyId = $approvalPolicyId}
		}

		# Création du nécessaire pour le service à ajouter
		$catalogItem = $this.createObjectFromJSON("vra-entitlement-catalog-item.json", $replace)

		# Ajout du service à l'objet
		$ent.entitledCatalogItems += $catalogItem

		# Retour de l'entitlement avec le nouveau Service.
		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Préparer un objet contenant un Entitlement en lui enlevant tous les éléments
				de catalogue

		IN  : $ent		-> Objet de l'entitlement auquel enlever l'élément de catalogue

		RET : Objet contenant Entitlement avec tous les éléments de catalogue
	#>
	[PSCustomObject] prepareRemoveAllCatalogItems([PSCustomObject]$ent)
	{
		# On supprime tous les éléments 
		$ent.entitledCatalogItems = @()
		return $ent
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Prépare un Objet représentant un Entitlement en initialisant la liste des actions
				2nd day.
				Afin de réellement ajouter les actions pour l'Entitlement dans vRA, il faudra
				appeler la méthode updateEnt() en passant l'objet en paramètre.

		IN  : $ent				-> Objet de l'entitlement auquel ajouter les actions
		IN  : $secondDayActions	-> Objet de la classe SecondDayActions contenant la liste des actions à ajouter.

		RET : Tableau associatif avec les éléments suivants:
				.entitlement		-> Objet contenant l'Entitlement avec les actions passée.
				.notFoundActions	-> Tableau avec la liste des actions non trouvées
	#>
	[Hashtable] prepareEntActions([PSCustomObject] $ent, [SecondDayActions]$secondDayActions)
	{
		# Pour enregistrer la liste des actions non trouvées
		$notFoundActions = @()

		# Pour stocker la liste des actions à ajouter, avec toutes les infos nécessaires
		$actionsToAdd = @()

		# Parcours des éléments sur lesquels des actions vont s'appliquer. 
		Foreach($targetElementName in $secondDayActions.getTargetElementList())
		{
			# Parcours des actions à ajouter pour l'élément
			ForEach($actionName in $secondDayActions.getElementActionList($targetElementName))
			{
				# Si on a trouvé des infos pour l'action demandée,
				if($null -ne ($vRAAction = $this.getAction($actionName, $targetElementName)))
				{
					# Recherche de l'id de l'approval policy pour l'élément et l'action.
					$approvalPolicyId = $secondDayActions.getActionApprovalPolicyId($targetElementName, $actionName)

					# Valeur à mettre pour la configuration du BG
					$replace = @{resourceOperationRef_id = $vRAAction.id
									resourceOperationRef_label = $vRAAction.name
									externalId = $vRAAction.externalId
									targetResourceTypeRef_id = $vRAAction.targetResourceTypeRef.id
									targetResourceTypeRef_label = $vRAAction.targetResourceTypeRef.label
									approvalPolicyId = $approvalPolicyId}

					# Création du nécessaire pour l'action à ajouter
					$actionsToAdd += $this.createObjectFromJSON("vra-entitlement-action.json", $replace)
				}
				else # Pas d'infos trouvées pour l'action
				{
					Write-Warning ("prepareEntActions(): No information found for action '{0}' for element '{1}'" -f $actionName, $targetElementName)
					
					if($notFoundActions -notcontains $actionName)
					{
						$notFoundActions += $actionName
					}
					
				}
			} # Fin BOUCLE de parcours des actions pour l'élément courant 
			
		} # FIN BOUCLE de parcours des éléments auxquels il faut ajouter des "2nd day actions"

		# Ajout du service à l'objet
		$ent.entitledResourceOperations = $actionsToAdd

		# Retour de l'entitlement avec les actions
		return @{
			entitlement = $ent
			notFoundActions = $notFoundActions
		}
	}




	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Reservations
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
		IN  : $allowCache	-> $true|$false pour dire si on peut utiliser le cache

		RET : Liste des Reservations
	#>
	hidden [Array] getResListQuery([string] $queryParams, [bool]$allowCache)
	{
		$uri = "{0}/reservation-service/api/reservations/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		$result = ($this.callAPI($uri, "Get", $null))

		# Si on a le droit d'utiliser le cache
		if($allowCache)
		{
			# Ajout dans le cache
			$this.addInCache($result, $uri)
		}

		return $result.content
		
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations contenant une chaine de caractères donnée

		IN  : $str			-> Chaine de caractères que doit contenir le nom (peut être vide)
		IN  : $allowCache	-> $true|$false pour dire si on peut utiliser le cache 

		RET : Liste des Reservations
	#>
	[Array] getResListMatch([string] $str, [bool]$allowCache)
	{
		return $this.getResListQuery(("`$filter=substringof('{0}', name)" -f $str), $allowCache)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une Reservation donnée par son nom

		IN  : $name	-> Le nom de la Reservation que l'on désire

		RET : Objet contenant la Reservation
				$null si n'existe pas
	#>
	[PSCustomObject] getRes([string] $name)
	{
		$list = $this.getResListQuery(("`$filter=name eq '{0}'" -f $name), $false)

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Reservations d'un BG

		IN  : $bgID	-> ID du BG dont on veut les Reservations

		RET : Liste des Reservation
	#>
	[PSCustomObject] getBGResList([string] $bgID)
	{
		return $this.getResListQuery(("`$filter=subTenantId eq '{0}'" -f $bgID), $false)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une Reservation à partir d'un template

		IN  : $resTemplate	-> Objet contenant le Template à utiliser pour ajouter la Reservation
		IN  : $name			-> Nom
		IN  : $tenant		-> Nom du Tenant
		IN  : $BGID			-> ID du Business Group auquel lier la Reservation

		RET : L'entitlement ajouté
	#>
	[PSCustomObject] addResFromTemplate([PSCustomObject]$resTemplate, [string]$name, [string]$tenant, [string]$BGID)
	{
		$uri = "{0}/reservation-service/api/reservations" -f $this.baseUrl

		# Mise à jour des champs pour pouvoir ajouter la nouvelle Reservation
		$resTemplate.name = $name
		$resTemplate.tenantId = $tenant
		$resTemplate.subTenantId = $BGID
		# Suppression de la référence au template
		$resTemplate.id = $null
		# On repart de 0 pour la version
		$resTemplate.version = 0
		# On l'active (dans le cas où le Template était désactivé)
		$resTemplate.enabled = $true

		$this.callAPI($uri, "Post", $resTemplate) | Out-Null
		
		return $this.getRes($name)

	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met une Reservation à jour mais seulement s'il y a eu des changements dans celle-ci.
				On se base sur .extensionData et .alertPolicy. Si un de ces éléments a changé, on
				met à jour. Sinon, on ne fait rien car on risque juste de se prendre une erreur
				dans la tête car rien n'a été changé...

		IN  : $res			-> Objet contenant la Reservation à mettre à jour.
		IN  : $resTemplate	-> Objet contenant le Template à utiliser pour mettre à jour la Reservation
		IN  : $name			-> Le nouveau nom de la Reservation (parce qu'il peut changer)

		RET : Tableau avec :
				0 -> Objet contenant la Reservation mise à jour
				1 -> $true|$false pour dire si ça a été mis à jour
	#>
	[Array] updateRes([PSCustomObject]$res, [PSCustomObject]$resTemplate, [string]$name)
	{
		$uri = "{0}/reservation-service/api/reservations/{1}" -f $this.baseUrl, $res.id

		$updated = $false

		# Si un des éléments a changé, 
		if(((ConvertTo-Json -InputObject $res.extensionData -Depth 20) -ne (ConvertTo-Json -InputObject $resTemplate.extensionData -Depth 20)) -or
		   ((ConvertTo-Json -InputObject $res.alertPolicy -Depth 20) -ne (ConvertTo-Json -InputObject $resTemplate.alertPolicy -Depth 20)) -or 
		   ($res.name -ne $name))
		{
			# Initialisation des champs pour pouvoir mettre à jour la Reservation
			$res.name = $name
			$res.extensionData =  $resTemplate.extensionData
			$res.alertPolicy =  $resTemplate.alertPolicy
			
			$res = $this.callAPI($uri, "Put", $res)

			$updated = $true
		}
		
		# on retourne spécifiquement l'objet qui est dans vRA et pas seulement celui qu'on a utilisé pour faire la mise à jour. Ceci
		# pour la simple raison que dans certains cas particuliers, on se retrouve avec des erreurs "409 Conflicts" si on essaie de
		# réutilise un élément pas mis à jour depuis vRA
		return @($this.getRes($name), $updated)
	}



	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime une Reservation

		IN  : $resId	-> Id de la Reservation à supprimer
	#>
	[void] deleteRes([string]$resID)
	{
		$uri = "{0}/reservation-service/api/reservations/{1}" -f $this.baseUrl, $resID

		$this.callAPI($uri, "Delete", $null) | Out-Null
		
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Resources Actions
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des actions (2nd day) basé sur les potentiels critères passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des actions
	#>
	hidden [Array] getActionListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/resourceOperations/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		# Récupération du résultat pour le mettre dans le cache
		$result = ($this.callAPI($uri, "Get", $null))

		# Ajout dans le cache
		$this.addInCache($result, $uri)

		return $result.content
		
	}
	hidden [Array] getActionListQuery()
	{
		return $this.getActionListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une action (2nd day) donnée par son nom et l'élément auquel elle s'applique

		IN  : $name			-> Le nom de l'action que l'on désire (c'est celui affiché dans la GUI)
		IN  : $appliesTo	-> Chaîne de caractères avec l'ID du type de ressource auquel s'applique
								cette action.
								Ex: "Virtual Machine" pour une VM, ou un nom de type dynamique
								
		RET : Objet contenant l'action
				$null si n'existe pas

		REMARQUE : On n'utilise pas le filtre OData avec le nom de l'action recherchée (même si ça peut être
					plus rapide) car si le nom de l'action contient des [ ], ça va retourner une erreur et 
					impossible de trouver comment formater la requête pour que ça passe. Même en encodant
					(urlencode), ça ne passe pas... donc, on utilise un "Where-Object" pour trouver ce que
					l'on recherche.
	#>
	[PSCustomObject] getAction([string] $name, [string]$appliesTo)
	{

		<# Filtre. On veut filtrer sur la structure suivante
		"targetResourceTypeRef": {
                "id": "Infrastructure.Virtual",
                "label": "Virtual Machine"
            }

		On doit cependant utiliser "targetResourceType/name" et pas "targetResourceTypeRef/label" pour arriver à nos fins... logique quand tu nous tiens...
		#>
		$appliesToFilter = "targetResourceType/name eq '{0}'" -f $appliesTo
		

		$list = $this.getActionListQuery(("`$filter={0}" -f $appliesToFilter)) | Where-Object { $_.name -eq $name }

		if($list.Count -eq 0){return $null}
		if($list.Count -gt 1)
		{
			Throw ("Multiple ({0}) 2nd day actions '{1}' found for element ''")
		}
		return $list[0]
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Principals
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des principals basé sur les potentiels critères passés en
				paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des Custom groups
	#>
	hidden [Array] getPrincipalsListQuery([string] $queryParams)
	{
		$uri = "{0}/identity/api/authorization/tenants/{1}/principals/?page=1&limit=9999" -f $this.baseUrl, $this.tenant

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
		return ($this.callAPI($uri, "Get", $null)).content

	}
	hidden [Array] getPrincipalsListQuery()
	{
		return $this.getPrincipalsListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Custom groups
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des admins pour le tenant courant.

		IN  : $domain	-> Le nom de domaine pour lequel on veut la liste des admins.
						   - "" -> pas de filtre
						   - nom du tenant -> admins locaux au tenant
						   - nom du domaine AD -> ([NameGenerator]::AD_DOMAIN_NAME) pour avoir
						   les admins se trouvant dans le domaine AD

		RET : Liste des admins au format "admin@domain"
	#>
	[Array] getTenantAdminGroupList([string]$domain)
	{
		# On récupère tous les admins 
		$adminList = $this.getPrincipalsListQuery()

		# Application du filtre si besoin 
		if($domain -ne "")
		{
			$adminList = $adminList | Where-Object {$_.principalRef.domain -eq $domain}
		}

		# Mise dans un tableau et on renvoie.
		$resArray = @()
		$adminList | ForEach-Object { $resArray += "{0}@{1}" -f $_.principalRef.name, $_.principalRef.domain }

		return $resArray
	}



	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
												Machine prefixes
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des préfixes de machines basé sur les potentiels critères de
				recherche passés en paramètre

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Liste des préfixes de machines
	#>
	hidden [Array] getMachinePrefixListQuery([string] $queryParams)
	{
		$uri = "{0}/iaas-proxy-provider/api/machine-prefixes/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		# Récupération du résultat pour l'ajouter dans le cache
		$result = ($this.callAPI($uri, "Get", $null))

		return $result.content

	}
	hidden [Array] getMachinePrefixListQuery()
	{
		return $this.getMachinePrefixListQuery($null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un préfix de machine donné par son nom

		IN  : $name	-> Le nom du préfix de machine que l'on désire

		RET : Objet contenant le préfix
				$null si n'existe pas
	#>
	[PSCustomObject] getMachinePrefix([string] $name)
	{
		$list = $this.getMachinePrefixListQuery(("`$filter=name eq '{0}'" -f $name))

		if($list.Count -eq 0){return $null}
		return $list[0]
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un préfix de machine dans vRA. Par défaut, il sera ajouté pour le tenant
				auquel on est connecté

		IN  : $name				-> Le nom du préfix de machine que l'on désire ajouter
		IN  : $numberOfDigits	-> Nombre de digits max du préfixe

		RET : Objet contenant le préfixe
	#>
	[PSCustomObject] addMachinePrefix([string] $name, [int] $numberOfDigits)
	{
		$uri = "{0}/iaas-proxy-provider/api/machine-prefixes/" -f $this.baseUrl

		# Valeur à mettre pour la configuration du BG
		$replace = @{
			name = $name
			numberOfDigits = $numberOfDigits
		}

		$body = $this.createObjectFromJSON("vra-machine-prefix.json", $replace)

		return ($this.callAPI($uri, "POST", $body))
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un préfixe de machine

		IN  : $machinePrefix	-> Objet représentant le préfixe de machine à effacer
	#>
	[void] deleteMachinePrefix([PSCustomObject] $machinePrefix)
	{
		<# A savoir que l'URL utilisée ici ne correspond pas à la documentation Swagger de l'API car ... ça fait depuis
			début 2019 que VMware ne l'a pas mise à jour... un bug était déjà présent dans la version 7.5 de l'API (ou de
			sa documentation). Bref, c'est grâce à ce post d'un forum que la solution a été trouvée:
			https://communities.vmware.com/thread/604831
		#>
		$uri = "{0}/iaas-proxy-provider/api/machine-prefixes/guid'{1}'" -f $this.baseUrl, $machinePrefix.id

		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}

<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
											CATALOG ITEMS
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items du catalogue (qui sont disponibles dans des
				entitlements) selon les paramètres passés dans $queryParams

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau contenant les items
	#>
	hidden [Array] getEntitledCatalogItemListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/consumer/entitledCatalogItems/?page=1&limit=5000" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		# Retour de la liste mais on ne prend que les éléments qui existent encore.
		$result = ($this.callAPI($uri, "Get", $null)).content 	

		return $result
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items du catalogue selon les paramètres passés dans $queryParams


		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau contenant les items
	#>
	hidden [Array] getCatalogItemListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/catalogItems/?page=1&limit=5000" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		# Retour de la liste mais on ne prend que les éléments qui existent encore.
		$result = ($this.callAPI($uri, "Get", $null)).content 	

		return $result
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items qui sont au catalogue pour un service.
			  
		IN  : $service			-> Objet représentant le service pour lequel on veut la liste 
									des Items du catalogue

		RET : Tableau contenant les items du catalogue
	#>
	[Array] getServiceEntitledCatalogItemList([PSObject] $service)
	{
		return $this.getEntitledCatalogItemListQuery(("`$filter=service/id eq '{0}' and status eq 'PUBLISHED'" -f $service.id))
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un item de catalogue donné par son nom
			  
		IN  : $name			-> Nom de l'élément de cataloguq que l'on désire

		RET : Objet avec les détails de l'élément de catalogue
				$null si pas trouvé
	#>
	[PSObject] getCatalogItem([string]$name)
	{
		$results = $this.getCatalogItemListQuery(("`$filter=name eq '{0}' and status eq 'PUBLISHED'" -f $name))

		if($results.count -eq 0)
		{
			return $null
		}
		return $results[0]
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Business Group Items
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items selon les paramètres passés dans $queryParams


		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau contenant les items
	#>
	hidden [Array] getBGItemListQuery([string] $queryParams)
	{
		$uri = "{0}/catalog-service/api/consumer/resources/?page=1&limit=9999" -f $this.baseUrl

		# Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		# Retour de la liste mais on ne prend que les éléments qui existent encore.
		$result = ($this.callAPI($uri, "Get", $null)).content 	

		# On ne filtre que si on n'a pas déjà un filtre.
		if($queryParams -notlike '*filter*')
		{
			# On filtre pour ne retourner que les éléments qui n'ont pas de parents car on ne veut pas les trucs
			# genre "yum_update" ou autre.
			$result = $result |  Where-Object { $null -eq $_.parentResourceRef}
		}

		return $result
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items d'un BG.
			  
		IN  : $bg				-> Objet représentant le BG pour lequel on veut la liste des Items

		RET : Tableau contenant les items
	#>
	[Array] getBGItemList([PSObject] $bg)
	{
		return $this.getBGItemListQuery(("`$filter=organization/subTenant/id eq '{0}'" -f $bg.id))
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Items d'un type donné pour un BG.
			  
		IN  : $bg				-> Objet représentant le BG pour lequel on veut la liste des Items
		IN  : $itemType			-> Type d'item que l'on désire ('Virtual Machine' par exemple)

		RET : Tableau contenant les items
	#>
	[Array] getBGItemList([PSObject] $bg, [string]$itemType)
	{
		return $this.getBGItemListQuery(("`$filter=organization/subTenant/id eq '{0}' and resourceType/name eq '{1}'" -f $bg.id, $itemType))

	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un item donné pour son type et son nom
			  
		IN  : $itemType			-> Type d'item que l'on désire ('Virtual Machine' par exemple)
		IN  : $itemName			-> Nom de l'item que l'on chercher

		RET : Objet avec l'item
			$null si pas trouvé
	#>
	[PSObject] getItem([string]$itemType, [string]$itemName)
	{
		# On encode le nom de l'item dans le cas où il aurait un nom avec des caractères spéciaux
		$res = $this.getBGItemListQuery(("`$filter=resourceType/name eq '{0}' and name eq '{1}'" -f $itemType, [System.Net.WebUtility]::UrlEncode($itemName)))

		if($res.length -eq 0)
		{
			return $null
		}
		return $res[0]
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un item donné pour son id
			  
		IN  : $itemName			-> ID de l'item que l'on chercher

		RET : Objet avec l'item
			$null si pas trouvé
	#>
	[PSObject] getItem([string]$itemId)
	{
		$res = $this.getBGItemListQuery(("`$filter=id eq '{0}'" -f $itemId))

		if($res.length -eq 0)
		{
			return $null
		}
		return $res[0]
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Directories
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Lance la synchro d'un directory (ex: Active Directory)

		IN  : $name	-> Nom du directory que l'on veut synchroniser
	#>
	[void] syncDirectory([string] $name)
	{
		$uri = "{0}/identity/api/tenants/{1}/directories/{2}/sync" -f $this.baseUrl, $this.tenant, $name

		$this.callAPI($uri, "Post", $null) | Out-Null
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Approval Policies
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Approve Policies

		IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams

		RET : Tableau d'Approve Policies
	#>
	hidden [Array] getApprovePolicyListQuery([string] $queryParams)
	{
		$uri = "{0}/approval-service/api/policies?page=1&limit=9999" -f $this.baseUrl

		# Si on doit ajouter des paramètres
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

		return ($this.callAPI($uri, "Get", $null)).content
	}
	hidden [Array] getApprovePolicyListQuery()
	{
		return $this.getApprovePolicyListQuery("")
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une Approve Policy basée sur son nom.

		IN  : $name	-> Le nom de l'approve policy que l'on désire

		RET : Objet contenant l'approve policy
				$null si n'existe pas
	#>
	[PSCustomObject] getApprovalPolicy([string] $name)
	{
		$list = $this.getApprovePolicyListQuery(("`$filter=name eq '{0}'" -f $name))

		if($list.Count -eq 0){return $null}
		return $list[0]
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des approval policies

		RET : Liste des approval policies
	#>
	[Array] getApprovalPolicyList()
	{
		return $this.getApprovePolicyListQuery()
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Créé une pré-approval policy qui passe par un "Subscription Event" OU un "Approver Group"
			  pour la validation.
			  Par défaut, le nom du "level" de type "Pre approval" sera identique au nom de la Policy

		IN  : $name						-> Nom de la policy
		IN  : $desc						-> Description de la policy
		IN  : $approvalLevelJSON		-> Le nom court du fichier JSON (template) à utiliser pour créer les
											les Approval Level de l'approval policy
		IN  : $approverGroupAtDomainList-> Tableau avec la liste ordrée des FQDN du groupe (<group>@<domain>) qui devront approuver.
											Chaque entrée du tableau correspond à un "level" d'approbation
		IN  : $approvalPolicyJSON		-> Le nom court du fichier JSON (template) à utiliser pour 
											créer l'approval policy dans vRA
		IN  : $additionnalReplace		-> Tableau associatif permettant d'étendre la liste des éléments
											à remplacer (chaînes de caractères) au sein du fichier JSON
											chargé. Le paramètre doit avoir en clef la valeur à chercher
											et en valeur celle avec laquelle remplacer.
											Peut être $null

		RET : L'approval policy créée
	#>
	[psobject] addPreApprovalPolicy([string]$name, [string]$desc, [string]$approvalLevelJSON, [Array]$approverGroupAtDomainList, [string]$approvalPolicyJSON, [psobject]$additionnalReplace)
	{
		$uri = "{0}/approval-service/api/policies" -f $this.baseUrl

		# Création des approval levels
		$approvalLevels = @()
		ForEach($approverGroupAtDomain in $approverGroupAtDomainList)
		{
			$approverDisplayName, $domain = $approverGroupAtDomain.Split('@')

			$levelNo = $approvalLevels.Count + 1

			$replace = @{preApprovalLevelName = ("{0}-{1}" -f $name, $levelNo)
						 approverGroupAtDomain = $approverGroupAtDomain
						 approverDisplayName = $approverDisplayName
						 preApprovalLeveNumber = @($levelNo, $true)}

			# Création du level d'approbation et ajout à la liste 
			$approvalLevels += $this.createObjectFromJSON($approvalLevelJSON, $replace)
		}

		# Valeur à mettre pour la configuration du BG
		$replace = @{preApprovalName = $name
			preApprovalDesc = $desc
			preApprovalLevels = @((ConvertTo-Json -InputObject $approvalLevels -Depth 10), $true) # On transforme en JSON pour remplacer dans le fichier JSON
			} 

		# Si on a des remplacement additionnels à faire,
		if(($null -ne $additionnalReplace) -and ($additionnalReplace.Count -gt 0))
		{
			# On les ajoute à la liste
			ForEach($search in $additionnalReplace)
			{
				$replace.Add($search, $additionnalReplace[$search])
			}
		}

		$body = $this.createObjectFromJSON($approvalPolicyJSON, $replace)

		# Création de la Policy
		$this.callAPI($uri, "Post", $body) | Out-Null

		# On utilise $body.name et pas simplement $name dans le cas où il y aurait un préfixe ou suffixe de nom déjà hard-codé dans 
		# le fichier JSON template
		return $this.getApprovalPolicy($body.name)
	}	

	<#
		-------------------------------------------------------------------------------------
		BUT : Change l'état d'une approval policy donnée

		IN  : $approvalPolicy		-> Approval Policy dont on veut changer l'état
		IN  : $activated			-> $true|$false pour dire si la policy est activée ou pas

		RET : L'approval policy modifiée
	#>
	[psobject] setApprovalPolicyState([PSCustomObject]$approvalPolicy, [bool]$activated)
	{
		$uri = "{0}/approval-service/api/policies/{1}" -f $this.baseUrl, $approvalPolicy.id

		# Si la policy est par hasard en "DRAFT", on ne fait rien
		if($approvalPolicy.state -eq "DRAFT")
		{
			return $approvalPolicy
		}

		if($activated)
		{
			# Si déjà active, on ne fait rien car vRA balancerait une erreur
			if($approvalPolicy.state -eq "PUBLISHED")
			{
				return $approvalPolicy
			}

			$approvalPolicy.state = "PUBLISHED"
			$approvalPolicy.stateName = "Active"
		}
		else 
		{
			# Si déjà inactive, on ne fait rien car vRA balancerait une erreur
			if($approvalPolicy.state -eq "RETIRED")
			{
				return $approvalPolicy
			}

			$approvalPolicy.state = "RETIRED"
			$approvalPolicy.stateName = "Inactive"
		}

		# Mise à jour des informations
		$this.callAPI($uri, "Put", $approvalPolicy) | Out-Null

		# on retourne spécifiquement l'objet qui est dans vRA et pas seulement celui qu'on a utilisé pour faire la mise à jour. Ceci
		# pour la simple raison que dans certains cas particuliers, on se retrouve avec des erreurs "409 Conflicts" si on essaie de
		# réutilise un élément pas mis à jour depuis vRA
		return $this.getApprovalPolicy($approvalPolicy.name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Efface une approval policy

		IN  : $approvalPolicy		-> Approval Policy qu'il faut effacer
		
		RET : rien
	#>
	[void] deleteApprovalPolicy([PSCustomObject]$approvalPolicy)
	{
		# On commence par la désactiver sinon on ne pourra pas la supprimer
		$approvalPolicy = $this.setApprovalPolicyState($approvalPolicy, $false)

		$uri = "{0}/approval-service/api/policies/{1}" -f $this.baseUrl, $approvalPolicy.id

		# Mise à jour des informations
		$this.callAPI($uri, "Delete", $null) | Out-Null
		
	}

	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Resource actions
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des actions disponibles pour une ressource donnée

		IN  : $forResource -> Objet représentant la ressource dont on veut la liste des actions.
		
		RET : Tableau avec la liste des actions
	#>
	[Array] getResourceActionList([PSCustomObject]$forResource)
	{
		
		$uri = "{0}/catalog-service/api/consumer/resources/{1}/actions" -f $this.baseUrl, $forResource.id

		# Retour de la liste
		return $this.callAPI($uri, "Get", $null).content
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie une action donnée par son nom pour la ressource passée

		IN  : $forResource 	-> Objet représentant la ressource 
		IN  : $actionName	-> Nom de l'action
		
		RET : Objet contenant l'action
				$null si pas trouvée
	#>
	[PSCustomObject] getResourceActionInfos([PSCustomObject]$forResource, [String]$actionName)
	{
		# Recherche de la liste et retour de l'action demandée 
		$list= $this.getResourceActionList($forResource)
		return $list | Where-Object { $_.name -eq $actionName }
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le template à utiliser pour effectuer une action donnée
				sur une ressource identifiée par $forResource. Ce template sera ensuite utilisé
				pour faire une 2nd action sur une ressource après avoir fait quelques 
				modifications dessus.

		IN  : $forResource 	-> Objet représentant la ressource 
		IN  : $actionName	-> Nom de l'action
		
		RET : Objet contenant le template pour exécuter l'action
	#>
	[PSCustomObject] getResourceActionTemplate([PSCustomObject]$forResource,  [String]$actionName)
	{
		$actionInfos = $this.getResourceActionInfos($forResource, $actionName)

		# Si l'action que l'on désire effectuer n'existe pas,
		if($null -eq $actionInfos)
		{
			Throw "No action named '{0}' found!" -f $actionName
		}

		# URL de recherche du template pour l'action que l'on désire effectuer
		$uri = "{0}/catalog-service/api/consumer/resources/{1}/actions/{2}/requests/template/" -f $this.baseUrl, $forResource.id, $actionInfos.id

		return $this.callAPI($uri, "Get", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
									Virtual Machines
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour une custom property sur une VM

		IN  : $vm 				-> Objet représentant la VM à mettre à jour 
		IN  : $customPropName	-> Nom de la custom property
		IN  : $customPropValue	-> Valeur de la custom property
		
		RET : rien
	#>
	[void] updateVMCustomProp([PSCustomObject]$vm, [string]$customPropName, [string]$customPropValue)
	{
		# Recherche du template de l'action de reconfiguration car c'est ce qu'on devra utiliser pour 
		# mettre à jour la custom property
		$actionTemplate = $this.getResourceActionTemplate($vm, "Reconfigure")

		# On regarde si on trouve la custom property dans la VM pour la mettre à jour
		$updateOK = $false
		Foreach($customProp in $actionTemplate.data.customProperties) 
		{
			# Si on tombe sur la propriété qu'on cherche 
			if($customProp.data.id -eq $customPropName)
			{
				$customProp.data.value = $customPropValue
				$updateOK = $true
				break
			}
		}

		# Si on n'a pas pu mettre à jour, c'est que la custom property n'existait pas dans la VM et donc il faut l'ajouter
		if(!$updateOK)
		{
			$replace = @{ customPropName = $customPropName
						  customPropValue = $customPropValue }

			# Création de la property depuis le JSON
			$newProp = $this.createObjectFromJSON("vra-resource-action-custom-prop.json", $replace)

			# Ajout à la list
			$actionTemplate.data.customProperties += $newProp
		}


		$uri = "{0}/catalog-service/api/consumer/resources/{1}/actions/{2}/requests" -f $this.baseUrl, $actionTemplate.resourceId, $actionTemplate.actionId

		# Mise à jour de la description, bien qu'elle n'apparaîtra nulle part...
		$actionTemplate.description = "Automatic Backup Tag Update"

		$this.callAPI($uri, "Post", $actionTemplate) | Out-Null

	}


}










