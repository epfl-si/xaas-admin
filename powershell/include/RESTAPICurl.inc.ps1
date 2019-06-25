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
	hidden [System.Collections.Hashtable]$headers
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

		<# Si le dossier n'existe pas, on le créé (il se peut qu'il n'existe pas car vu qu'il est vide,
			il ne sera pas ajouté dans GIT)
		#>
		if(!(Test-Path $global:TEMP_FOLDER))
		{
			$dummy = New-Item -Path $global:TEMP_FOLDER -ItemType "directory"
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
		BUT : Renvoie un nom de fichier temporaire contenant les informations à envoyer via
				un appel à curl.exe

		RET : Chemin jusqu'au fichier
	#>
	hidden [String]getTmpFilename()
	{
		$length = 10
		return [IO.Path]::Combine($global:TEMP_FOLDER, ( -join ((0x30..0x39) + ( 0x41..0x5A) + ( 0x61..0x7A) | Get-Random -Count $length | ForEach-Object {[char]$_}) )) 
	}
	
	
	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $json 	-> Code JSON

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [string]$json)
	{
		try
		{
			$args = "--insecure -s --request {0}" -f $method.ToUpper()

			$tmpFile = $null

			if($json -ne "")
			{
				# Génération d'un nom de fichier temporaire et ajout du JSON dans celui-ci
				$tmpFile = $this.getTmpFilename()
				$json | Out-File -FilePath $tmpFile -Encoding:default

				$args += ' --data "@{0}"' -f $tmpFile
			}

			# Ajout des arguments 
			# Explication sur le @'...'@ ici : https://stackoverflow.com/questions/18116186/escaping-quotes-and-double-quotes
			$this.curl.StartInfo.Arguments = "{0} {1} {2}" -f ( $this.getCurlHeaders() ), $args, $uri

			$out = $this.curl.Start()

			$output = $this.curl.StandardOutput.ReadToEnd()
			$errorStr = $this.curl.StandardError.ReadToEnd()

			# Si on a utilisé un fichier temporaire, 
			if($null -ne $tmpFile)
			{
				# Suppression du fichier temporaire 
				Remove-Item -Path $tmpFile -Force:$true -Confirm:$false
			}

			if($this.curl.ExitCode -ne 0)
			{
				Throw "Error executing command ({0}) with error : `n{1}" -f $this.curl.StartInfo.Arguments, $errorStr
			}

			$result = $output | ConvertFrom-Json

			if($null -ne $result.error_code)
			{
				Throw "Error executing REST call: {0} `n{1}" -f $result.error_code, $result.error_message
			}

			return $result

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

			$errorDetails = "{}`n{}" -f $errorDetails, $_.Exception.InnerException.Message

			# On récupère aussi le nom de la classe et de la fonction qui a appelé celle-ci, histoire d'avoir un peu d'infos dans le message d'erreur
			# Le nom de la classe est récupéré dynamiquement car la classe courante va être dérivée en d'autres classes
            $classNameAndFunc =  "{0}::{1}" -f $this.gettype().Name, (Get-PSCallStack)[1].FunctionName

			Throw ("{0}(): {1}" -f $classNameAndFunc, $errorDetails)
		}
	}
    
}