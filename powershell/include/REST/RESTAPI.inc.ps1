<#
   BUT : Contient une classe avec les fonctions de base pour faire des appels REST
		 via le cmdlet Invoke-RestMethod.
         La classe utilise des templates se trouvant dans des fichiers JSON.
         Cette classe devra ensuite être utilisée comme classe parente par les
         classes spécifiques pour accéder en REST à l'un ou l'autre système.

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class RESTAPI
{
    hidden [string]$server

    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
	#>
    RESTAPI([string] $server)
    {
        $this.server = $server
    }


    
	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $json 	-> Code JSON

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [string]$json)
	{
		try
		{
			if($json -ne "")
			{
				return Invoke-RestMethod -Uri $uri -Method $method -Headers $this.headers -Body $json
			}
			else 
			{
				return Invoke-RestMethod -Uri $uri -Method $method -Headers $this.headers 
			}


		}
		catch 
		{
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
			else 
			{
				$exceptionMessage = $_.Exception.message
			}


			$errorDetails = "{}`n{}" -f $errorDetails, $exceptionMessage

			# On récupère aussi le nom de la classe et de la fonction qui a appelé celle-ci, histoire d'avoir un peu d'infos dans le message d'erreur
			# Le nom de la classe est récupéré dynamiquement car la classe courante va être dérivée en d'autres classes
            $classNameAndFunc =  "{0}::{1}" -f $this.gettype().Name, (Get-PSCallStack)[1].FunctionName

			Throw ("{0}(): {1}" -f $classNameAndFunc, $errorDetails)
		}
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Charge un fichier JSON et renvoie le code.
				Le fichier doit se trouver dans le dossier spécifié par $global:JSON_TEMPLATE_FOLDER

		IN  : $file				-> Fichier JSON à charger
		IN  : $valToReplace	-> (optionnel) Dictionnaaire avec en clef la chaine de caractères
										à remplacer dans le code JSON (qui sera mise entre {{ et }} dans
										le fichier JSON). 
										En valeur, on peut trouver :
										- Chaîne de caractères à mettre à la place de la clef
										- Tableau avec:
											[0] -> Chaîne de caractères à mettre à la place de la clef
											[1] -> $true|$false pour dire s'il faut remplacer aussi ou pas
													les "" qui entourent la clef qui est entre {{ }}.
													On est en effet obligés de mettre "" autour sinon on
													pète l'intégrité du JSON.

		RET : Objet créé depuis le code JSON
	#>
	hidden [Object] loadJSON([string] $file, [System.Collections.IDictionary] $valToReplace)
	{
		# Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:JSON_TEMPLATE_FOLDER $file)

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("JSON file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$json = (Get-Content -Path $filepath) -join "`n"

		# S'il y a des valeurs à remplacer
		if($null -ne $valToReplace)
		{
			# Parcours des remplacements à faire
			foreach($search in $valToReplace.Keys)
			{
				# Si on a des infos pour savoir si on doit supprimer ou pas les doubles quotes 
				if($valToReplace.Item($search) -is [Array])
				{
					# Extraction des informations 
					$replaceWith, $removeDoubleQuotes = $valToReplace.Item($search)	
				}
				else # On a juste la chaîne de caractères 
				{
					$replaceWith = $valToReplace.Item($search)
					$removeDoubleQuotes = $false
				}

				$search = "{{$($search)}}"
				
				# Si on doit supprimer les doubles quotes autour de {{ }}
				if($removeDoubleQuotes)
				{
					# Ajout des doubles quotes pour la recherche
					$search = "`"$($search)`""
				}

				# Recherche et remplacement de l'élément
				$json = $json -replace $search, $replaceWith
			}
		}
		try
		{
			return $json | ConvertFrom-Json
		}
		catch
		{
			Throw ("Error converting JSON from file ({0})" -f $filepath)
		}
	}
    
}