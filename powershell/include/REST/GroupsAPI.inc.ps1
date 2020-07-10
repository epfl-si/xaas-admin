<#
    BUT : Contient les fonctions donnant accès à l'API de groups.epfl.ch

    Documentation: 
        - API: http://websrv.epfl.ch/RWSGroups.html

    Prérequis:
        - Il faut inclure le fichier incude/functions.inc.ps1

    AUTEUR : Lucien Chaboudez
    DATE   : Juillet 2020


#>
class GroupsAPI: RESTAPICurl
{

    hidden [string] $appName
    hidden [string] $callerSciper

    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $appName  	    -> Nom de l'application qui va appeler l'API
		IN  : $callerSciper		-> No sciper de la personne pour laquelle on exécute la commande
	#>
	GroupsAPI([string] $server, [string] $appName, [string] $callerSciper) : base($server) # Ceci appelle le constructeur parent
	{
        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')
        
        $this.appName = $appName
        $this.callerSciper = $callerSciper
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
        return ("https://{0}/rwsgroups/{1}?app={2}&caller={3}" -f $this.server, $command, $this.appName, $this.callerSciper)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST et contrôle s'il y a une erreur

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
    hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
    {

        $response = $this.callAPI($uri, $method, $body)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'error')
        {
            Throw ("GroupsAPI error: {0}" -f $response.error.text)
        }

        return $response
    }


    <# --------------------------------------------------------------------------------------
                                        GROUPES
    -------------------------------------------------------------------------------------- #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un Groupe donné par son ID

		IN  : $id   -> ID du Groupe recherché

