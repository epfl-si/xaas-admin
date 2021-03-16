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
		# Oui, cette ligne est débile... pourquoi on la met? simplement parce qu'il semblerait que du côté AVI, ils ne gèrent pas 
		# "si bien que ça" le fait que plein de requêtes REST arrivent à la suite... 
		Start-Sleep -Seconds 1

		# On fait un "cast" pour être sûr d'appeler la fonction de la classe courante et pas une surcharge éventuelle
		$result = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

        if(objectPropertyExists -obj $result -propertyName "error")
        {
            Throw $result.error
        }

        return $result
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
        $uri = "{0}/tenant" -f $this.baseUrl

        return ($this.callAPI($uri, "Get", $null)).results
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un tenant

        IN  : $name         -> Nom du tenant
        IN  : $description  -> Description du tenant
		IN  : $labels		-> Tableau associatif avec les labels à mettre au tenant

        RET : Objet représentant le tenant

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_tenant
	#>
    [PSObject] addTenant([string]$name, [string]$description, [Hashtable]$labels)
    {
        $uri = "{0}/tenant" -f $this.baseUrl

        $replace = @{
			name = $name
			description = $description
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-tenant.json", $replace)

		# Ajout des labels
		$labels.Keys | ForEach-Object {
			$replace = @{
				key = $_
				value = $labels.item($_)
			}
			$body.suggested_object_labels += $this.createObjectFromJSON("xaas-avi-networks-tenant-label.json", $replace)
		}

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
    [PSObject] getTenantById([string]$id)
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
    [PSObject] getTenantByName([string]$name)
    {
        $uri = "{0}/tenant?name={1}" -f $this.baseUrl, $name

        $res = $this.callAPI($uri, "GET", $null).results

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
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
	[PSObject] updateTenant([PSObject]$tenant, [string]$newName, [string]$newDesc)
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
    [void] deleteTenant([PSObject]$tenant)
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
	[PSObject] getRoleByName([string]$name)
	{
		$uri = "{0}/role?name={1}" -f $this.baseUrl, $name

		$res = $this.callAPI($uri, "GET", $null).results

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
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
	hidden [psobject] getSystemConfiguration()
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

		IN  : $tenantList	-> Tableau avec la liste des objets représentant des tenants auxquels
								appliquer une nouvelle règle
		IN  : $role			-> Objet représentant le role à appliquer
		IN  : $adGroupList	-> Tableau avec les noms courts des groupe AD contenant les utilisateurs 
								qui vont avoir le rôle

        RET : Tableau avec la liste des règles après ajout de la nouvelle

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_systemconfiguration
	#>
	[Array] addAdminAuthRule([Array]$tenantList, [PSObject]$role, [Array]$adGroupList)
	{
		$uri = "{0}/systemconfiguration" -f $this.baseUrl

		$systemConfig = $this.getSystemConfiguration()

		# Recherche du prochain index dispo
		$usedIndexList = @($systemConfig.admin_auth_configuration.mapping_rules | Select-Object -ExpandProperty index | Sort-Object)

		# Index de départ (aucune idée si on peut partir à 0 donc on part à 1)
		$index = 1
		# Recherche du premier index libre
		While($usedIndexList -contains $index) {
			$index++
		}

		$replace = @{
			tenantRefList = @( ( @($tenantList | Select-Object -ExpandProperty url) | ConvertTo-Json), $true)
			index = $index
			roleRef = $role.url
			adGroupList = @( ( $adGroupList | ConvertTo-Json), $true)
			authProfileRef = $systemConfig.admin_auth_configuration.auth_profile_ref
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-new-systemconfiguration.json", $replace)

		$this.callAPI($uri, "PATCH", $body) | Out-Null
		
		# Retour de la liste mise à jour
		return $this.getAdminAuthRuleList()
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Renvoie la règle qui est utilisée pour donner les droits au tenant passé

		IN  : $forTenant	-> Objet représentant le tenant pour lequel on veut avoir la règle
		
        RET : Objet avec les détails de la règle
	#>
	[PSObject] getTenantAdminAuthRule([PSObject]$forTenant)
	{
		return $this.getAdminAuthRuleList() | Where-Object { $_.tenant_refs -contains $forTenant.url}
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Efface une règle d'authentification

		IN  : $rule	-> Objet représentant la règle à effacer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/patch_systemconfiguration
	#>
	[void] deleteAdminAuthRule([PSObject]$rule)
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
	[PSObject] addAlertMailConfig([PSObject]$tenant, [Array]$mailList)
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
	[Array] getAlertMailConfigList([PSObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertemailconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les AlertMailConfig définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results | Where-Object  {$_.tenant_ref -eq $tenant.url }
		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime une configuration mail pour les alertes sur un tenant donné

		IN  : $tenant			-> Objet représentant le tenant sur lequel supprimer la config
		IN  : $alertMailConfig	-> Config à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_alertemailconfig__uuid_
	#>
	[void] deleteAlertMailConfig([PSObject]$tenant, [PSObject]$alertMailConfig)
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
		IN  : $alertMailConfig	-> Objet représentant la configuration mail à lier (obtenue par addAlertMailConfig() )
		IN  : $alertName		-> Nom de l'alerte
		IN  : $levelName		-> Nom du niveau d'alerte

		RET : Objet représentant la configuration d'alerte créée

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_actiongroupconfig
	#>
	[PSObject] addActionGroupConfig([PSObject]$tenant, [PSObject]$alertMailConfig, [string]$alertName, [string]$levelName)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/actiongroupconfig" -f $this.baseUrl

		$replace = @{
			alertName = $alertName
			alertLevel = $levelName
			mailConfigRef = $alertMailConfig.url
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
	[Array] getActionGroupConfigList([PSObject]$tenant)
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
		BUT : Supprime un niveau d'alerte mail

		IN  : $tenant			-> Objet représentant le tenant sur lequel supprimer le niveau d'alerte
		IN  : $alertActionLevel	-> Niveau d'alerte à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_actiongroupconfig__uuid_
	#>
	[void] deleteActionGroupConfig([PSObject]$tenant, [PSObject]$alertActionLevel)
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

		RET : Objet représentant la configuration d'alerte créée

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/post_alertconfig
	#>
	[PSObject] addAlertConfig([PSObject]$tenant, [PSObject]$alertActionLevel, [XaaSAviNetworksMonitoredElements]$element, [XaaSAviNetworksMonitoredStatus]$status)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig" -f $this.baseUrl

		# Génération du nom du fichier JSON à utiliser
		$jsonFile = "xaas-avi-networks-alert-config-{0}-{1}.json" -f $element.toString().toLower(), $status.toString().toLower()

		$replace = @{
			actionGroupRef = $alertActionLevel.url
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
	[Array] getAlertConfigList([PSObject]$tenant)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig" -f $this.baseUrl

		# Recherche. Et on filtre aussi pour avoir uniquement les AlertConfig définies pour le tenant car
		# par défaut il va aussi renvoyr les "admin"
		$res = $this.callAPI($uri, "GET", $null).results | Where-Object  {$_.tenant_ref -eq $tenant.url }
		$this.setDefaultTenant()

		return $res
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Supprime une alerte pour une événement et un statut

		IN  : $tenant		-> Objet représentant le tenant sur lequel supprimer la config
		IN  : $alertConfig	-> Niveau d'alerte à supprimer

		https://vsissp-avi-ctrl-t.epfl.ch/swagger/#/default/delete_alertconfig__uuid_
	#>
	[void] deleteAlertConfig([PSObject]$tenant, [PSObject]$alertConfig)
	{
		$this.setActiveTenant($tenant.name)

		$uri = "{0}/alertconfig/{1}" -f $this.baseUrl, $alertConfig.uuid

		$this.callAPI($uri, "DELETE", $null) | Out-Null
		$this.setDefaultTenant()
	}
}
