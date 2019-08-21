<#
   BUT : Contient les fonctions donnant accès à l'API vRA

   Documentation: 
    - API: https://code.vmware.com/apis/222/nsx-t
    - Fichiers JSON utilisés: https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-NSX

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NSXAPI: RESTAPICurl
{
    hidden [string]$authInfos
    
    
    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $username     	-> Nom d'utilisateur (local)
		IN  : $password			-> Mot de passe
	#>
	NSXAPI([string] $server, [string] $username, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')
        
        $this.authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

        # Mise à jour des headers
        $this.headers.Add('Authorization', ("Remote {0}" -f $this.authInfos))
        
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    									NS GROUP
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un NS Group donné par son ID

		IN  : $id   -> ID du NS Group recherché

		RET : Le NS group 
    #>
    [PSObject] getNSGroupById([string]$id)
    {
        $uri = "https://{0}/api/v1/ns-groups/{1}" -f $this.server, $id

        return $this.callAPI($uri, "Get", $null)
        
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un NS Group donné par son nom

            L'API REST de NSX-T ne nous permet pas d'utiliser un filtre directement pour trouver le bon NSGroup avec le bon nom.
            Ce qu'on fait donc, c'est de récupérer la liste de tous les NSGroup (sans les référence) et on fait le filtre en PowerShell. 

            On fait ensuite une nouvelle requête avec l'ID pour récupérer uniquement le NSGroup mais cette fois-ci avec les références.

		IN  : $name     -> Nom du NS Group recherché

		RET : Le NS group 
    #>
    [PSObject] getNSGroupByName([string]$name)
    {
        $uri = "https://{0}/api/v1/ns-groups/?populate_references=false" -f $this.server

        $id =  ($this.callAPI($uri, "Get", $null).results | Where-Object {$_.display_name -eq $name}).id
     
        if($null -eq $id)
        {
            return $null
        }

        # Recherche par ID
        return $this.getNSGroupById($id)
    }

    
    <#
		-------------------------------------------------------------------------------------
		BUT : Crée un NS Group

		IN  : $name	        -> Le nom du groupe
		IN  : $description	-> La description
		IN  : $tag	        -> Le nom du tag pour le membership

		RET : Le NS group créé
	#>
    [PSObject] addNSGroup([string]$name, [string]$desc, [string] $tag)
    {
		$uri = "https://{0}/api/v1/ns-groups" -f $this.server

		# Valeur à mettre pour la configuration du NS Group
		$replace = @{name = $name
					description = $desc
					tag = $tag}

        $body = $this.createObjectFromJSON("nsx-nsgroup.json", $replace)
        
		# Création du NS Group
        $dummy = $this.callAPI($uri, "Post", $body)
        
        # Retour du NS Group en le cherchant par son nom
        return $this.getNSGroupByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    								FIREWALL SECTION
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
    #>
        

	<#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une section de firewall donnée par son nom
        
        IN  : $name	        -> Le nom de la section de firewall
        IN  : $filterType   -> (optionnel) le type de filtre: FILTER, SEARCH
                                Défaut: FILTER
        IN  : $type         -> (optionnel) le type de section: LAYER2, LAYER3
                                Défaut: LAYER3

		RET : la section demandée
	#>
	[psObject] getFirewallSectionByName([string] $name, [string]$filterType, [string]$type)
	{
        if($filterType -eq "")
        {
            $filterType = "FILTER"
        }
        if($type -eq "")
        {
            $type = "LAYER3"
        }

		$uri = "https://{0}/api/v1/firewall/sections?filter_type={1}&page_size=1000&search_invalid_references=false&type={2}" -f $this.server, $filterType, $type

        # Récupération de la liste
		$sectionList = $this.callAPI($uri, "GET", $null).results
        
        # Retour de celui-ci
        return $sectionList | Where-Object {$_.display_name -eq $name }
    }
    
    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une section de firewall donnée par son nom
        
        IN  : $name	        -> Le nom de la section de firewall

		RET : la section demandée
	#>
    [psObject] getFirewallSectionByName([string] $name)
    {
        return $this.getFirewallSectionByName($name, "", "")
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une section de firewall donnée par son ID
        
        IN  : $id	        -> ID de la section de firewall

		RET : la section demandée
	#>
    [psObject] getFirewallSectionById([string] $id)
    {
        $uri = "https://{0}/api/v1/firewall/sections/{1}" -f $this.server, $id

        # Création du NSGroup
		return $this.callAPI($uri, "GET", $null)
    }



    <#
		-------------------------------------------------------------------------------------
        BUT : Crée une section de firewall 
        
        IN  : $name	        -> Le nom de la section de firewall
        IN  : $desc         -> Description de la section
        IN  : $beforeId     -> (optionnel) ID de la section avant laquelle il faut insérer

		RET : la section créée
    #>
    [PSObject] addFirewallSection([string]$name, [string]$desc, [string]$beforeId)
    {
        
        $uri = "https://{0}/api/v1/firewall/sections" -f $this.server
        
        # Si on doit insérer avant un ID donné
        if($beforeId -ne "")
        {
            $uri += ("?id={0}&operation=insert_before" -f $beforeId)
        }

		# Valeur à mettre pour la configuration de la section de firewall
		$replace = @{name = $name
					desc = $desc}

        $body = $this.createObjectFromJSON("nsx-firewall-section.json", $replace)
        
		# Création de la section de firewall
        return $this.callAPI($uri, "Post", $body)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Efface une section de firewall 
        
        IN  : $id	        -> ID de la section de firewall
    #>
    [void] deleteFirewallSection([string]$id)
    {
        
        $uri = "https://{0}/api/v1/firewall/sections/{1}" -f $this.server, $id
        
		# Création de la section de firewall
        $dummy = $this.callAPI($uri, "Delete", $null)       
        
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Verrouille une section de firewall. Quitte si celle-ci est déjà verrouillée.
        
        IN  : $id       -> ID de la section à verrouiller

		RET : la section modifiée
    #>
    [PSObject] lockFirewallSection([string]$id)
    {
        # on commence par récupérer les informations de la section
        $section = $this.getFirewallSectionById($id)

        if($null -eq $section)
        {
            Throw ("Firewall section with ID {0} not found!" -f $id)
        }

        # Si la section est déjà verrouillée, on la retourne tout simplement
        if($section.locked)
        {
            return $section
        }

        # Ensuite on va la modifier en prenant soin de mettre le bon no de révision 
        $uri = "https://{0}/api/v1/firewall/sections/{1}?action=lock" -f $this.server, $id


        # Valeur à mettre pour la configuration de la section de firewall
		$replace = @{sectionRevision = $section._revision}

        $body = $this.createObjectFromJSON("nsx-firewall-section-lock.json", $replace)

        # Verrouillage de la section
        return $this.callAPI($uri, "POST", $body)
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    							FIREWALL SECTION RULES
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
    #> 
    
    
    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute les règles dans une section de firewall
        
        IN  : $firewallSectionId    -> ID de la section de firewall
        
        RET : La liste des règles pour la section donnée
    #>
    [Array] getFirewallSectionRules([string]$firewallSectionId)
    {
        $uri = "https://{0}/api/v1/firewall/sections/{1}/rules" -f $this.server, $firewallSectionId

        return $this.callAPI($uri, "GET", $null).results
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute les règles dans une section de firewall
        
        IN  : $firewallSectionId    -> ID de la section de firewall
        IN  : $nameIn               -> Nom pour la règle "in"
        IN  : $nameCommunication    -> Nom pour la règle "communication"
        IN  : $nameOut              -> Nom pour la règle "out"
        IN  : $nsGroup              -> Objet représentant le NS Group lié aux règles
    #>
    [void] addFirewallSectionRules([string]$firewallSectionId, [string]$nameIn, [string]$nameCommunication, [string]$nameOut, [PSObject]$nsGroup)
    {
        $uri = "https://{0}/api/v1/firewall/sections/{1}/rules?action=create_multiple" -f $this.server, $firewallSectionId

		# Valeur à mettre pour la configuration des règles
		$replace = @{ruleNameIn             = $nameIn
                     ruleNameCommunication  = $nameCommunication
                     ruleNameOut            = $nameOut
                     nsGroupName            = $nsGroup.display_name
                     nsGroupId              = $nsGroup.id}

        $body = $this.createObjectFromJSON("nsx-firewall-section-rules.json", $replace)

        # Création des règles
        $dummy = $this.callAPI($uri, "Post", $body)
    }

}