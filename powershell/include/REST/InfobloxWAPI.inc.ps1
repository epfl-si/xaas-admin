<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API Infoblox qui permet
            de gérer plusieurs choses:
            - DNS
            - IP
            - VLAN
            - Grid management scenarios

    Documentation:
    - PDF en ligne: https://www.infoblox.com/wp-content/uploads/infoblox-deployment-infoblox-rest-api.pdf

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021
#>

$global:WAPI_VERSION = "2.11"

class InfobloxWAPI: RESTAPICurl
{
    hidden [string] $extraArgs
    hidden [string] $cookieFile
    hidden [string] $baseUrl

    
	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $serverList           -> Liste avec les noms des serveurs
        IN  : $username             -> Nom d'utilisateur
        IN  : $password             -> Mot de passe
	#>
	InfobloxWAPI([string]$server, [string]$username, [string]$password): base($server) 
	{
        # Mise à jour des headers
        $this.headers.Add('Accept', 'application/json')
        
        <# Pour l'API d'Infoblox, on ne peut pas s'authentifier en passant les informations dans le header de la requête. Non,
            on doit utiliser le paramètre "-u" de Curl pour faire le job. Cependant, on peut choisir de stocker les informations
            dans un cookie lors de la première requête et ensuite, on réutilise le cookie pour l'authentification, ce qui évite
            de repasser à nouveau les infos de connexion. 
            Donc dans un premier temps, les 'extraArgs' 
        #>
        # Création d'un fichier temporaire pour le cookie
        $this.cookieFile = (New-TemporaryFile).FullName
        $this.extraArgs = '-u {0}:{1} -c "{2}"' -f $username, $password, $this.cookieFile

        # Définition de l'URL de base pour constuire les appels
        $this.baseUrl = "{0}/wapi/{1}" -f $this.baseUrl, $global:WAPI_VERSION
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
                d'ajouter le paramètre supplémentaire en l'état des arguments additionnels, le tout
                en n'ayant qu'un point d'entrée

        IN  : $uri		            -> URL à appeler. Si elle ne démarre pas par "https://" c'est qu'on a passé
                                        que le chemin jusqu'à l'API (ex: /api/cluster/jobs/...) et dans ce cas-là,
                                        il faut boucler sur tous les serveurs
		IN  : $method	            -> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	            -> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
                                        Si $null, on ne passe rien.
        
		RET : Retour de l'appel
    #>
    hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
    {
        # Si la requête doit retourner quelque chose
        if($method -eq "get")
        {
            if($uri -contains "?")
            {
                $concatChar = "&"
            }
            else
            {
                $concatChar = "?"
            }
            # On ajoute le nécessaire pour que le résultat soit renvoyé sous forme d'objet JSON
            $uri = "{0}{1}_return_as_object=1" -f $uri, $concatChar
        }
        

        # Appel de la fonction parente en ajouter les arguments supplémentaires
        $result = ([RESTAPICurl]$this).callAPI($uri, $method, $body, $this.extraArgs)

        # Si on vient de faire le permier appel REST, le fichier Cookie a dû être généré
        if($this.extraArgs.StartsWith("-u"))
        {
            # On fait en sorte d'utiliser le fichier Cookie pour l'authentification pour les appels suivants
            $this.extraArgs = '-b "{0}"' -f $this.cookieFile
        }

        return $result.result
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST
	#>
    [void] disconnect()
    {
		$uri = "{0}/logout" -f $this.baseUrl

		$this.callAPI($uri, "POST", $null)        
    }

}
