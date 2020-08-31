<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API du NetApp

         La classe parente est APIUtils et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.

    Documentation:
    - Appels synchrones vs asynchrones: https://library.netapp.com/ecmdocs/ECMLP2853739/html/GUID-142FC66E-7C9C-40E9-8F2D-80D7F0E32835.html
    - Check des appels asynchrones: https://library.netapp.com/ecmdocs/ECMLP2853739/html/GUID-E2B341A4-2FAD-44A3-8472-F14A83D6BA6C.html
    - API en elle-même: https://nas-mcc-t.epfl.ch/docs/api/ (nécessite ue authentification user/password)

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2020
#>

class NetAppAPI: RESTAPICurl
{
    hidden [string] $extraArgs
    hidden [string] $password

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server               -> Nom du serveur Scality. Sera utilisé pour créer l'URL du endpoint
        IN  : $username             -> Nom du profile à utiliser pour les credentials
                                        de connexion.
        IN  : $password             -> Nom d'utilisateur pour se connecter à la console Web
	#>
	NetAppAPI([string]$server, [string]$username, [string]$password): base($server) 
	{
        # Pour l'API de NetApp, on ne peut pas s'authentifier en passant les informations dans le header de la requête. Non,
        # on doit utiliser le paramètre "-u" de Curl pour faire le job.
        # Exemple: http://docs.netapp.com/ontap-9/index.jsp?topic=%2Fcom.netapp.doc.dot-rest-api%2Fhome.html
        $this.extraArgs = "-u {0}:{1}" -f $username, $password
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
                d'ajouter le paramètre supplémentaire en l'état des arguments additionnels, le tout
                en n'ayant qu'un point d'entrée

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		# Appel de la fonction parente
        return ([RESTAPICurl]$this).callAPI($uri, $method, $body, $this.extraArgs)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Retourne les informations sur la version du NetApp
	#>
    [PSCustomObject] getVersion()
    {
        $uri = "https://{0}/api/cluster?fields=version" -f $this.server

        return $this.callAPI($uri, "GET", $null).version
    }

     
}
