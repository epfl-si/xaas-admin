<#
   	BUT : Contient les fonctions donnant accès à l'API Avi Networks.
		
   	AUTEUR : Lucien Chaboudez
   	DATE   : Février 2021

	Documentation:
		- API: https://vsissp-avi-ctrl-t.epfl.ch/swagger/
		

	REMARQUES :
	- Cette classe hérite de RESTAPICurl. Pourquoi Curl? parce que si on utilise le CmdLet
		Invoke-RestMethod, on a une erreur de connexion refermée, et c'est la même chose 
		lorsque l'on veut parler à l'API de NSX-T. C'est pour cette raison que l'on passe
		par Curl par derrière.


#>
 

class AviNetworksAPI: RESTAPICurl
{
	hidden [System.Collections.Hashtable]$headers
	# Chemin jusqu'au fichier JSON où se trouvent les infos sur la version de l'API
	hidden [string]$pathToAPIInfos
	

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $targetEnv		-> Environnement sur lequel on est
		IN  : $server			-> Nom DNS du serveur
		IN  : $username	        -> Nom d'utilisateur
		IN  : $password			-> Mot de passe

	#>
	AviNetworksAPI([string]$targetEnv, [string] $server, [string] $username, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.pathToAPIInfos = ([IO.Path]::Combine($global:DATA_FOLDER, "XaaS", "Avi-Networks", "api-version.json"))

		if(!(Test-Path $this.pathToAPIInfos))
		{
			Throw ("Missing config file ({0})" -f $this.pathToAPIInfos)
		}

		# Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@("XaaS", "Avi-Networks") )

		$this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')
        $this.headers.Add('X-Avi-Version', $this.getAPIVersion($targetEnv))
        $this.headers.Add('X-Avi-Tenant', 'admin')

		$authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Basic {0}" -f $authInfos))

		$this.baseUrl = "{0}/api" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.updateAPIVersion($targetEnv)
    }    

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la version courante de l'API stockée dans le fichier JSON et ceci pour un 
				environnement donné
		
		IN  : $targetEnv	-> Environnement pour lequel on veut la version de l'API

		RET : No de version
	#>
	hidden [string] getAPIVersion([string]$targetEnv)
	{
		return (Get-Content -Path $this.pathToAPIInfos -Raw -Encoding:UTF8 | ConvertFrom-Json).$targetEnv.version
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Met à jour la version courante de l'API dans le fichier JSON (pour l'environnement donné)

		IN  : $targetEnv	-> Environnement pour lequel on veut mettre à jour la version de l'API

