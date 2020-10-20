<#
   BUT : Contient les fonctions donnant accès à l'API de PKS (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

    
	Documentation:
	https://orchestration.io/2019/04/08/getting-started-with-the-pks-api/

	https://pks-t.epfl.ch:9021/v2/api-docs puis copier le JSON dans https://editor.swagger.io/ pour avoir
	une présentation un peu plus human-readable ^^'


	REMARQUES:
	- On hérite de RESTAPICurl et pas RESTAPI parce que sur les machines de test/prod, il y a des problèmes
	de connexion refermée...

#>



class PKSAPI: RESTAPICurl
{
	hidden [string]$token
	

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $user         	-> Nom d'utilisateur 
		IN  : $password			-> Mot de passe

		Documentation:
	#>
	PKSAPI([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.server = $server

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.headers.Add('Accept', 'application/json;charset=utf-8')

		# Ajout pour le login
		$this.headers.Add('Content-Type', 'application/x-www-form-urlencoded;charset=utf-8')

		$body = "grant_type=client_credentials"
		$uri = "https://{0}:8443/oauth/token" -f $this.server

		# Récupération du token
		$this.token = ($this.callAPI($uri, "POST", $body, ("-u {0}:{1}" -f $user, $password))).access_token


		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Bearer {0}" -f $this.token))

		# On met à jour pour les requêtes futures
		$this.headers.Remove('Content-Type')
		$this.headers.Add('Content-Type', 'application/json')
    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
				de pouvoir gérer de manière spécifique les messages d'erreur renvoyés par l'API

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		return $this.callAPI($uri, $method, $body, "")
	}
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$extraArgs)
	{
		# Appel de la fonction parente
		$res = ([RESTAPICurl]$this).callAPI($uri, $method, $body, $extraArgs)

		# Si on a un message d'erreur
		if([bool]($res.PSobject.Properties.name -match "error") -and ($res.error -ne ""))
		{
			# Création de l'erreur de base 
			Throw ("{0}::{1}(): {2} -> {3}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.error, $res.error_description)
		}

		# Check si pas trouvé
		if([bool]($res.PSobject.Properties.name -match "body"))
		{
			# Si on a un message qui dit "machin truc not found"
			if($res.body -like "*not found*")
			{
				# On n'a rien trouvé
				return $null
			}
			else # on doit donc probablement avoir un message d'erreur
			{
				Throw ("{0}::{1}(): {2}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.body)
			}
			
		}

		return $res
	}
	

	<#
        =====================================================================================
											CLUSTERS
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Attend qu'une action sur un cluster soit terminée. Cela peut être une action de
				création ou de suppression. C'est pour cette dernière qu'on check aussi si 
				$cluster est différent de $null

		IN  : $clusterName	-> nom du cluster
	#>
	hidden [void] waitForClusterAction([string]$clusterName)
	{	
		$cluster = $null
		do
		{
			Start-Sleep -Seconds 10
			$cluster = $this.getCluster($clusterName)
		} while (($null -ne $cluster) -and ($cluster.last_action_state -eq "in progress"))

		# Si ça ne s'est pas terminé correctement
		if(($null -ne $cluster) -and ($cluster.last_action_state -ne "succeeded"))
		{
			Throw(("Error on cluster '{0}' with action '{1}'. Description is '{2}'" -f $clusterName, $cluster.last_action, $cluster.last_action_description))
		}
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des clusters avec possibilité de filtrer

		IN  : $queryParams	-> Paramètres pour la query

		RET : Tableau avec les résultats
	#>
	hidden [Array] getClusterListQuery([string]$queryParams)
    {
        $uri = "https://{0}:9021/v1/clusters" -f $this.server

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}?{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null)
	}
	

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des clusters
	#>
	[Array] getClusterList()
	{
		return $this.getClusterListQuery("")
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un cluster d'une manière détaillée

		IN  : $clusterName		-> Le nom du cluster

		NOTE: Cette fonction a été implémentée mais à priori, la fonction 'getCluster(..)' renvoie
				exactement la même chose...
	#>
	[PSObject] getClusterDetails([string]$clusterName)
	{
		$uri = "https://{0}:9021/v1/clusterdetails/{1}" -f $this.server, [System.Net.WebUtility]::UrlEncode($clusterName)

		return $this.callAPI($uri, "GET", $null)
		
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un cluster

		IN  : $clusterName		-> Le nom du cluster
	#>
	[PSObject] getCluster([string]$clusterName)
	{
		$uri = "https://{0}:9021/v1/clusters/{1}" -f $this.server, [System.Net.WebUtility]::UrlEncode($clusterName)

		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un cluster

		IN  : $clusterName		-> Le nom du cluster
	#>
	[void] deleteCluster([string]$clusterName)
	{
		$uri = "https://{0}:9021/v1/clusters/{1}" -f $this.server, [System.Net.WebUtility]::UrlEncode($clusterName)

		$this.callAPI($uri, "DELETE", $null) | Out-Null

		$this.waitForClusterAction($clusterName)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un cluster

		IN  : $clusterName		-> Le nom du cluster
		IN  : $planName			-> Le nom du plan
		IN  : $netProfileName	-> Le nom du network profile
		IN  : $dnsHostName		-> Nom DNS à utiliser

		RET : Objet représentant le cluster
	#>
	[PSObject] addCluster([string]$clusterName, [string]$planName, [string]$netProfileName, [string]$dnsHostName)
	{
		$uri = "https://{0}:9021/v1/clusters/" -f $this.server

		# Valeur à mettre pour la configuration du BG
		$replace = @{
			clusterName = $clusterName
			planName = $planName
			netProfileName = $netProfileName
			dnsHostName = $dnsHostName
		}

		$body = $this.createObjectFromJSON("xaas-k8s-new-pks-cluster.json", $replace)
			
		$this.callAPI($uri, "POST", $body) | Out-Null

		$this.waitForClusterAction($clusterName)

		return $this.getCluster($clusterName)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Met un cluster à jour

		IN  : $clusterName		-> Le nom du cluster
	#>
	[void] updateCluster([string]$clusterName)
	{
		$uri = "https://{0}:9021/v1/clusters/{1}" -f $this.server, [System.Net.WebUtility]::UrlEncode($clusterName)

		Throw "To implement"
		# Valeur à mettre pour la configuration du BG
		$replace = @{}

		$body = $this.createObjectFromJSON("xaas-k8s-patch-pks-cluster.json", $replace)
			
		$this.callAPI($uri, "POST", $body) | Out-Null
	}


	<#
        =====================================================================================
											PLANS
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des plans qui existent
	#>
	[Array] getPlanList()
    {
        $uri = "https://{0}:9021/v1/plans" -f $this.server
        
        return $this.callAPI($uri, "GET", $null)
	}


	<#
        =====================================================================================
										NETWORK PROFILES
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des network profiles qui existent
	#>
	[Array] getNetworkProfileList()
    {
        $uri = "https://{0}:9021/v1/network-profiles" -f $this.server
        
        return $this.callAPI($uri, "GET", $null)
	}


	<#
        =====================================================================================
											USAGE
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie l'utilisation des clusters
	#>
	[Array] getUsages()
    {
        $uri = "https://{0}:9021/v1/usages" -f $this.server
        
        return $this.callAPI($uri, "GET", $null)
	}
}