        RET : Le groupe
                $null si pas trouvé
    #>
    [PSObject] getGroupById([string]$id)
    {
        $uri = "{0}&id={1}" -f $this.getBaseURI('getGroup'), $id

        $group = $this.callAPI($uri, "Get", $null)

        Throw "Handle if not found"
        return $group.result
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Recherche un groupe par son nom

        IN  : $name         -> Nom du Groupe recherché

        RET : Le groupe
                $null si pas trouvé
    #>
    [PSObject] getGroupByName([string]$name)
    {
        return $this.getGroupByName($name, $false)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Recherche un groupe par son nom

        IN  : $name         -> Nom du Groupe recherché
        IN  : $allDetails   -> $true|$false pour savoir si on veut tous les détails du groupe

        RET : Le groupe
                $null si pas trouvé
    #>
    [PSObject] getGroupByName([string]$name, [bool]$allDetails)
    {
        $uri = "{0}&name={1}" -f $this.getBaseURI('searchGroups'), $name

        $group = $this.callAPI($uri, "Get", $null)

        # Si le groupe existe
        if($null -ne $group)
        {
            # on l'ajoute au cache
            $this.addInCache($group.result[0], $uri)
        }

        # Si on veut tous les détails
        if($allDetails)
        {
            # On fait un autre appel pour avoir tous les détails. Car une recherche ne renvoie que peu de choses.
            return $this.getGroupById($group.result[0].id)
        }
        Throw "Handle if not found"
        return $group.result[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un groupe

        IN  : $name             -> Nom du groupe 
        IN  : $ownerSciper      -> No sciper du owner du groupe
        IN  : $description      -> Description du groupe
        IN  : $url              -> URL associée au groupe

        RET : Le groupe ajouté 
    #>
    [PSObject] addGroup([string]$name, [string]$ownerSciper, [string]$description, [string]$url)
    {
        return $this.addGroup($name, $ownerSciper, $description, $url, @{})
    }
    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un groupe

        IN  : $name             -> Nom du groupe 
        IN  : $ownerSciper      -> No sciper du owner du groupe
        IN  : $description      -> Description du groupe
        IN  : $url              -> URL associée au groupe
        IN  : $optionsOverride  -> Tableau associatif avec les options que l'on veut surcharger par 
                                    rapport à celles définies par défaut.

        RET : Le groupe ajouté 
    #>
    [PSObject] addGroup([string]$name, [string]$ownerSciper, [string]$description, [string]$url, [Hashtable]$optionsOverride)
    {
        # Options par défaut pour la création d'un groupe
        $defaultOptions = {
            
            # 'o' = Tout le monde peut voir la liste des membres
            # 'f' = Seul l'admin peut voir la liste des membres
            # 'r' = Seuls les membres peuvent voir la liste des membres
            access = 'o'  

            # 'f' = Seuls les admins et owner peuvent ajouter/supprimer des membres
            # 'o' = Les membres peuvent s'ajouter/retirer du groupe par eux-mêmes
            # 'w' = Comme 'o' mais avec Warning envoyé par email aux admins/owner quand une opération est effectuée
            registration = 'f'

            # 'y' = groupe visible (nécessaire pour Tequila)
            # 'n' = groupe qu'on le voit pas mais il est là
            visible = 'y'

            # 'y' = mailing list <groupe>@groupes.epfl.ch
            # 'n' = pas de mailing list
            maillist = 'y'

            # 'y' = mailing list visible
            # 'n' = mailing list invisible
            visilist = 'n'

            # 'y' = le groupe peut être utilisé par quelqu'un d'autre pour être mis dans un autre groupe
            # 'n' = bah... contraire de 'y'
            public = 'n'

            # 'y' = groupe visible dans LDAP
            # 'n' = groupe pas visible dans LDAP
            ldap = 'y'
        }

        # On met à jour les options par défaut avec ce qu'il faut override
        $optionsOverride.GetEnumerator() | ForEach-Object { $defaultOptions.($_.key) = $_.value }

        $uri = "{0}&name={1}&owner={2}&description={3}&url={4}&{5}" -f $this.getBaseURI('addGroup'), `
                                                                    $name, `
                                                                    $ownerSciper, `
                                                                    [System.Net.WebUtility]::HtmlEncode($description), `
                                                                    $url, `
                                                                    (($defaultOptions.getEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")

        $dummy = $this.callAPI($uri, "Get", $null)

        return $this.getGroupByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un groupe

        IN  : $groupId          -> ID du groupe à supprimer
    #>
    [void] deleteGroup([string]$groupId)
    {
        $uri = "{0}&id={1}" -f $this.getBaseURI('deleteGroup'), $groupId

        $group = $this.callAPI($uri, "Get", $null)
    }




    <# --------------------------------------------------------------------------------------
                                        ADMINS
    -------------------------------------------------------------------------------------- #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un admin à un groupe

        IN  : $groupId          -> ID du groupe auquel ajouter l'admin
        IN  : $adminSciper      -> No sciper de l'admin
    #>
    [void] addAdmin([string]$groupId, [string]$adminSciper)
    {
        $uri = "{0}&id={1}&admin={2}" -f $this.getBaseURI('addAdmin'), $groupId, $adminSciper

        $group = $this.callAPI($uri, "Get", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute des admins à un groupe

        IN  : $groupId          -> ID du groupe auquel ajouter les admins
        IN  : $adminSciperList  -> Tableau avec la liste des scipers
    #>
    [void] addAdmins([string]$groupId, [Array]$adminSciperList)
    {
        ForEach($adminSciper in $adminSciperList)
        {
            $this.addAmin($groupId, $adminSciper)
        }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un admin d'un groupe

        IN  : $groupId          -> ID du groupe duquel supprimer l'admin
        IN  : $adminSciper      -> No sciper de l'admin
    #>
    [void] removeAdmin([string]$groupId, [string]$adminSciper)
    {
        $uri = "{0}&id={1}&admin={2}" -f $this.getBaseURI('removeAdmin'), $groupId, $adminSciper

        $group = $this.callAPI($uri, "Get", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime des admins d'un groupe

        IN  : $groupId          -> ID du groupe duquel supprimer les admins
        IN  : $adminSciperList  -> Tableau avec la liste des scipers
    #>
    [void] removeAdmins([string]$groupId, [Array]$adminSciperList)
    {
        ForEach($adminSciper in $adminSciperList)
        {
            $this.removeAdmin($groupId, $adminSciper)
        }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Liste les admins d'un groupe

        IN  : $groupId          -> ID du groupe

        RET : Tableau avec les admins
    #>
    [Array] listAdmins([string]$groupId)
    {
        $uri = "{0}&id={1}" -f $this.getBaseURI('listAdmins'), $groupId

        $result = $this.callAPI($uri, "Get", $null)

        return $result.result
    }



    <# --------------------------------------------------------------------------------------
                                        MEMBRES
    -------------------------------------------------------------------------------------- #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un membre à un groupe

        IN  : $groupId          -> ID du groupe auquel ajouter le membre
        IN  : $memberSciper      -> No sciper du membre
    #>
    [void] addMember([string]$groupId, [string]$memberSciper)
    {
        $uri = "{0}&id={1}&member={2}" -f $this.getBaseURI('addMember'), $groupId, $memberSciper

        $group = $this.callAPI($uri, "Get", $null)
    }
    
    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute des membres à un groupe

        IN  : $groupId              -> ID du groupe auquel ajouter les membres
        IN  : $memberSciperList     -> Tableau avec la liste des scipers
    #>
    [void] addMembers([string]$groupId, [Array]$memberSciperList)
    {
        ForEach($memberSciper in $memberSciperList)
        {
            $this.addMember($groupId, $memberSciper)
        }
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un membre d'un groupe

        IN  : $groupId          -> ID du groupe duquel supprimer le membre
        IN  : $memberSciper      -> No sciper du membre
    #>
    [void] removeMember([string]$groupId, [string]$memberSciper)
    {
        $uri = "{0}&id={1}&member={2}" -f $this.getBaseURI('removeMember'), $groupId, $memberSciper

        $group = $this.callAPI($uri, "Get", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime des membres d'un groupe

        IN  : $groupId              -> ID du groupe duquel supprimer les membres
        IN  : $memberSciperList     -> Tableau avec la liste des scipers
    #>
    [void] removeMembers([string]$groupId, [Array]$memberSciperList)
    {
        ForEach($memberSciper in $memberSciperList)
        {
            $this.removeMember($groupId, $memberSciper)
        }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Liste les membres d'un groupe

        IN  : $groupId          -> ID du groupe

        RET : Tableau avec les membres
    #>
    [Array] listMembers([string]$groupId)
    {
        $uri = "{0}&id={1}" -f $this.getBaseURI('listMembers'), $groupId

        $result = $this.callAPI($uri, "Get", $null)

        return $result.result
    }



    





    


}