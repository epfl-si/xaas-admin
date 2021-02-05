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
    hidden [string] $password

    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $appName  	    -> Nom de l'application qui va appeler l'API
        IN  : $callerSciper		-> No sciper de la personne pour laquelle on exécute la commande
        IN  : $password         -> Le mot de passe
	#>
	GroupsAPI([string] $server, [string] $appName, [string] $callerSciper, [string]$password) : base($server) # Ceci appelle le constructeur parent
	{
        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/x-www-form-urlencoded')
        
        $this.appName = $appName
        $this.callerSciper = $callerSciper
        $this.password = $password

        # L'API sur https://groups.epfl.ch ne supporte pas l'UTF-8 donc on utilise l'encodage par défaut
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
        return ("https://{0}/cgi-bin/rwsgroups/{1}?app={2}&caller={3}" -f $this.server, $command, $this.appName, $this.callerSciper)
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

        # Tous les appels à la fonction vont se faire avec $body=$null car l'intégralité des paramètres passe en GET.
        # Il y a juste le mot de passe qui passe en --data donc on l'y ajoute tout simplement
        $body = "password={0}" -f $this.password

        $response = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

        # Si une erreur a été renvoyée 
        if(objectPropertyExists -obj $response -propertyName 'error')
        {
            Throw ("GroupsAPI error: {0}" -f $response.error.text)
        }

        return $response
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le sciper qui est utilisé pour faire les appels à l'API
    #>
    [string] getCallerSciper()
    {
        return $this.callerSciper
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

        try
        {
            $group = $this.callAPI($uri, "POST", $null)
        }
        catch
        {
            # Analyse du message d'erreur pour voir si le groupe n'est pas trouvé
            if($_.Exception.Message -like ("*{0} doesn't exist*" -f $id))
            {
                return $null
            }
            # On continue la propagation de l'exception 
            Throw
        }

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
        $uri = "{0}&name=^{1}$" -f $this.getBaseURI('searchGroups'), $name

        $group = $this.callAPI($uri, "POST", $null)

        # Si pas trouvé
        if($group.result.count -eq 0)
        {
            return $null
        }

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
        
        return $group.result[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un groupe. Par défaut, on met comme owner ce qui est configuré pour faire
                les requêtes dans Groups. Il faudra ensuite utiliser la fonction changeOwner pour
                mettre le bon owner.

        IN  : $name             -> Nom du groupe 
        IN  : $description      -> Description du groupe
        IN  : $url              -> URL associée au groupe

        RET : Le groupe ajouté 
    #>
    [PSObject] addGroup([string]$name, [string]$description, [string]$url)
    {
        return $this.addGroup($name, $description, $url, @{})
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un groupe. Par défaut, on met comme owner ce qui est configuré pour faire
                les requêtes dans Groups. Il faudra ensuite utiliser la fonction changeOwner pour
                mettre le bon owner.

        IN  : $name             -> Nom du groupe 
        IN  : $description      -> Description du groupe
        IN  : $url              -> URL associée au groupe
        IN  : $optionsOverride  -> Tableau associatif avec les options que l'on veut surcharger par 
                                    rapport à celles définies par défaut.

        RET : Le groupe ajouté 
    #>
    [PSObject] addGroup([string]$name, [string]$description, [string]$url, [Hashtable]$optionsOverride)
    {
        # Options par défaut pour la création d'un groupe
        $defaultOptions = @{
            
            # 'o' = Tout le monde peut voir la liste des membres
            # 'f' = Seul l'admin peut voir la liste des membres
            # 'r' = Seuls les membres peuvent voir la liste des membres
            access = 'o'  

            # 'f' = Seuls les admins et owner peuvent ajouter/supprimer des membres
            # 'o' = Les membres peuvent s'ajouter/retirer du groupe par eux-mêmes
            # 'w' = Comme 'o' mais avec Warning envoyé par email aux admins/owner quand une opération est effectuée
            registration = 'f'

            # '1' = groupe visible (nécessaire pour Tequila)
            # '0' = groupe qu'on le voit pas mais il est là
            visible = '1'

            # '1' = mailing list <groupe>@groupes.epfl.ch
            # '0' = pas de mailing list
            maillist = '1'

            # '1' = mailing list visible
            # '0' = mailing list invisible
            visilist = '0'

            # '1' = le groupe peut être utilisé par quelqu'un d'autre pour être mis dans un autre groupe
            # '0' = bah... contraire de 'y'
            public = '0'

            # '1' = groupe visible dans LDAP
            # '0' = groupe pas visible dans LDAP
            ldap = '1'
        }

        # On met à jour les options par défaut avec ce qu'il faut override
        $optionsOverride.GetEnumerator() | ForEach-Object { $defaultOptions.($_.key) = $_.value }

        $uri = "{0}&name={1}&owner={2}&description={3}&url={4}&{5}" -f $this.getBaseURI('addGroup'), `
                                                                    $name.ToLower(), `
                                                                    $this.callerSciper, `
                                                                    [System.Net.WebUtility]::UrlEncode($description), `
                                                                    $url, `
                                                                    (($defaultOptions.getEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join "&")

        $this.callAPI($uri, "POST", $null) | Out-Null

        return $this.getGroupByName($name)
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Renomme un groupe

        IN  : $currentName  -> Nom actuel du groupe
        IN  : $newName      -> Nouveau nom du groupe

        RET : Objet représentant le groupe renommé
                $null si le groupe n'existe pas à la base
    #>
    [PSObject] renameGroup([string]$currentName, [string]$newName)
    {

        $group = $this.getGroupByName($currentName)

        if($null -eq $group)
        {
            return $null
        }

        $uri = "{0}&id={1}&newname={2}" -f $this.getBaseURI('renameGroup'), $group.id, $newName

        $this.callAPI($uri, "POST", $null) | Out-Null

        return $this.getGroupByName($newName)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un groupe

        IN  : $groupName          -> Nom du groupe à supprimer
    #>
    [void] deleteGroup([string]$groupName)
    {
        # Recherche du groupe
        $group = $this.getGroupByName($groupName)

        # Si trouvé
        if($null -ne $group)
        {
            # Création de l'URL pour effacement
            $uri = "{0}&id={1}" -f $this.getBaseURI('deleteGroup'), $group.id

            $group = $this.callAPI($uri, "POST", $null)
        }

    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Change le owner d'un groupe

        IN  : $groupId          -> ID du groupe 
        IN  : $ownerSciper      -> Sciper du nouveau owner
    #>
    [void] changeOwner([string]$groupId, [string]$ownerSciper)
    {
        $uri = "{0}&id={1}&newowner={2}" -f $this.getBaseURI('changeOwner'), $groupId, $ownerSciper

        $this.callAPI($uri, "POST", $null) | Out-Null
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

        $this.callAPI($uri, "POST", $null) | Out-Null
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
            $this.addAdmin($groupId, $adminSciper)
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

        $this.callAPI($uri, "POST", $null) | Out-Null
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

        $result = $this.callAPI($uri, "POST", $null)

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

        $this.callAPI($uri, "POST", $null) | Out-Null
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

        $this.callAPI($uri, "POST", $null) | Out-Null
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

        $result = $this.callAPI($uri, "POST", $null)

        return $result.result
    }



    





    


}