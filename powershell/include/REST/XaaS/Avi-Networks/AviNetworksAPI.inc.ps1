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

$global:XAAS_AVI_NETWORK_API_VERSION = "20.1.4"

class AviNetworksAPI: RESTAPICurl
{
	hidden [System.Collections.Hashtable]$headers
    

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $username	        -> Nom d'utilisateur
		IN  : $password			-> Mot de passe

	#>
	AviNetworksAPI([string] $server, [string] $username, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		# Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@("XaaS", "Avi-Networks") )

		$this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')
        $this.headers.Add('X-Avi-Version', $global:XAAS_AVI_NETWORK_API_VERSION)
        $this.headers.Add('X-Avi-Tenant', 'admin')

		$authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username, $password)))

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Basic {0}" -f $authInfos))

		$this.baseUrl = "{0}/api" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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

        RET : Objet représentant le tenant
	#>
    [PSObject] addTenant([string]$name, [string]$description)
    {
        $uri = "{0}/tenant" -f $this.baseUrl

        $replace = @{
			name = $name
			description = $description
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
	#>
    [PSObject] getTenantById([string]$id)
    {
        $uri = "{0}/tenant/{1}" -f $this.baseUrl, $id

        return $this.callAPI($uri, "GET", $null)
    }


    <#
	-------------------------------------------------------------------------------------
		BUT : Renvoie un tenant par son nom

        IN  : $nom       -> nom du tenant

        RET : Objet représentant le tenant
                $null si pas trouvé
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
		BUT : Efface un tenant

        IN  : $tenant       -> Objet représentant le tenant à effacer
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
		IN  : $adGroup		-> Nom court du groupe AD contenant les utilisateurs qui vont avoir le rôle

        RET : Tableau avec la liste des règles après ajout de la nouvelle
	#>
	[Array] addAdminAuthRule([Array]$tenantList, [PSObject]$role, [string]$adGroup)
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
		BUT : Renvoie la règle qui est utilisée pour donner les droits au tenant passé

		IN  : $forTenant	-> Objet représentant le tenant pour lequel on veut avoir la règle
		
        RET : Objet avec les détails de la règle
	#>
	[PSObject] getAdminAuthRule([PSObject]$forTenant)
	{
		return $this.getAdminAuthRuleList() | Where-Object { $_.tenant_refs -contains $forTenant.url}
	}


	[void] deleteAdminRule([PSObject]$rule)
	{
		$uri = "{0}/systemconfiguration" -f $this.baseUrl

		$replace = @{
			index = $rule.index
		}

		$body = $this.createObjectFromJSON("xaas-avi-networks-delete-systemconfiguration.json", $replace)

		$this.callAPI($uri, "PATCH", $body) | Out-Null
	}
}
