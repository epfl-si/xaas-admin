<#
   BUT : Contient les fonctions donnant accès à l'API de K8s (Kubernetes)

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

		# Si on a un messgae d'erreur
		if([bool]($res.PSobject.Properties.name -match "error") -and ($res.error -ne ""))
		{
			# Création de l'erreur de base 
			$err = "{0}::{1}(): {2} -> {3}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.error, $res.error_description

			Throw $err
		}

		return $res
	}
	
    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		# FIXME: Implement
		Throw "Implement"
		$uri = "https://{0}/logout" -f $this.server

		$this.callAPI($uri, "Post", $null)
    }
    

	<#
        =====================================================================================
											CLUSTERS
        =====================================================================================
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



}