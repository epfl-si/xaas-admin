<#
    BUT : Contient les fonctions donnant accès à l'API de accred.epfl.ch

    Documentation: 
        - API: https://websrv.epfl.ch/RWSAccreds.html

    Prérequis:
        - Il faut inclure le fichier incude/functions.inc.ps1

    AUTEUR : Lucien Chaboudez
    DATE   : Décembre 2020


#>
class AccredAPI: RESTAPICurl
{

    hidden [string] $appName
    hidden [string] $password
    hidden [EPFLLDAP] $ldap

    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $appName  	    -> Nom de l'application qui va appeler l'API
        IN  : $password         -> Le mot de passe
	#>
	AccredAPI([string] $server, [string] $appName,  [string]$password, [EPFLLDAP]$ldap) : base($server) # Ceci appelle le constructeur parent
	{
        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/x-www-form-urlencoded')
        
        $this.appName = $appName
        $this.password = $password
        $this.ldap = $ldap

        # L'API sur https://accreds.epfl.ch ne supporte pas l'UTF-8 donc on utilise l'encodage par défaut
        $this.usePSDefaultEncoding()
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie l'URL de base pour une commande. On y ajoutera ensuite d'autres paramètres
                pour compléter la commande que l'on désire faire.

		IN  : $command -> la commande que l'on veut exécuter

		RET : URL 
    #>
    hidden [string] getBaseURI([string]$command)
    {
        # Le sciper du caller peut rester à 000000 car c'est uniquement de la lecture et pas de l'écriture.
        return ("https://{0}/cgi-bin/rwsaccred/{1}?app={2}&caller=000000&password={3}" -f $this.server, $command, $this.appName, $this.password)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST et contrôle s'il y a une erreur

		IN  : $uri		-> URL à appeler
        IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
        
        RET : Retour de l'appel

        NOTE: Pas de "body" car cette API ne permet que de faire des requêtes GET (ça serait trop
                beau qu'on puisse faire du PUT dans Accred XD )
	#>
    hidden [Object] callAPI([string]$uri, [string]$method)
    {

        $response = ([RESTAPICurl]$this).callAPI($uri, $method, $null)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'error')
        {
            Throw ("AccredAPI error: {0}" -f $response.error.text)
        }

        return $response
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la list des personnes qui sont admins IT d'une unité. On prend aussi en compte
                les personnes qui héritent de ce droit pour l'unité en question pas uniquement 
                celles qui sont spécifiquement accréditées dans l'unité en tant que AdminIT

		IN  : $unitId   -> ID de l'unité

        RET : Liste des personnes
    #>
    [PSObject] getUnitITAdminList([string]$unitId)
    {
        $uri = "{0}&roleid=AdminIT&unitid={1}" -f $this.getBaseURI('getRoles'), $unitId

        try
        {
            $list = $this.callAPI($uri, "GET")
        }
        catch
        {
            # Analyse du message d'erreur pour voir si le groupe n'est pas trouvé
            if($_.Exception.Message -like ("*{0} doesn't exist*" -f $unitId))
            {
                return $null
            }
            # On continue la propagation de l'exception 
            Throw
        }

        $personList = @()

        # Parcours des no scipers renvoyés
        $list.result | ForEach-Object {
            $person = $this.ldap.getPersonInfos($_)

            # Si la personne a été trouvée dans LDAP, ajout à la liste
            if($null -ne $person)
            {
                $personList += $person
            }
        }
        return $personList
    }

}