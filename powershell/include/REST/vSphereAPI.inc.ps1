<#
   BUT : Contient les fonctions donnant accès à l'API vSphere.
		Certaines opérations sur les tags ne peuvent pas être effectuées via les CmdLet
		à cause d'une erreur renvoyée pour une histoire de Single-SignOn... et cette 
		erreur ne survient que quand on exécute le script depuis vRO via le endpoint
		PowerShell.


   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019

	Documentation de l'API https://vsissp-vcsa-t-01.epfl.ch/apiexplorer/index.html#!/


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

		$uri = "https://{0}/rest/com/vmware/cis/session" -f $this.server

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
		$uri = "https://{0}/rest/com/vmware/cis/session" -f $this.server

		$this.callAPI($uri, "Delete", $null)
	}    


    <#
		-------------------------------------------------------------------------------------
        BUT : Extrait un ID de VM depuis l'ID complet d'une VM renvoyé par Get-VM
        
        IN  : $vmFullId -> Id complet de la VM

	#>
    hidden [string] extractVMId([string]$vmFullId)
    {
        # VirtualMachine-vm-7987 => vm-7987
        return $vmFullId -replace "VirtualMachine-", ""
    }


	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie les détails d'un tag.
        
        IN  : $tagId	-> ID du tag dont on veut les détails

	#>
	hidden [PSObject] getTagById([string] $tagId)
	{
		$uri = "https://{0}/rest/com/vmware/cis/tagging/tag/id:{1}" -f $this.server, $tagId
		return ($this.callAPI($uri, "Get", $null)).value
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Ajoute ou supprime un tag à une VM
        
		IN  : $vm		-> Objet représentant la VM
		IN  : $tagId	-> Id du tag que l'on veut ajouter/supprimer
		IN  : $action	-> "attach" ou "detach" suivant ce que l'on veut faire.
	#>
	hidden [void] attachDetachVMTag([PSObject]$vm,  [string]$tagId, [string]$action)
	{
		$uri = "https://{0}/rest/com/vmware/cis/tagging/tag-association/id:{1}?~action={2}" -f $this.server, $tagId, $action

		$replace = @{tagId = $tagId
					objectType = "VirtualMachine"
					objectId = $this.extractVMId($vm.id)}

		$body = $this.loadJSON("vsphere-tag-operation.json", $replace)

		$res = $this.callAPI($uri, "Post", $body)
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Supprime un tag à d'une VM
        
		IN  : $vm		-> Objet représentant la VM
		IN  : $tagId	-> Id du tag que l'on veut supprimer
	#>
	[void] detachVMTag([PSObject]$vm,  [string]$tagId)
	{
		$this.attachDetachVMTag($vm, $tagId, "detach")
	}


	<#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un tag à une VM
        
		IN  : $vm		-> Objet représentant la VM
		IN  : $tagId	-> Id du tag que l'on veut ajouter
	#>
	[void] attachVMTag([PSObject]$vm,  [string]$tagId)
	{
		$this.attachDetachVMTag($vm, $tagId, "attach")
	}


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des tags (détaillés) attachés à l'objet représentant une VM qui 
				est passé en paramètre. Cet objet aura été obtenu via le CmdLet "Get-VM"
        
        IN  : $vm		-> Objet représentant la VM dont on veut la liste de tags

		RET : Tableau avec les détails des tags 
	#>
    [Array] getVMTags([PSObject] $vm)
    {
		$uri = "https://{0}/rest/com/vmware/cis/tagging/tag-association?~action=list-attached-tags" -f $this.server

		$replace = @{objectType = "VirtualMachine"
					objectId = $this.extractVMId($vm.id)}

		$body = $this.loadJSON("vsphere-object-infos.json", $replace)

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
        BUT : Renvoie la liste des tags du système
	#>
	[Array] getTagList()
	{
		$uri = "https://{0}/rest/com/vmware/cis/tagging/tag" -f $this.server

		return $this.callAPI($uri, "Get", $null).value
	}

	
	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie les infos d'un tag donné par son nom.
		
		IN  : $tagName		-> Le nom du tag que l'on cherche
	#>
	[PSObject] getTag([string]$tagName)
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

}