<#
   BUT : Contient les fonctions donnant accès à l'API de K8s (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

    
	Documentation:
	


	REMARQUES:
	- On hérite de RESTAPICurl et pas RESTAPI parce que sur les machines de test/prod, il y a des problèmes
	de connexion refermée...

#>



class K8sAPI: RESTAPICurl
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
	K8sAPI([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.server = $server

		<# Le plus souvent, on utilise 'application/json' pour les 'Accept' et 'Content-Type' mais NetBackup semble vouloir faire
			autrement... du coup, obligé de mettre ceci car sinon cela génère des erreurs. Et au final, c'est toujours du JSON... #>
		$this.headers.Add('Accept', 'application/vnd.netbackup+json;version=2.0')
		$this.headers.Add('Content-Type', 'application/vnd.netbackup+json;version=1.0')


		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

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
		# Appel de la fonction parente
		$res = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

		# FIXME: Implement
		Throw "Implement error handling"

		# Si on a un messgae d'erreur
		if([bool]($res.PSobject.Properties.name -match "errorMessage") -and ($res.errorMessage -ne ""))
		{
			# Création de l'erreur de base 
			$err = "{0}::{1}(): {2}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.errorMessage

			# Ajout des détails s'ils existent 
			$res.attributeErrors.PSObject.Properties | ForEach-Object {
			
				$err = "{0}`n{1}: {2}" -f $err, $_.Name, $_.Value
			}
			

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
    


}