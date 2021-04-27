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
	hidden [Hashtable]$bgCustomIdMappingCache


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
		$this.bgCustomIdMappingCache = $null

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

        $refreshToken = (Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)).refresh_token
        

        # --- Etape 2 de l'authentification
        $replace = @{refreshToken = $refreshToken }

        $body = $this.createObjectFromJSON("vra-auth-step2.json", $replace)

        # https://code.vmware.com/apis/978#/Login/retrieveAuthToken
        $uri = "{0}/iaas/api/login" -f $this.baseUrl

		$this.token = (Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)).token

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
			Throw ("vRA8API error: {0}" -f $response.serverMessage
			)
        }

        return $response
	}
}