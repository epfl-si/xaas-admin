<#
   	BUT : Contient les fonctions donnant accès à l'API vSphere.
		Certaines opérations sur les tags ne peuvent pas être effectuées via les CmdLet
		à cause d'une erreur renvoyée pour une histoire de Single-SignOn... et cette 
		erreur ne survient que quand on exécute le script depuis vRO via le endpoint
		PowerShell.


   	AUTEUR : Lucien Chaboudez
   	DATE   : Juillet 2019

	Documentation:
		- API: https://vsissp-vcsa-t-01.epfl.ch/apiexplorer/index.html#!/
		- Fichiers JSON utilisés: https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-vSphere


	REMARQUES :
	- Cette classe hérite de RESTAPICurl. Pourquoi Curl? parce que si on utilise le CmdLet
		Invoke-RestMethod, on a une erreur de connexion refermée, et c'est la même chose 
		lorsque l'on veut parler à l'API de NSX-T. C'est pour cette raison que l'on passe
		par Curl par derrière.

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class vSphereAPI: RESTAPICurl
{
	hidden [string]$apiSessionId
    hidden [System.Collections.Hashtable]$headers
    

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $userAtDomain	-> Nom d'utilisateur (user@domain)
		IN  : $password			-> Mot de passe

	#>
	vSphereAPI([string] $server, [string] $userAtDomain, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')

		$authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $userAtDomain, $password)))

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("Basic {0}" -f $authInfos))

		$this.baseUrl = "{0}/rest" -f $this.baseUrl
		$uri = "{0}/com/vmware/cis/session" -f $this.baseUrl

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.apiSessionId = ($this.callAPI($uri, "Post", $null)).value

		# Mise à jour des headers
		$this.headers.Add('vmware-api-session-id', $this.apiSessionId)

    }    
    

	<#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		$uri = "{0}/com/vmware/cis/session" -f $this.baseUrl

		$this.callAPI($uri, "Delete", $null)
	}    


	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une VM donnée par son nom.
        
		IN  : $vmName	-> Nom de la VM
		
		RET : Objet représentant la VM
			  $null si pas trouvé

	#>
	hidden [PSObject] getVM([string] $vmName)
	{
		$uri = "{0}/vcenter/vm?filter.names={1}" -f $this.baseUrl, $vmName
		return ($this.callAPI($uri, "Get", $null)).value[0]
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie les détails d'un tag.
        
        IN  : $tagId	-> ID du tag dont on veut les détails

	#>
	hidden [PSObject] getTagById([string] $tagId)
	{
		$uri = "{0}/com/vmware/cis/tagging/tag/id:{1}" -f $this.baseUrl, $tagId
		return ($this.callAPI($uri, "Get", $null)).value
	}
	

	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie les détails d'une catégorie.
        
        IN  : $categoryId	-> ID de la catégorie dont on veut les détails

	#>
	hidden [PSObject] getCategoryById([string] $categoryId)
	{
		$uri = "{0}/com/vmware/cis/tagging/category/id:{1}" -f $this.baseUrl, $categoryId
		return ($this.callAPI($uri, "Get", $null)).value
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un tag donné par son nom.
		
		IN  : $tagName		-> Le nom du tag que l'on cherche
	#>
	hidden [PSObject] getTag([string]$tagName)
	{
		# On récupère la liste des tags et pour chacun, on recherche les détails pour savoir si le nom correspon
		# et dès qu'on a trouvé, on renvoie l'objet avec les détails.
		return $this.getTagList() | Foreach-Object {
			$details = $this.getTagById($_)
			if($details.Name -eq $tagName)
			{
				return $details
			}
		}
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Ajoute ou supprime un tag à une VM
        
		IN  : $vmName	-> Nom de la VM
		IN  : $tagName	-> Nom du tag que l'on veut ajouter/supprimer
		IN  : $action	-> "attach" ou "detach" suivant ce que l'on veut faire.
	#>
	hidden [void] attachDetachVMTag([PSObject]$vmName,  [string]$tagName, [string]$action)
	{
		$vm = $this.getVM($vmName)
		if($null -eq $vm)
		{
			Throw "VM '{0}' not found in vSphere" -f $vmName
		}

		$tag = $this.getTag($tagName)
		if($null -eq $tag)
		{
			Throw ("Tag '{0}' to {1} to/from VM {2} not found in vSphere" -f $tagName, $action, $vmName)
		}


		$uri = "{0}/com/vmware/cis/tagging/tag-association/id:{1}?~action={2}" -f $this.baseUrl, $tag.id, $action

		$replace = @{tagId = $tag.id
					objectType = "VirtualMachine"
					objectId = $vm.vm}

		$body = $this.createObjectFromJSON("vsphere-tag-operation.json", $replace)

		$this.callAPI($uri, "Post", $body) | Out-Null
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une catégorie
        
		IN  : $categoryName	-> Nom de la catégorie
	#>
	hidden [PSObject] getCategory([string]$categoryName)
	{
		# On récupère la liste des catégories et pour chacun, on recherche les détails pour savoir si le nom correspond
		# et dès qu'on a trouvé, on renvoie l'objet avec les détails.
		return $this.getCategoryList() | Foreach-Object {
			$details = $this.getCategoryById($_)
			if($details.Name -eq $categoryName)
			{
				return $details
			}
		}
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Supprime un tag à d'une VM
        
		IN  : $vmName	-> Nom de la VM
		IN  : $tagName	-> Nom du tag que l'on veut supprimer
	#>
	[void] detachVMTag([string]$vmName,  [string]$tagName)
	{
		$this.attachDetachVMTag($vmName, $tagName, "detach")
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un tag à une VM
        
		IN  : $vmName	-> Nom de la VM
		IN  : $tagName	-> Nom du tag que l'on veut ajouter
	#>
	[void] attachVMTag([string]$vmName,  [string]$tagName)
	{
		$this.attachDetachVMTag($vmName, $tagName, "attach")
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Permet de savoir si une VM existe
        
		IN  : $vmName	-> Nom de la VM

		RET : $true|$false
	#>
	[bool] VMExists([string]$vmName)
	{
		return ($null -ne $this.getVM($vmName))
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des tags (détaillés) attachés à l'objet représentant une VM qui 
				est passé en paramètre. Cet objet aura été obtenu via le CmdLet "Get-VM"
        
        IN  : $vmName	-> Nom de la VM

		RET : Tableau avec les détails des tags 
	#>
    [Array] getVMTags([string] $vmName)
    {
		$vm = $this.getVM($vmName)

		if($null -eq $vm)
		{
			Throw ("VM {0} not found in vSphere" -f $vmName)
		}

		return $this.getVMTags($vm)
	}

		<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des tags (détaillés) attachés à l'objet représentant une VM qui 
				est passé en paramètre. Cet objet aura été obtenu via le CmdLet "Get-VM"
        
        IN  : $vmName	-> Nom de la VM

		RET : Tableau avec les détails des tags 
	#>
    [Array] getVMTags([psobject] $vm)
    {

		$uri = "{0}/com/vmware/cis/tagging/tag-association?~action=list-attached-tags" -f $this.baseUrl

		$replace = @{objectType = "VirtualMachine"
					objectId = $vm.vm}

		$body = $this.createObjectFromJSON("vsphere-object-infos.json", $replace)

		$tagList = @()

		# On récupère la liste des tags mais on n'a que leurs ID... on boucle donc dessus pour récupérer les informations
		# de chaque tag et l'ajouter à la liste que l'on va ensuite renvoyer
		$this.callAPI($uri, "Post", $body).value | ForEach-Object {

			$tagList += $this.getTagById($_)
		}

		return $tagList
	}
	
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des tags (détaillés) attachés à l'objet représentant une VM qui 
				est passé en paramètre. Cet objet aura été obtenu via le CmdLet "Get-VM"
				Seuls les tags faisant partie de la catégorie donnée sont remontés
        
		IN  : $vmName		-> Nom de la VM
		IN  : $categoryName	-> Nom de la catégorie à laquelle les tags doivent appartenir.

		RET : Tableau avec les détails des tags 
	#>
	[Array] getVMTags([string]$vmName, [string]$categoryName)
	{
		# Recherche des infos de la catégorie 
		$category = $this.getCategory($categoryName)
		# Récupération de tous les tags de la VM et filtre sur la catégorie de ceux-ci 
		return $this.getVMTags($vmName) | Where-Object { $_.category_id -eq $category.id}
	}
	

	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des tags du système
	#>
	[Array] getTagList()
	{
		$uri = "{0}/com/vmware/cis/tagging/tag" -f $this.baseUrl

		return $this.callAPI($uri, "Get", $null).value
	}

	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des catégories du système
	#>
	[Array] getCategoryList()
	{
		$uri = "{0}/com/vmware/cis/tagging/category" -f $this.baseUrl

		return $this.callAPI($uri, "Get", $null).value
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des tags d'une catégorie donnée
		
		IN  : $categoryName	-> Nom de la catégorie pour laquelle on veut les tags
	#>
	[Array] getTagList([string]$categoryName)
	{
		$uri = "{0}/com/vmware/cis/tagging/tag" -f $this.baseUrl

		return $this.callAPI($uri, "Get", $null).value
	}

}