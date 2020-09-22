<#
   BUT : Contient une classe avec les fonctions de base pour faire des appels REST
		 via CURL.
         La classe utilise des templates se trouvant dans des fichiers JSON.
         Cette classe devra ensuite être utilisée comme classe parente par les
		 classes spécifiques pour accéder en REST à l'un ou l'autre système.
		 
	NOTE : Certains systèmes comme NSX-T ne fonctionnent pas correctement avec
		   la manière standard de faire (Invoke-RestMethod) et nécessitent donc
		   une autre manière de faire, et celle-ci consiste à utiliser Curl comme
		   intermédiaire pour effectuer les requêtes.

	PREREQUIS : Pour fonctionner, cette classe nécessite le binaire curl.exe, 
				celui-ci peut être téléchargé ici : https://curl.haxx.se/windows/
				Une fois le ZIP téléchargé et extrait, copier le contenu du dossier
				"bin" dans le dossier "powershell/bin" du repo courant.

   AUTEUR : Lucien Chaboudez
   DATE   : Juin 2019

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class RESTAPICurl: RESTAPI
{
	
	hidden [System.Diagnostics.Process]$curl
	hidden [PSObject]$process
	
    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
	#>
    RESTAPICurl([string] $server) : base($server) # Ceci appelle le constructeur parent
    {
		$pathToCurl = [IO.Path]::Combine($global:BINARY_FOLDER, "curl.exe")

		# On check qu'on a bien le tout pour faire le job 
		if(!(Test-Path $pathToCurl))
		{
			Throw ("Binary file 'curl.exe' is missing... ({0})" -f $pathToCurl)
		}

		# Création du nécessaire pour exécuter un process CURL
		$this.curl = New-Object System.Diagnostics.Process
		$this.curl.StartInfo.FileName = $pathToCurl
		# On est obligé de mettre UseShellExecute à true sinon ça foire avec le code de retour de
		# la fonction 
		$this.curl.StartInfo.UseShellExecute = $false

		$this.curl.StartInfo.RedirectStandardOutput = $true
		$this.curl.StartInfo.RedirectStandardError = $true

		$this.curl.StartInfo.CreateNoWindow = $false

    }

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les headers sous la forme d'une chaine de caractère pouvant être passée
			  en paramètre à Curl

		RET : Chaîne de caractères avec les headers
	#>
	hidden [String]getCurlHeaders()
	{
		$headersStr = ""

		ForEach($headerName in $this.headers.keys)
		{
			$headersStr += ' --header "{0}: {1}"' -f $headerName, $this.headers[$headerName]
		}

		return $headersStr
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
		return $this.callAPI($uri, $method, $body, "")
	}
	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
							 Si $null, on ne passe rien.
		IN  : $extraAgrs -> Arguments supplémentaires pouvant être passés à Curl

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$extraArgs)
	{
		$this.lastBody = $body
		
		$method = $method.ToUpper()

		# Si la requête est de la lecture
		if($method -eq "GET")
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
		
		$curlArgs = "{0} --insecure -s --request {1}" -f $extraArgs, $method.ToUpper()

		$tmpFile = $null

		if($null -ne $body)
		{
			# Génération d'un nom de fichier temporaire et ajout du JSON dans celui-ci
			$tmpFile = (New-TemporaryFile).FullName

			# Si on a passé une simple chaine de caractères, on la prend tel quel
			if($body.GetType().Name -eq "String")
			{
				$body | Out-File -FilePath $tmpFile -Encoding:default
			}
			else # On a passé un objet, on le converti en JSON
			{
				(ConvertTo-Json -InputObject $body -Depth 20) | Out-File -FilePath $tmpFile -Encoding:default
			}

			$curlArgs += ' --data "@{0}"' -f $tmpFile
		}

		# Ajout des arguments 
		# Explication sur le @'...'@ ici : https://stackoverflow.com/questions/18116186/escaping-quotes-and-double-quotes
		$this.curl.StartInfo.Arguments = "{0} {1} `"{2}`"" -f ( $this.getCurlHeaders() ), $curlArgs, ($uri -replace " ","%20")

		$result = $null

		# On fait plusieurs tentatives dans le cas où ça foirerait
		$nbCurlAttempts = 2
		for($currentAttemptNo=1; $currentAttemptNo -le $nbCurlAttempts; $currentAttemptNo++)
		{
			$out = $this.curl.Start()

			$output = $this.curl.StandardOutput.ReadToEnd()
			$errorStr = $this.curl.StandardError.ReadToEnd()
	
			# Si aucune erreur
			if($this.curl.ExitCode -eq 0)
			{
				# On teste la récupération de ce qui a été retourné
				try
				{
					$result = $output | ConvertFrom-Json
				}
				catch
				{
					# Si erreur, on ajoute simplement le JSON retourné au message d'exception pour que ça soit repris dans le mail envoyé aux admins
					Throw ("{0}`n<b>Returned 'JSON':</b> {1}" -f $_.Exception.Message, $output)
				}
	
				# Si pas trouvé
				if($result.httpStatus -eq "NOT_FOUND")
				{
					# On peut simplement sortir de la boucle
					$result = $null
					break	
				}
				
				# Si rien reçu ou code d'erreur
				if($null -ne $result.error_code)
				{
					# Si on a fait le max de tentative, on peut lever une erreur
					if($currentAttemptNo -eq $nbCurlAttempts)
					{
						Throw "Error executing REST call: {0} `n{1}" -f $result.error_code, $result.error_message
					}
					
				}
				else # Aucun code d'erreur
				{
					# On peut sortir de la boucle car $result contient notre résultat
					break
				}
		
			}
			# Si erreur Curl
			else
			{
				# Si on a fait le max de tentative, on peut lever une erreur
				if($currentAttemptNo -eq $nbCurlAttempts)
				{
					# https://curl.haxx.se/libcurl/c/libcurl-errors.html
					switch($this.curl.ExitCode)
					{
						7
						{
							$errorStr = "Failed to connect to host or proxy"
						}

						52
						{
							$errorStr = "Empty answer received from remote host"
						}
						
					}
					Throw ("Error executing command ({0}) with error : `n{1}" -f $this.curl.StartInfo.Arguments, $errorStr)
				}

			}# FIN SI erreur Curl 
	
			# On attend un peu avant la prochaine tentative
			Start-Sleep -Seconds 2
		}# FIN BOUCLE du nombre d'appels Curl

		# Si on a utilisé un fichier temporaire, 
		if($null -ne $tmpFile)
		{
			# Suppression du fichier temporaire 
			Remove-Item -Path $tmpFile -Force:$true -Confirm:$false
		}

		return $result


	}
    
}