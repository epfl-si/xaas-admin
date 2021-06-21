<#
   BUT : Contient juste une méthode, celle permettant de charger des informations depuis
        des fichiers JSON pour ensuite être utilisés dans des appels à une API quelconque, 
        que cela soit via REST ou via des méthodes PowerShell (cmdlet)

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class APIUtils
{
	# Pour compter le nombre d'appels aux fonctions de la classe
	hidden [Counters] $funcCalls

	<# Pour avoir un cache local pour certaines fonctions, ceci afin d'éviter de faire milliards d'appels aux APIs
		Certains éléments ne changent en effet pas via le script donc sont en "read only" en quelque sorte. Pour 
		ceux-ci, on peut se permettre d'avoir un cache local pour aller plus vite. #>
	hidden [Array] $cache

	<# Objet de la classe LogHistory dans le cas où on voudrait faire du logging "verbose" de ce qui se passe.
		Il faudra utiliser la fonction 'activateDebug()' pour activer ce logging en passant l'objet de la 
		classe LogHistory #>
	hidden [LogHistory] $logHistory

	# Particules de chemin à ajouter à la fin de $global:JSON_TEMPLATE_FOLDER pour atteindre le "vrai" chemin où
	# se trouvent les JSON
	hidden [Array]$jsonSubPath

    <#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
	#>
    APIUtils()
    {
		$this.funcCalls = [Counters]::new()
		$this.cache = @()

		$this.logHistory = $null

		$this.jsonSubPath = @()
	}


	<#
	-------------------------------------------------------------------------------------
        BUT : Initialise les particules de chemin à ajouter pour atteindre les fichiers JSON

		IN  : $subPath	-> Tableau avec les niveaux à ajouter, un par dossier
	#>
	hidden [void] setJSONSubPath([Array]$subPath)
	{
		$this.jsonSubPath = $subPath
	}

	
	<#
	-------------------------------------------------------------------------------------
		BUT : Ajoute un élément dans le cache. Il sera référencé par l'URI de la requête
				REST qui a été utilisée pour récupérer les données.

		IN  : $object	-> Ce qu'il faut mettre dans le cache
		IN  : $uri		-> URI pour identifier l'objet et le retrouver plus facilement.
	#>
	hidden [void] addInCache([PSObject]$object, [string]$uri)
	{
		# On n'ajoute que si ce n'est pas déjà dans le cache.
		if($null -eq $this.getFromCache($uri))
		{
			$this.cache += @{uri = $uri
							object = $object}
		}
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Recherche un élément dans le cache et le retourne
		
		IN  : $uri	-> URI qui identifie l'élément que l'on désire

		RET : $null si pas trouvé dans le cache
				L'objet
	#>
	hidden [PSObject] getFromCache([string]$uri)
	{

		$match = $this.cache | Where-Object { $_.uri -eq $uri}
		
		if($match.count -gt 0)
		{
			return $match.object
		}
		return $null
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Incrémente le nombre d'appels à la fonction qui se trouve 2 étages au-dessus.
			Cette fonction-ci sera appelée par la fonction "callAPI()" qui sera implémentée
			dans les classes enfantes.

		IN  : $cacheHit	-> Pour dire si l'appel à la fonction a utilisé le cache pour retourner
							le résultat
	#>
	hidden [void] incFuncCall([bool]$cacheHit)
	{
		$funcName = ""
		ForEach($call in (Get-PSCallStack))
		{
			if(@("callAPI", "incFuncCall") -notcontains $call.FunctionName)
			{
				$funcName = $call.FunctionName
				break
			}
		}

		$cacheHitStr = ""
		# Si on a pu récupérer l'information dans le cache
		if($cacheHit)
		{
			$cacheHitStr = " (cache hit)"
			$funcName = "{0}_cacheHit" -f $funcName
		}

		# Si le compteur pour la fonction n'existe pas, 
		if($this.funcCalls.get($funcName) -eq -1)
		{
			# Ajout du compteur
			$this.funcCalls.add($funcName, ("# calls for {0}::{1}{2}" -f $this.GetType().Name, $funcName, $cacheHitStr))
		}
		# Incrémentation
		$this.funcCalls.inc($funcName)
	}

	
	<#
		-------------------------------------------------------------------------------------
		BUT : Affiche les stats d'appels aux fonctions
	#>
	[void] displayFuncCalls()
	{
		$this.funcCalls.display("# Calls per function")
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la chaine de caractères pour afficher les stats d'appels aux fonctions

		IN  : $title	-> Titre à mettre en haut
	#>
	[string] getFuncCallsDisplay([string]$title)
	{
		return $this.funcCalls.getDisplay($title)
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
	[Object] createObjectFromJSON([string] $file, [System.Collections.IDictionary] $valToReplace)
	{
		$filePath = ""
		# Chemin complet jusqu'au fichier à charger
		Invoke-Expression ('$filepath = ([IO.Path]::Combine($global:JSON_TEMPLATE_FOLDER, "{0}"))' -f (@($this.jsonSubPath + $file) -join '","'))
		
		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("JSON file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$json = ((Get-Content -Path $filepath -raw) -replace '(?m)\s*//.*?$' -replace '(?ms)/\*.*?\*/')

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

					if($replaceWith -is [bool])
					{
						$replaceWith = $replaceWith | ConvertTo-Json
					}
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


	<#
		-------------------------------------------------------------------------------------
		BUT : Activation du logging "debug" des requêtes faites sur le système distant.

		IN  : $logHistory	-> Objet de la classe LogHistory qui va permettre de faire le logging.
	#>
	[void] activateDebug([LogHistory]$logHistory)
	{
		$this.logHistory = $logHistory
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une ligne au debug si celui-ci est activé

		IN  : $line	-> La ligne à ajouter
	#>
	[void] debugLog([string]$line)
	{
		if($null -ne $this.logHistory)
		{
			$funcName = ""

			ForEach($call in (Get-PSCallStack))
			{
				if(@("callAPI", "debugLog") -notcontains $call.FunctionName)
				{
					$funcName = $call.FunctionName
					break
				}
			}
			
			$this.logHistory.addDebug(("{0}::{1}(): {2}" -f $this.GetType().Name, $funcName, $line))
		}
	}
    
}