		https://vsissp-avi-ctrl-t.epfl.ch/api/image
	#>
	hidden [void] updateAPIVersion([string]$targetEnv)
	{
		$uri = "{0}/image" -f $this.baseUrl

		$res = $this.callAPI($uri, "GET", $null)

		$version = ($res.results | ForEach-Object { $_.controller_info.build.version } | Sort-Object -Descending)[0]

		# Si la version a changé par rapport au fichier JSON
		$versionInfos = (Get-Content -Path $this.pathToAPIInfos -Raw -Encoding:UTF8 | ConvertFrom-Json)
		if($versionInfos.$targetEnv.version -ne $version)
		{
			$versionInfos.$targetEnv.version = $version
			$versionInfos.$targetEnv.dateChanged = (Get-Date -Format "yyyy-MM-dd")

			# Mise à jour dans le fichier
			$versionInfos | ConvertTo-Json | Out-File $this.pathToAPIInfos -Encoding:utf8
		}
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Initialise le tenant actif sur lequel on va faire les requêtes

		IN  : $tenantName		-> nom du tenant
	#>
	hidden [void] setActiveTenant([string]$tenantName)
	{
		$this.headers.Item('X-Avi-Tenant') = $tenantName
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Repasse sur le tenant par défaut
	#>
	hidden [void] setDefaultTenant()
	{
		$this.setActiveTenant('admin')
	}


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		$nbRetries = 2
		do
		{
			# On fait un "cast" pour être sûr d'appeler la fonction de la classe courante et pas une surcharge éventuelle
			$result = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

			if(objectPropertyExists -obj $result -propertyName "error")
			{
				# De manière aléatoire, on peut avoir une erreur qui fait que le serveur LDAP n'est pas atteignable, à tous 
				# les coups c'est parce qu'en amont ils ne font aucun retry... du coup, ça a été implémenté ici.
				if(($nbRetries -gt 0) -and ($result.error -like "*LDAP server(s) not reachable*"))
				{
					$nbRetries--
					$this.debugLog("Error with LDAP servers, retrying in 2 sec")
					Start-Sleep -Seconds 2
				}
				else
				{
					Throw $result.error
				}
				
			}
			else # Pas d'erreur, on peut sortir de la boucle
			{
				break
			}
		} while($nbRetries -gt 0)

        return $result
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Récupère un objet à l'URI donnée et le renvoie. 

		IN  : $uri			-> URI où faire la requête
        IN  : $tenant		-> (optionnel) Objet représentant le tenant sur lequel faire la requête
		IN  : $method		-> (optinonel) la méthode à utiliser (POST|GET)
		
		RET : Objet si trouvé
				$null si pas trouvé
	#>
	hidden [PSCustomObject] getObject([string]$uri)
	{
		return $this.getObject($uri, $null)
	}
	hidden [PSCustomObject] getObject([string]$uri, [PSCustomObject]$tenant)
	{
		if($null -ne $tenant)
		{
			$this.setActiveTenant($tenant.name)
		}

		$res = $this.callAPI($uri, "GET", $null).results

		if($null -ne $tenant)
		{
			$this.setDefaultTenant()
		}

		if($res.count -eq 0)
		{
			return $null
		}

		return $res[0]
	}

    <# --------------------------------------------------------------------------------------------------------- 
                                                    TENANTS
       --------------------------------------------------------------------------------------------------------- #>

    
    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste de tenants existants

        RET : Tableau avec la liste des tenants

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_tenant
	#>
    [Array] getTenantList()
    {
		# On fait en sorte de retourner les "custom labels" mais on doit aussi ajouter à nouveau les "config_settings" car ils 
		# sont du coup supprimés quand on utilise le paramètre "fields"
        $uri = "{0}/tenant?fields=config_settings" -f $this.baseUrl

        return ($this.callAPI($uri, "Get", $null)).results
    }


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste de tenants existants qui correspondent aux filtres donnés pour les labels

		IN  : $labelFilters	-> Tableau associatif avec en clef le nom du label à filtrer et en valeur, 
								la valeur que le label doit avoir.

        RET : Tableau avec la liste des tenants filtrés
	#>
    [Array] getTenantList([Hashtable]$labelFilters)
    {
        $result = @()

		# Parcours des tenants existants
		$this.getTenantList() | ForEach-Object {

			$tenant = $this.getTenantById($_.uuid)

			try
			{
				$tenantLabels = $tenant.description | ConvertFrom-Json | ConvertTo-Hashtable
			}
			catch
			{
				$this.debugLog(("Tenant '{0}' doesn't have JSON in description field" -f $tenant.name))
				# On passe à l'élément suivant
				return 
			}
			
			# Si on a trouvé des labels pour le tenant courant
			if($null -ne $tenantLabels)
			{
				$match = $true
				ForEach($labelKey in $labelFilters.keys)
				{
					# Si on ne trouve pas le label courant pour le tenant courant
					if($tenantLabels.Item($labelKey) -ne $labelFilters.Item($labelKey))
					{
						# C'est qu'il ne correspond pas
						$match = $false
						break
					}
				}

				if($match)
				{
					$result += $tenant
				}

			}# FIN SI on a trouvé des labels pour le tenant courant
			
		}# FIN BOUCLE parcours des tenants existants

		return @($result)
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un tenant

        IN  : $name         -> Nom du tenant
        IN  : $labels		-> Tableau associatif avec les labels à mettre au tenant

        RET : Objet représentant le tenant

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_tenant
	#>
    [PSCustomObject] addTenant([string]$name, [Hashtable]$labels)
    {
        $uri = "{0}/tenant" -f $this.baseUrl

        $replace = @{
			name = $name
			description = (ConvertTo-json $labels -Compress) -replace '"','\"'
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-tenant.json", $replace)

        return $this.callAPI($uri, "POST", $body) 
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un tenant par son ID

        IN  : $id       -> ID du tenant

        RET : Objet représentant le tenant
                Exception si le tenant n'existe pas

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_tenant__uuid_
	#>
    [PSCustomObject] getTenantById([string]$id)
    {
        $uri = "{0}/tenant/{1}" -f $this.baseUrl, $id

        return $this.callAPI($uri, "GET", $null)
    }


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie les tenants (un par environnement) par leur ID "custom"

        IN  : $customId       -> ID custom du tenant

        RET : Tableau avec les objets représentant le tenant
               $null si pas trouvé
	#>
    [Array] getTenantByCustomIdList([string]$customId)
    {
        return $this.getTenantList() | Where-Object { 
			$_.suggested_object_labels | Where-Object { 
				($_.key -eq $global:VRA_CUSTOM_PROP_EPFL_BG_ID) -and ($_.value -eq $customId )
			} 
		}
    }
	

    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un tenant par son nom

        IN  : $nom       -> nom du tenant

        RET : Objet représentant le tenant
                $null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_tenant
	#>
    [PSCustomObject] getTenantByName([string]$name)
    {
		$uri = "{0}/tenant?name={1}" -f $this.baseUrl, $name
		return $this.getObject($uri)

    }


	<#
	-------------------------------------------------------------------------------------
		BUT : Met à jour le nom et la description d'un tenant.

        IN  : $tenant 	-> Objet représentant le tenant
		IN  : $newName	-> Nouveau nom
		IN  : $newDesc	-> Nouvelle description

		RET : Le tenant modifié

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_tenant__uuid_
	#>
	[PSCustomObject] updateTenant([PSCustomObject]$tenant, [string]$newName, [string]$newDesc)
	{
		$uri = "{0}/tenant/{1}" -f $this.baseUrl, $tenant.uuid

		$tenant.name = $newName
		$tenant.description = $newDesc

		$this.callAPI($uri, "PUT", $tenant) | Out-Null

		return $tenant
	}


    <#
	-------------------------------------------------------------------------------------
		BUT : Efface un tenant

        IN  : $tenant       -> Objet représentant le tenant à effacer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_tenant__uuid_
	#>
    [void] deleteTenant([PSCustomObject]$tenant)
    {
        $uri = "{0}/tenant/{1}" -f $this.baseUrl, $tenant.uuid

        $this.callAPI($uri, "DELETE", $null) | Out-Null
    }


	<# --------------------------------------------------------------------------------------------------------- 
                                            		ROLES
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un role donné par son nom

        IN  : $name       -> Nom du rôle

		RET : Objet représentant le rôle
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_role
	#>
	[PSCustomObject] getRoleByName([string]$name)
	{
		$uri = "{0}/role?name={1}" -f $this.baseUrl, $name
		return $this.getObject($uri)

	}

	<# --------------------------------------------------------------------------------------------------------- 
                                            	ADMIN AUTH CONFIGURATION
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la configuration système de tout

        RET : Objet avec la configuration système

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_systemconfiguration
	#>
	hidden [PSCustomObject] getSystemConfiguration()
	{
		$uri = "{0}/systemconfiguration" -f $this.baseUrl

		return $this.callAPI($uri, "GET", $null)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des règles d'authentification actuellement appliquées

        RET : Tableau avec la liste de ce qui est appliqué
	#>
	[Array] getAdminAuthRuleList()
	{
		return $this.getSystemConfiguration().admin_auth_configuration.mapping_rules
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une règle d'authentification pour un ou plusieurs tenants

		IN  : $tenantRefList	-> Tableau avec la liste des références (URL) des tenants auxquels
									appliquer une nouvelle règle
		IN  : $roleRef			-> Référence (URL) sur le role à appliquer
		IN  : $adGroup			-> Nom court du groupe AD contenant les utilisateurs qui vont avoir le rôle
		IN  : $ruleIndex		-> (optionnel) index de la règle dans le cas où on veut faire un "Update"
									On passe -1 si on veut ajouter une règle

        RET : Tableau avec la liste des règles après ajout de la nouvelle

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_systemconfiguration

		Dans le WebUI, c'est dans "Adminitration" > "Settings" > "Authentication/Authorization"
	#>
	hidden [Array] addOrUpdateAdminAuthRule([Array]$tenantRefList, [string]$roleRef, [String]$adGroup, [int]$ruleIndex)
	{
		$uri = "{0}/systemconfiguration" -f $this.baseUrl

		$systemConfig = $this.getSystemConfiguration()

		# Si on doit faire un ajout, on doit rechercher le bon index
		if($ruleIndex -eq -1)
		{
			# Recherche du prochain index dispo
			$usedIndexList = @($systemConfig.admin_auth_configuration.mapping_rules | Select-Object -ExpandProperty index | Sort-Object)

			# Index de départ (aucune idée si on peut partir à 0 donc on part à 1)
			$ruleIndex = 1
			# Recherche du premier index libre
			While($usedIndexList -contains $ruleIndex) {
				$ruleIndex++
			}
		}		

		$replace = @{
			tenantRefList = @( ( ConvertTo-Json @($tenantRefList)), $true)
			index = $ruleIndex
			roleRef = $roleRef
			adGroup = $adGroup
			authProfileRef = $systemConfig.admin_auth_configuration.auth_profile_ref
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-new-systemconfiguration.json", $replace)

		$this.callAPI($uri, "PATCH", $body) | Out-Null
		
		# Retour de la liste mise à jour
		return $this.getAdminAuthRuleList()
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une règle d'authentification pour un ou plusieurs tenants

		IN  : $tenantList	-> Tableau avec la liste des objets représentant des tenants auxquels
								appliquer une nouvelle règle
		IN  : $role			-> Objet représentant le role à appliquer
		IN  : $adGroup		-> Nom court du groupe AD contenant les utilisateurs qui vont avoir le rôle

        RET : Tableau avec la liste des règles après ajout de la nouvelle

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_systemconfiguration

		Dans le WebUI, c'est dans "Adminitration" > "Settings" > "Authentication/Authorization"
	#>
	[Array] addAdminAuthRule([Array]$tenantList, [PSCustomObject]$role, [String]$adGroup)
	{
		return $this.addOrUpdateAdminAuthRule(@($tenantList | Select-Object -ExpandProperty url), $role.url, $adGroup, -1)
	}
	
	
	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un tenant dans une règle d'authentification

		IN  : $rule			-> Objet représentant la règle à modifier
		IN  : $tenantList	-> Tableau avec les objets représentant les tenants à ajouter

        RET : Tableau avec la liste des références (URL) sur les tenants qui sont dans
				la règle après modification
	#>
	[Array] addTenantsToAdminAuthRule([PSCustomObject]$rule, [Array]$tenantList)
	{
		$updateNeeded = $false

		# Ajout des tenants manquants dans la liste
		$tenantList | Foreach-Object {
			if($rule.tenant_refs -notcontains $_.url)
			{
				# On ajoute la référence du nouveau tenant
				$rule.tenant_refs += $_.url	
				# Pour dire qu'on doit mettre à jour
				$updateNeeded = $true
			}
		}
		
		# Au moins un tenant a été ajouté à la liste
		if($updateNeeded)
		{
			# Mise à jour
			$this.addOrUpdateAdminAuthRule($rule.tenant_refs, $rule.role_refs[0], $rule.group_match.groups[0], $rule.index) | Out-Null
		}
	
		return @($rule.tenant_refs)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime un tenant d'une règle d'authentification

		IN  : $rule			-> Objet représentant la règle à modifier
		IN  : $tenant		-> Tableau avec les objets représentant les tenants à supprimer

        RET : Bool pour dire si la règle est maintenant exempte de tout tenant ou pas.
	#>
	[bool] removeTenantFromAdminAuthRule([PSCustomObject]$rule, [PSCustomObject]$tenant)
	{
		if($rule.tenant_refs -contains $tenant.url)
		{
			# On supprime la référence à supprimer
			$rule.tenant_refs = @($rule.tenant_refs | Where-Object { $_ -ne $tenant.url })

			# Mise à jour
			$this.addOrUpdateAdminAuthRule($rule.tenant_refs, $rule.role_refs[0], $rule.group_match.groups[0], $rule.index) | Out-Null
		}
		
		return @($rule.tenant_refs).count -eq 0
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un tableau avec la liste des règles qui sont utilisée pour donner les droits au tenant passé.

		IN  : $forTenant	-> Objet représentant le tenant pour lequel on veut avoir la règle
		
        RET : Tableau avec la liste des règles

		REMARQUES: 
		- Les règles en question sont peut être aussi utilisées pour d'autres tenants
		- La règle "SuperUser" n'est pas retournée
	#>
	[Array] getTenantAdminAuthRuleList([PSCustomObject]$forTenant)
	{
		return @($this.getAdminAuthRuleList() | Where-Object { 
			$null -ne $forTenant.url -and ` # On check que pas $null car si n'existe pas, c'est qu'on est peut-être dans la règle "SuperUser"
			$_.tenant_refs -contains $forTenant.url
		})
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Efface une règle d'authentification

		IN  : $rule	-> Objet représentant la règle à effacer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_systemconfiguration
	#>
	[void] deleteAdminAuthRule([PSCustomObject]$rule)
	{
		$uri = "{0}/systemconfiguration" -f $this.baseUrl

		$replace = @{
			index = $rule.index
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-delete-systemconfiguration.json", $replace)

		$this.callAPI($uri, "PATCH", $body) | Out-Null
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            	ALERT MAIL CONFIG
       --------------------------------------------------------------------------------------------------------- #>


	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une configuration mail pour les alertes sur un tenant donné

		IN  : $tenant	-> Objet représentant le tenant sur lequel créer la config
		IN  : $mailList	-> Tableau avec la liste des mails à mettre

		RET : Objet représentant la configuration d'alerte mail créée

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_alertemailconfig
	#>
	[PSCustomObject] addAlertMailConfig([PSCustomObject]$tenant, [Array]$mailList)
	{
		$this.setActiveTenant($tenant.name)
		$uri = "{0}/alertemailconfig" -f $this.baseUrl

		$replace = @{
			mailList = ($mailList -join ",")
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-alert-email-config.json", $replace)

		$res = $this.callAPI($uri, "POST", $body)

		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des configurations mail pour les alertes sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les configuration mail

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertemailconfig
	#>
	[Array] getAlertMailConfigList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertemailconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les AlertMailConfig définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results | Where-Object  {$_.tenant_ref -eq $tenant.url }
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime une configuration mail pour les alertes sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant sur lequel supprimer la config
		IN  : $alertMailConfig	-> Config à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_alertemailconfig__uuid_
	#>
	[void] deleteAlertMailConfig([PSCustomObject]$tenant, [PSCustomObject]$alertMailConfig)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertemailconfig/{1}" -f $this.baseUrl, $alertMailConfig.uuid

		$this.callAPI($uri, "DELETE", $null) | Out-Null
		$this.setDefaultTenant()
	}




	<# --------------------------------------------------------------------------------------------------------- 
                                            	ALERT GROUP CONFIG
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un niveau d'alerte mail

		IN  : $tenant			-> Objet représentant le tenant sur lequel créer le niveau d'alerte
		IN  : $alertMailConfig	-> Objet représentant la configuration mail à lier (obtenu par addAlertMailConfig() )
		IN  : $sysLogConfig		-> Objet représentant la configuration d'alerting Syslog (obtenu par getAlertSyslogConfig())
		IN  : $alertName		-> Nom de l'alerte
		IN  : $levelName		-> Nom du niveau d'alerte

		RET : Objet représentant la configuration d'alerte créée

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_actiongroupconfig
	#>
	[PSCustomObject] addActionGroupConfig([PSCustomObject]$tenant, [PSCustomObject]$alertMailConfig, [PSCustomObject]$sysLogConfig, [string]$alertName, [string]$levelName)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/actiongroupconfig" -f $this.baseUrl

		$replace = @{
			alertName = $alertName
			alertLevel = $levelName
			mailConfigRef = $alertMailConfig.url
			syslogConfigRef = $sysLogConfig.url
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-action-group-config.json", $replace)

		$res = $this.callAPI($uri, "POST", $body)

		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des niveaux d'alerte mail sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les niveaux d'alerte

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_actiongroupconfig
	#>
	[Array] getActionGroupConfigList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/actiongroupconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les ActionLevel définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results | Where-Object  {$_.tenant_ref -eq $tenant.url }
		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un niveau d'alerte mail sur un tenant donné

		IN  : $tenant	-> Objet représentant le tenant pour lequel on veut le niveau d'alerte
		IN  : $name		-> Nom du niveau d'alerte

		RET : Objet avec le niveau d'alerte
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_actiongroupconfig
	#>
	[PSCustomObject] getActionGroupConfig([PSCustomObject]$tenant, [string]$name)
	{
		$uri = "{0}/actiongroupconfig?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri, $tenant)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime un niveau d'alerte mail

		IN  : $tenant			-> Objet représentant le tenant sur lequel supprimer le niveau d'alerte
		IN  : $alertActionLevel	-> Niveau d'alerte à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_actiongroupconfig__uuid_
	#>
	[void] deleteActionGroupConfig([PSCustomObject]$tenant, [PSCustomObject]$alertActionLevel)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/actiongroupconfig/{1}" -f $this.baseUrl, $alertActionLevel.uuid

		$this.callAPI($uri, "DELETE", $null) | Out-Null
		$this.setDefaultTenant()
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            	ALERT CONFIG
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute une alerte pour un événement sur un élément (statut qui change)

		IN  : $tenant			-> Objet représentant le tenant sur lequel créer le niveau d'alerte
		IN  : $alertActionLevel	-> Objet représentant le niveaud d'alerte à lier (obtenue par addActionGroupConfig() )
		IN  : $element			-> Element sur lequel l'alerte s'applique
		IN  : $status			-> Le statut pour lequel on veut une alerte
		IN  : $name				-> Nom de l'alert config

		RET : Objet représentant la configuration d'alerte créée

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_alertconfig
	#>
	[PSCustomObject] addAlertConfig([PSCustomObject]$tenant, [PSCustomObject]$alertActionLevel, [XaaSAviNetworksMonitoredElements]$element, [XaaSAviNetworksMonitoredStatus]$status, [string]$name)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig" -f $this.baseUrl

		# Génération du nom du fichier JSON à utiliser
		$jsonFile = "xaas-avi-networks-alert-config-{0}-{1}.json" -f $element.toString().toLower(), $status.toString().toLower()

		$replace = @{
			actionGroupRef = $alertActionLevel.url
			name = $name
		}

		$body = $this.createObjectFromJSON($jsonFile, $replace)

		$res = $this.callAPI($uri, "POST", $body)

		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des alertes configurées sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les alertes configurées

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertconfig
	#>
	[Array] getAlertConfigList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les AlertConfig définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results | Where-Object  {$_.tenant_ref -eq $tenant.url }
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie une alerte configurées sur un tenant donné, par son nom

		IN  : $tenant	-> Objet représentant le tenant sur lequel se trouve l'alert config
		IN  : $name		-> Nom de l'Alert Config	

		RET : Objet avec l'alert config
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertconfig
	#>
	[PSCustomObject] getAlertConfig([PSCustomObject]$tenant, [string]$name)
	{
		$uri = "{0}/alertconfig?name={1}" -f $this.baseUrl, $name
		return $this.getObject($uri, $tenant)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des alertes configurées sur un tenant et un élément donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste
		IN  : $forElement		-> Objet représentant l'élément pour lequel on veut les "Alert Config"

		RET : Tableau avec les alertes configurées

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertconfig
	#>
	[Array] getAlertConfigList([PSCustomObject]$tenant, [XaaSAviNetworksMonitoredElements]$forElement)
	{
		return @($this.getAlertConfigList($tenant) | Where-Object { $_.object_type -eq $forElement.toString()})
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime une alerte pour une événement et un statut

		IN  : $tenant		-> Objet représentant le tenant sur lequel supprimer la config
		IN  : $alertConfig	-> Niveau d'alerte à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_alertconfig__uuid_
	#>
	[void] deleteAlertConfig([PSCustomObject]$tenant, [PSCustomObject]$alertConfig)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig/{1}" -f $this.baseUrl, $alertConfig.uuid

		$this.callAPI($uri, "DELETE", $null) | Out-Null
		$this.setDefaultTenant()
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            	ALERT SYSLOG CONFIG
       --------------------------------------------------------------------------------------------------------- #>
	
	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des configuration d'alertes SysLog sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les configurations d'alertes syslog

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertsyslogconfig
	#>
	[Array] getAlertSyslogConfigList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertsyslogconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les AlertConfig définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results 
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie une configuration d'alerte Syslog sur un tenant donné, par son nom

		IN  : $name		-> Nom de la configuration d'alerte syslog

		RET : Objet avec la configuration
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_alertsyslogconfig
	#>
	[PSCustomObject] getAlertSyslogConfig([string]$name)
	{
		$uri = "{0}/alertsyslogconfig?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            		POOLS
       --------------------------------------------------------------------------------------------------------- #>


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des pools sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les pools

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_pool
	#>
	[Array] getPoolList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/pool" -f $this.baseUrl

		$res = $this.callAPI($uri, "GET", $null).results
		$this.setDefaultTenant()

		return @($res)
	}



	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un pool qui est sur un tenant donné, par son nom

		IN  : $tenant	-> Objet représentant le tenant sur lequel se trouve le pool
		IN  : $name		-> Nom du pool

		RET : Objet avec le pool
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_pool
	#>
	[PSCustomObject] getPool([PSCustomObject]$tenant, [string]$name)
	{
		$uri = "{0}/pool?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri, $tenant)
	}



	# [PSCustomObject] addPool([PSCustomObject]$tenant)
	# {
	# 	$this.setActiveTenant($tenant.name)

	# 	$uri = "{0}/pool" -f $this.baseUrl

	# 	$replace = @{
	# 		actionGroupRef = $alertActionLevel.url
	# 		name = $name
	# 	}

	# 	$body = $this.createObjectFromJSON($jsonFile, $replace)

	# 	$res = $this.callAPI($uri, "POST", $body).results
	# 	$this.setDefaultTenant()
	# }


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie les infos de runtime pour un pool donné

		IN  : $tenant			-> Objet représentant le tenant sur lequel se trouve le pool
		IN  : $pool				-> Objet représentant le pool
		IN  : $serverDetails	-> (optionnel) $true|$false pour dire si on veut, à la place, la liste détaillée

		RET : Objet avec les infos du pool

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_pool__uuid__runtime_
	#>
	[PSCustomObject] getPoolRuntime([PSCustomObject]$tenant, [PSCustomObject]$pool)
	{
		return $this.getPoolRuntime($tenant, $pool, $false)
	}
	[PSCustomObject] getPoolRuntime([PSCustomObject]$tenant, [PSCustomObject]$pool, [bool]$serverDetails)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/pool/{1}/runtime/" -f $this.baseUrl, $pool.uuid

		# Si on veut les détails sur les serveurs
		if($serverDetails)
		{
			$uri = "{0}server/" -f $uri
		}

		$res = $this.callAPI($uri, "GET", $null)
		$this.setDefaultTenant()

		if($res.count -eq 0)
		{
			return $null
		}

		return $res[0]
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            VIRTUAL SERVICE
       --------------------------------------------------------------------------------------------------------- #>


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des virtuals services sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les virtual services

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_virtualservice
	#>
	[Array] getVirtualServiceList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/virtualservice/" -f $this.baseUrl

		$res = $this.callAPI($uri, "GET", $null).results
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un virtual service qui est sur un tenant donné, par son nom

		IN  : $tenant	-> Objet représentant le tenant sur lequel se trouve le virtual service
		IN  : $name		-> Nom du virtual service

		RET : Objet avec le virtual service
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_virtualservice
	#>
	[PSCustomObject] getVirtualService([PSCustomObject]$tenant, [string]$name)
	{
		$uri = "{0}/virtualservice?name={1}" -f $this.baseUrl, $name
		return $this.getObject($uri, $tenant)
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            		CLOUDS
       --------------------------------------------------------------------------------------------------------- #>


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Clouds sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les clouds

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_cloud
	#>
	[Array] getCloudList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/cloud" -f $this.baseUrl

		$res = $this.callAPI($uri, "GET", $null).results
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un cloud qui est sur un tenant donné, par son nom

		IN  : $type		-> Le type du cloud

		RET : Objet avec le cloud
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_cloud
	#>
	[PSCustomObject] getCloudByType([string]$type)
	{
		$uri = "{0}/cloud?vtype={1}" -f $this.baseUrl, $type
		return $this.getObject($uri)
		
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            	HEALTH MONITOR
       --------------------------------------------------------------------------------------------------------- #>


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Health Monitor sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant pour lequel on veut la liste

		RET : Tableau avec les Health Monitor

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_healthmonitor
	#>
	[Array] getHealthMonitorList([PSCustomObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/healthmonitor" -f $this.baseUrl

		$res = $this.callAPI($uri, "GET", $null).results
		$this.setDefaultTenant()

		return @($res)
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un health monitor qui est sur un tenant donné, par son nom

		IN  : $tenant	-> Objet représentant le tenant sur lequel se trouve le health monitor
		IN  : $name		-> Nom du health monitor

		RET : Objet avec le health monitor
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_healthmonitor
	#>
	[PSCustomObject] getHealthMonitor([PSCustomObject]$tenant, [string]$name)
	{
		$uri = "{0}/healthmonitor?name={1}" -f $this.baseUrl, $name
		return $this.getObject($uri, $tenant)
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            	APPLICATION PROFILE
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un application profile donné par son nom

		IN  : $name		-> Nom du application profile

		RET : Objet avec le application profile
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_applicationprofile
	#>
	[PSCustomObject] getApplicationProfile([string]$name)
	{
		$uri = "{0}/applicationprofile?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}
	

	<# --------------------------------------------------------------------------------------------------------- 
                                            	STRING GROUP
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un string group donné par son nom

		IN  : $tenant	-> Objet représentant le tenant sur lequel se trouve le string group
		IN  : $name		-> Nom du application profile

		RET : Objet avec le application profile
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_applicationprofile
	#>
	[PSCustomObject] getStringGroup([string]$name)
	{
		$uri = "{0}/stringgroup?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}
	

	<# --------------------------------------------------------------------------------------------------------- 
                                            	VRF Context
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un VRF Context donné par son nom

		IN  : $name		-> Nom du application profile

		RET : Objet avec le application profile
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_vrfcontext
	#>
	[PSCustomObject] getVRFContext([string]$name)
	{
		$uri = "{0}/vrfcontext?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}


	<# --------------------------------------------------------------------------------------------------------- 
                                            SERVICE ENGINE GROUP
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un service engine group donné par son nom

		IN  : $name		-> Nom du service engine group

		RET : Objet avec le service engine group
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_serviceenginegroup
	#>
	[PSCustomObject] getServiceEngineGroup([string]$name)
	{
		$uri = "{0}/serviceenginegroup?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}


	<# --------------------------------------------------------------------------------------------------------- 
												NETWORK
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un network donné par son nom

		IN  : $name		-> Nom du network

		RET : Objet avec le network
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_network
	#>
	[PSCustomObject] getNetwork([string]$name)
	{
		$uri = "{0}/network?name={1}" -f $this.baseUrl, $name

		return $this.getObject($uri)
	}

	
	<# --------------------------------------------------------------------------------------------------------- 
												TIERS
       --------------------------------------------------------------------------------------------------------- #>

	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un tier de cloud donné par son nom

		IN  : $vrfContext	-> Objet réprésentant le cloud
		IN  : $name			-> Le nom du tier que l'on cherche

		RET : Objet avec le tier
				$null si pas trouvé

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/get_network
	#>
	[PSCustomObject] getTier([PSCustomObject]$cloud, [string]$name)
	{
		$uri = "{0}/nsxt/tier1s" -f $this.baseUrl

		$replace = @{
			cloudUUID = $cloud.uuid
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-tier.json", $replace)

        $res = $this.callAPI($uri, "POST", $body)

		if($null -ne $res)
		{
			$res = $res.resource.nsxt_tier1routers | Where-Object { $_.name -eq $name }
		}
		return $res

	}
}
