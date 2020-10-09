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

		$uri = "https://{0}/service/token?service=harbor-registry&scope=repository:library/mysql:pull,push" -f $this.server

		# Récupération du token. C'est particulier parce qu'on doit faire un GET et pas un POST comme on aurait tendance.
		$this.token = ($this.callAPI($uri, "GET", $null, ("-u {0}:{1}" -f $user, $password))).token

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Bearer {0}" -f $this.token))

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
		if([bool]($res.PSobject.Properties.name -match "error") -and ($res.error -ne ""))
		{
			# Création de l'erreur de base 
			Throw ("{0}::{1}(): {2} -> {3}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.error, $res.error_description)
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
			$uri = "https://{0}/api/projects?page_size={1}&page={2}" -f $this.server, $nbPerPage, $pageNo

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
		$uri = "https://{0}/api/projects" -f $this.server

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
		$uri = "https://{0}/api/projects/{1}" -f $this.server, $project.project_id
			
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
		return switch($role)
		{
			Admin { 1 }
			Developer { 2 }
			Guest { 3 }
			Master { 4 }
		}
	}
	 

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des membres d'un projet

		IN  : $project			-> Objet représentant le projet

		RET : Liste des membres
	#>
	[Array] getProjectMemberList([PSObject]$project)
	{
		$uri = "https://{0}/api/projects/{1}/members" -f $this.server, $project.project_id
			
		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une membre à un projet (utilisateur ou groupe)

		IN  : $project			-> Objet représentant le projet
		IN  : $userOrGroupName	-> Nom d'utilisateur ou groupe
		IN  : $role				-> Rôle à attribuer

		RET : Le projet créé
	#>
	[PSObject] addProjectMember([PSObject]$project, [string]$userOrGroupName, [HarborProjectRole]$role)
	{
		$groupDN = $null
		try
		{
			$groupDN = (Get-ADGroup $userOrGroupName).DistinguishedName
		}
		catch
		{
			
		}
		
		$uri = "https://{0}/api/projects/{1}/members" -f $this.server, $project.project_id

		# Si c'est un groupe qu'on ajoute, 
		if($null -ne $groupDN)
		{
			$replace = @{
				roleId = @($this.getRoleID($role), $true)
				groupName = $userOrGroupName
				LDAPDN = (getADUserOrGroupDN -userOrGroup $userOrGroupName)
			}

			$body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-member-group.json", $replace)
		}		
		else # C'est un utilisateur qu'on ajoute
		{
			$replace = @{
				roleId = @($this.getRoleID($role), $true)
				userName = $userOrGroupName
			}
			$body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-member-user.json", $replace)
		}
			
		return $this.callAPI($uri, "POST", $body) 
		
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
	#>
	[Array] getProjectRobotList([PSObject]$project)
	{
		$uri = "https://{0}/api/projects/{1}/robots" -f $this.server, $project.project_id
			
		return $this.callAPI($uri, "GET", $null)
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Ajoute une membre à un projet (utilisateur ou groupe)

		IN  : $project			-> Objet représentant le projet
		IN  : $name				-> Nom du robot
		IN  : $description		-> Description du robot

		RET : Le projet créé
	#>
	[PSObject] addProjectRobot([PSObject]$project, [string]$name, [string]$description)
	{
		
		$uri = "https://{0}/api/projects/{1}/robots" -f $this.server, $project.project_id

		$replace = @{
			name = $name
			description = $description
			projectId = $project.project_id
		}

		$body = $this.createObjectFromJSON("xaas-k8s-add-harbor-project-robot.json", $replace)

		return $this.callAPI($uri, "POST", $body) 
		
	}
}