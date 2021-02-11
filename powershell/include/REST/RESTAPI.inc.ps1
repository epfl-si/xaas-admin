<#
   BUT : Contient une classe avec les fonctions de base pour faire des appels REST
		 via le cmdlet Invoke-RestMethod.
		 La classe utilise des templates se trouvant dans des fichiers JSON et c'est
		 pour cette raison qu'elle hérite de la classe APIUtils. Cette dernière fourni
		 juste la primitive pour charger des fichiers JSON, elle n'a pas été inclue
		 dans la classe courante car elle est nécessaire pour d'autres classes qui ne
		 font pas forcément des appels REST comme celle-ci.

         Cette classe courante devra ensuite être utilisée comme classe parente par les
         classes spécifiques pour accéder en REST à l'un ou l'autre système.

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base
   0.2 - Ajout du JSON dans le message d'erreur si présent

#>
class RESTAPI: APIUtils
{
	hidden [string]$server
	hidden [System.Collections.Hashtable]$headers
	hidden [System.Object] $lastBody

    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
	#>
    RESTAPI([string] $server)
    {
		$this.server = $server
		$this.headers = @{}
    }


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne le dernier "body" (en JSON) qui a été utilisé pour faire une requête.
				Permet par exemple de savoir ce qui a été envoyé pour une requête qui 
				aurait planté
	#>
	[System.Object] getLastBodyJSON()
	{
		return $this.lastBody | ConvertTo-Json -Depth 20
	}

    
	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel

		REMARQUE: Si on a un retour autre qu'un code 200 lors de l'appel à Invoke-RestMethod, 
					cela fait qu'on passe directement dans le bloc "catch"
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		$this.lastBody = $body

		$this.debugLog(("Invoke-RestMethod: $($method) $($uri) `nBody:`n{0}" -f (ConvertTo-Json -InputObject $body -Depth 20)))

		# Si la requête est de la lecture
		if($method -eq "get")
		{
			# Si on a l'info dans le cache, on la retourne
			$cached = $this.getFromCache($uri)
			if($null -ne  $cached)
			{
				$this.incFuncCall($true)
				return $cached
			}
		}		

		# Mise à jour du compteur d'appels à la fonction qui a appelé celle-ci
		$this.incFuncCall($false)

		$json = "No JSON"

		# On fait plusieurs tentatives dans le cas où ça foirerait
		$nbCurlAttempts = 2
		for($currentAttemptNo=1; $currentAttemptNo -le $nbCurlAttempts; $currentAttemptNo++)
		{
			$this.debugLog("Invoke-RestMethod attempt: $($currentAttemptNo)")
			try
			{
				if($null -ne $body)
				{
					# On converti l'objet du Body en JSON pour faire la requête
					$json = ConvertTo-Json -InputObject $body -Depth 20
					return Invoke-RestMethod -Uri $uri -Method $method -Headers $this.headers -Body $json
				}
				else 
				{
					return Invoke-RestMethod -Uri $uri -Method $method -Headers $this.headers 
				}


			}
			catch 
			{
				# Si on n'est psa encore au nombre d'essais
				if($currentAttemptNo -lt $nbCurlAttempts)
				{
					# On fait une petite pause et on y retourne
					Start-Sleep -seconds 2
				}
				else
				{
					$exceptionMessage = ""
					# Si une erreur survient, on la "repropage" mais avec un message d'erreur plus parlant qu'un "Bad Request" ou autre... 
					# On va récupérer le message qui a été renvoyé par vRA et on va le rebalance en exception !
					if($null -ne $_.ErrorDetails)  
					{
						$errorDetails = $_.ErrorDetails.Message
					}
					else
					{
						$errorDetails = $_.Exception.message
					}

					if($null -ne $_.Exception.InnerException)
					{
						$exceptionMessage = $_.Exception.InnerException.Message
					}


					$errorDetails = "{0}`n{1}" -f $errorDetails, $exceptionMessage

					# On récupère aussi le nom de la classe et de la fonction qui a appelé celle-ci, histoire d'avoir un peu d'infos dans le message d'erreur
					# Le nom de la classe est récupéré dynamiquement car la classe courante va être dérivée en d'autres classes
					$classNameAndFunc =  "{0}::{1}" -f $this.gettype().Name, (Get-PSCallStack)[1].FunctionName

					Throw ("{0}(): {1}`nJSON: {2}" -f $classNameAndFunc, $errorDetails, $json)

				}# FIN SI on a fait le nombre d'essais max

			} # FIN Catch

		} # FIN BOUCLE nombre d'essais

		return $null
	}
    
}