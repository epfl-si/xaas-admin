<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API de ServiceNow

         La classe parente est APIUtils et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.


   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021
#>


class SnowAPI: RESTAPICurl
{
    hidden [string] $extraArgs


	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server			-> Nom DNS du serveur
        IN  : $username         -> Nom d'utilisateur
        IN  : $password         -> Mot de passe
	#>
	SnowAPI([string]$server, [string]$username, [string]$password): base($server) 
	{
        # Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )
        
        $this.extraArgs = "-u {0}:{1}" -f $username, $password

        $this.baseUrl = "{0}/api/now/" -f $this.baseUrl
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie le service manager pour un service
        
        IN  : $serviceId        -> ID du service "svcXXXX"

        RET : Objet avec les infos suivantes
                .fullName   -> Nom complet du service manager
                .sciper     -> Sciper du service manager
            
                $null si pas trouvé
	#>
    [PSObject] getServiceManager([string]$serviceId)
    {
        $uri = "{0}/table/cmdb_ci_service?sysparm_fields=owned_by.user_name%2C%20owned_by.name&sysparm_limit=10&u_number={1}" -f $this.baseUrl, $serviceId

        $res = $this.callAPI($uri, "GET", $null, $this.extraArgs)

        # Si pas trouvé
        if($res.result.count -eq 0)
        {
            return $null
        }

        return @{
            fullName = $res.result[0] | Select-Object -ExpandProperty owned_by.name
            sciper = $res.result[0] | Select-Object -ExpandProperty owned_by.user_name
        }
    }


}