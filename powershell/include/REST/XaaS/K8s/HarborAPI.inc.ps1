<#
   BUT : Contient les fonctions donnant accès à l'API de Harbor (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

    
	Documentation:
	https://vsissp-harbor-t.epfl.ch/devcenter-api-2.0

	
	REMARQUES:
	- On hérite de RESTAPICurl et pas RESTAPI parce que sur les machines de test/prod, il y a des problèmes
	de connexion refermée...

#>

enum HarborProjectRole
{
	Admin
	Developer
	Guest
	Master
}


class HarborAPI: RESTAPICurl
{
	hidden [string]$token
	

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $user         	-> Nom d'utilisateur 
		IN  : $password			-> Mot de passe

		Documentation:
	#>
	HarborAPI([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.server = $server

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }
		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.headers.Add('Accept', 'application/json;charset=utf-8')
		$this.headers.Add('Content-Type', 'application/json')

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Basic {0}" -f [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $user,$password)))))

    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
				de pouvoir gérer de manière spécifique les messages d'erreur renvoyés par l'API

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
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$extraArgs)
	{
		# Appel de la fonction parente
		$res = ([RESTAPICurl]$this).callAPI($uri, $method, $body, $extraArgs)

		# Si on a un message d'erreur
		if([bool]($res.PSobject.Properties.name -match "errors") -and ($res.errors.count -gt 0))
		{
			# Création de l'erreur de base 
			Throw ("{0}::{1}(): {2} -> {3}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.errors[0].code, $res.errors[0].message)
		}

		# Check si pas trouvé
		if([bool]($res.PSobject.Properties.name -match "body"))
		{
			# Si on a un message qui dit "machin truc not found"
			if($res.body -like "*not found*")
			{
				# On n'a rien trouvé
				return $null
			}
			else # on doit donc probablement avoir un message d'erreur
			{
				Throw ("{0}::{1}(): {2}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.body)
			}
			
		}

		return $res
	}
	
	
	<#
        =====================================================================================
											PROJECT
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des projets avec possibilité de filtrer

		IN  : $queryParams	-> Paramètres pour la query

		RET : Tableau avec les résultats
	#>
	hidden [Array] getProjectListQuery([string]$queryParams)
    {
		$result = @()
		$pageNo = 1
		$nbPerPage = 100
		do
		{
			$uri = "https://{0}/api/v2.0/projects?page_size={1}&page={2}" -f $this.server, $nbPerPage, $pageNo

			# Si un filtre a été passé, on l'ajoute
			if($queryParams -ne "")
			{
				$uri = "{0}&{1}" -f $uri, $queryParams
			}
			
			$res = $this.callAPI($uri, "GET", $null, "", $true)

			# Si on doit faire une autre requête pour récupérer la suite
			if( ($pageNo * $nbPerPage) -lt $this.responseHeaders.Get_Item('x-total-count'))
			{
				$pageNo++
			}
			else # Pas besoin d'autre requête
			{
				$pageNo = $null
			}

			# Ajout du résultat à la liste
			$result += $res

		} While($null -ne $pageNo)

        return $result
	}
	

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des projets

		RET : Liste des projets
	#>
	[Array] getProjectList()
	{
		return $this.getProjectListQuery("")
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un projet

		IN  : $name		-> Nom du projet

		RET : Détails du projet
				$null si pas trouvé
	#>
	[PSObject] getProject([string]$name)
	{
		$res = $this.getProjectListQuery( ("name={0}" -f $name) )

		if($res.count -gt 0)
		{
			return $res[0]
		}
		return $null
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un projet

		IN  : $name		-> Nom du projet

		RET : Le projet créé
	#>
	[PSObject] addProject([string]$name)
	{
		$uri = "https://{0}/api/v2.0/projects" -f $this.server

		$replace = @{
			projectName = $name
		}

		$body = $this.createObjectFromJSON("xaas-k8s-new-harbor-project.json", $replace)
			
		$this.callAPI($uri, "POST", $body) | Out-Null

		# Recherche et renvoi du projet créé
		return $this.getProject($name)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un projet

		IN  : $project	-> Objet représentant le projet à supprimer
	#>
	[void] deleteProject([PSObject]$project)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}" -f $this.server, $project.project_id
			
		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}


	<#
        =====================================================================================
										PROJECT MEMBERS
        =====================================================================================
	#>
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie l'ID d'un role

		IN  : $role		-> Role dont on veut l'ID
		
		RET : ID du rôle
	#>
	hidden [int] getRoleID([HarborProjectRole]$role)
	{
		$id = switch($role)
		{
			Admin { 1 }
			Developer { 2 }
			Guest { 3 }
			Master { 4 }
		}
		return $id
	}
	
	
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie l'ID d'un groupe LDAP défini dans Harbor. C'est l'ID que Harbor a donné 
				au groupe en interne...

		IN  : $groupLDAPDN			-> DN LDAP jusqu'au groupe

		RET : ID du groupe dans Harbor
				0 si pas trouvé
	
		https://vsissp-harbor-t.epfl.ch/#/Products/get_usergroups
	#>
	hidden [int] getLDAPGroupId([string]$groupLDAPDN)
	{
		$uri = "https://{0}/api/v2.0/usergroups" -f $this.server
			
		$group = ($this.callAPI($uri, "GET", $null) | Where-Object { $_.group_name.toLower() -eq $groupLDAPDN.toLower()})

		if($null -eq $group)
		{
			return 0
		}
		return $group.id
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des membres d'un projet

		IN  : $project			-> Objet représentant le projet

		RET : Liste des membres

		https://vsissp-harbor-t.epfl.ch/#/Products/get_projects__project_id__members
	#>
	[Array] getProjectMemberList([PSObject]$project)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}/members" -f $this.server, $project.project_id
			
		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une membre à un projet (utilisateur ou groupe)

		IN  : $project			-> Objet représentant le projet
		IN  : $userOrGroupName	-> Nom d'utilisateur ou groupe
		IN  : $role				-> Rôle à attribuer

		RET : Le projet créé

		https://vsissp-harbor-t.epfl.ch/#/Products/post_projects__project_id__members
	#>
	[void] addProjectMember([PSObject]$project, [string]$userOrGroupName, [HarborProjectRole]$role)
	{
		try
		{
			$groupDN = (Get-ADGroup $userOrGroupName).DistinguishedName
		}
		catch
		{
			$groupDN = $null	
		}
		
		$uri = "https://{0}/api/v2.0/projects/{1}/members" -f $this.server, $project.project_id

		# Recherche de la liste des membres du projet
		$memberList = $this.getProjectMemberList($project)

		# Si c'est un groupe qu'on ajoute, 
		if($null -ne $groupDN)
		{
			# Recherche de l'ID du groupe dans Harbor car même si on lui file le DN de LDAP, faut aussi lui filer
			# l'ID du groupe en interne... stupide mais bref... ça a été codé avec les pieds Harbor on dirait..
			$groupId = $this.getLDAPGroupId($groupDN)

			if($groupId -eq 0)
			{
				Throw ("No information found in Harbor for group '{0}' ({1})" -f $userOrGroupName, $groupDN)
			}

			# Si le groupe est déjà présent dans la liste
			if($null -ne ($memberList | Where-Object { $_.entity_type -eq "g" -and $_.entity_id -eq $groupId }) )
			{
				# Pas besoin d'aller plus loin
				return
			}
			
			$replace = @{
				roleId = @($this.getRoleID($role), $true)
				groupName = $userOrGroupName
				LDAPDN = $groupDN.toLower()
				groupId = @($groupId, $true)
			}

			$body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-member-group.json", $replace)
		}		
		else # C'est un utilisateur qu'on ajoute
		{
			# FIXME: voir pour résoudre ce problème
			Throw "Not handled for now, raise 500 intenal server error, even when trying to do it using web interface"
			# $replace = @{
			# 	roleId = @($this.getRoleID($role), $true)
			# 	userName = $userOrGroupName
			# }
			# $body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-member-user.json", $replace)
		}
			
		$this.callAPI($uri, "POST", $body) | Out-Null
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Supprime un membre d'un projet

		IN  : $project			-> Objet représentant le projet
		IN  : $memberId			-> ID du membre à supprimer

		https://vsissp-harbor-t.epfl.ch/#/Products/delete_projects__project_id__members__mid_
	#>
	[void] deleteProjectMember([PSObject]$project, [int]$memberId)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}/members/{2}" -f $this.server, $project.project_id, $memberId
			
		$this.callAPI($uri, "DELETE", $null) | Out-Null
	}


	<#
        =====================================================================================
									PROJECT ROBOT ACCOUNT
        =====================================================================================
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des robots d'un projet

		IN  : $project			-> Objet représentant le projet

		RET : Liste des robots

		https://vsissp-harbor-t.epfl.ch/#/Robot%20Account/get_projects__project_id__robots
	#>
	[Array] getProjectRobotList([PSObject]$project)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}/robots" -f $this.server, $project.project_id
			
		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un robot éphémère (comme un papillon) à un projet. Le nom et la description
				du robot sont générés automatiquement.

		IN  : $project			-> Objet représentant le projet
		IN  : $robotName		-> Nom du compte robot
		IN  : $robotDesc		-> Description du robot
		IN  : $expireAtUTime	-> Temps unix auquel le robot va expirer

		RET : Le robot créé

		https://vsissp-harbor-t.epfl.ch/#/Robot%20Account/post_projects__project_id__robots
	#>
	[PSObject] addTempProjectRobotAccount([PSObject]$project, [string]$robotName, [string]$robotDesc, [int]$expireAtUTime)
	{
		
		$uri = "https://{0}/api/v2.0/projects/{1}/robots" -f $this.server, $project.project_id

		$replace = @{
			name = $robotName
			description = $robotDesc
			projectId = $project.project_id
			expireAt = @($expireAtUTime, $true)
		}

		$body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-robot.json", $replace)

		return $this.callAPI($uri, "POST", $body) 
		
	}


	<#
        =====================================================================================
									PROJECT REPOSITORIES
        =====================================================================================
	#>

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des repositories pour un projet donné

		IN  : $project			-> Objet représentant le projet

		RET : La liste

		https://vsissp-harbor-t.epfl.ch/#/repository/listRepositories
	#>
	[Array] getProjectRepositoryList([PSObject]$project)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}/repositories" -f $this.server, $project.name
			
		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Efface un repository appartenant à un projet.

		IN  : $project			-> Objet représentant le projet
		IN  : $repository		-> Objet représentant le repository
	#>
	[void] deleteProjectRepository([PSObject]$project, [PSObject]$repository)
	{
		$uri = "https://{0}/api/v2.0/projects/{1}/repositories/{2}" -f $this.server, $project.name, $repository.name
			
		$this.callAPI($uri, "DELETE", $null)
	}

}