<#
   BUT : Contient les fonctions donnant accès à l'API NSX

   Documentation: 
    - API:
        Swagger: https://code.vmware.com/apis/222/nsx-t
        Autre: https://vsissp-nsxm-t.epfl.ch/policy/api.html
    - Fichiers JSON utilisés: https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-NSX

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019

#>
enum NSXNSGroupMemberType {
    VirtualMachine
    LogicalSwitch
}

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
        # Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@( (Get-PSCallStack)[0].functionName) )
        
        $this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')
        
        $this.authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

        # Mise à jour des headers
        $this.headers.Add('Authorization', ("Remote {0}" -f $this.authInfos))

        # Mise à jour de l'URL de base pour accéder à l'API
        $this.baseUrl = "{0}/api/v1" -f $this.baseUrl
        
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
        $uri = "{0}/ns-groups/{1}" -f $this.baseUrl, $id

        $nsGroup = $this.callAPI($uri, "Get", $null)

        # Si le NS group existe (il devrait vu qu'on l'a cherché par ID)
        if($null -ne $nsGroup)
        {
            # on l'ajoute au cache
            $this.addInCache($nsGroup, $uri)
        }

        return $nsGroup
    }

    
       <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un NS Group donné par son nom

            L'API REST de NSX-T ne nous permet pas d'utiliser un filtre directement pour trouver le bon NSGroup avec le bon nom.
            Ce qu'on fait donc, c'est de récupérer la liste de tous les NSGroup (sans les référence) et on fait le filtre en PowerShell. 

            On fait ensuite une nouvelle requête avec l'ID pour récupérer uniquement le NSGroup mais cette fois-ci avec les références.

        IN  : $name         -> Nom du NS Group recherché

		RET : Le NS group 
    #>
    [PSObject] getNSGroupByName([string]$name)
    {
        # On commence par chercher les groupes "de base"
        $uri = "{0}/ns-groups/?populate_references=false" -f $this.baseUrl
        $results = ($this.callAPI($uri, "Get", $null)).results

        <# Recherche d'une autre manière, en prenant aussi les NSGroup pouvant contenir un certain type d'éléments.
        On est obligé de faire comme ça parce que NSX renvoie les NSGroup de manière un peu foireuse... il faut par
        exemple qu'un groupe ait contenu au moins un type d'élément avant de pouvoir être retourné par l'API #>
        [enum]::getvalues([NSXNSGroupMemberType]) | Foreach-Object {
            $uri = "{0}/ns-groups/?populate_references=false&member_types={1}" -f $this.baseUrl, $_.ToString()

            $results += ($this.callAPI($uri, "Get", $null)).results
        }
        

        $id =  ($results | Where-Object {$_.display_name -eq $name}).id | Sort-Object| Get-Unique
     
        if($null -eq $id)
        {
            return $null
        }
        # On check si on a plusieurs résultats
        elseif($id -is [Array])
        {
            Throw ("Multiple results ({0}) found for NSGroup '{1}'. Only one expected" -f $id.Count, $name)
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
        IN  : $memberType   -> Ce à quoi s'applique le NSGroup:
                                VirtualMachine
                                LogicalSwitch

		RET : Le NS group créé
	#>
    [PSObject] addNSGroup([string]$name, [string]$desc, [string] $tag, [NSXNSGroupMemberType]$memberType)
    {
		$uri = "{0}/ns-groups" -f $this.baseUrl

		# Valeur à mettre pour la configuration du NS Group
		$replace = @{
            name = $name
            description = $desc
            tag = $tag
            memberType = $memberType.toString()
        }

        $body = $this.createObjectFromJSON("nsx-nsgroup.json", $replace)
        
		# Création du NS Group
        $this.callAPI($uri, "Post", $body) | Out-Null
        
        # Retour du NS Group en le cherchant par son nom
        return $this.getNSGroupByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Met à jour un NS Group

        IN  : $nsGroup      -> Objet réprésentant le NSGroup à mettre à jour
		IN  : $nnewNameame  -> Le nouveau nom du groupe
		IN  : $newDesc	    -> La nouvelle description description
		IN  : $newTag	    -> Le nouveau nom du tag pour le membership

		RET : Le NS group mis à jour
	#>
    [PSObject] updateNSGroup([PSObject]$nsGroup, [string]$newName, [string]$newDesc, [string]$newTag)
    {
        $uri = "{0}/ns-groups/{1}" -f $this.baseUrl, $nsGroup.id

		# Valeur à mettre pour la configuration du NS Group
		$nsGroup.display_name = $newName
        $nsGroup.description = $newDesc
        $nsGroup.membership_criteria[0].tag = $newTag

        # Mise à jour du NS Group
        $this.callAPI($uri, "PUT", $nsGroup) | Out-Null
        
        # Retour du NS Group en le cherchant par son nom
        return $this.getNSGroupById($nsGroup.id)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Efface un NS Group

		IN  : $nsGroup  -> Objet représentant le NS Group à effacer
	#>
    [void] deleteNSGroup([PSObject]$nsGroup)
    {
        $uri = "{0}/ns-groups/{1}" -f $this.baseUrl, $nsGroup.id

        $this.callAPI($uri, "Delete", $null) | Out-Null
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
        # Création de la clef pour la gestion du cache
        $cacheKey = "FWSection_{0}_{1}_{2}" -f $name, $filterType, $type

        # Si c'est dans le cache, on retourne la valeur
        $fwSection = $this.getFromCache($cacheKey)
        if($null -ne $fwSection)
        {
            return $fwSection
        }
        if($filterType -eq "")
        {
            $filterType = "FILTER"
        }
        if($type -eq "")
        {
            $type = "LAYER3"
        }

		$uri = "{0}/firewall/sections?filter_type={1}&page_size=1000&search_invalid_references=false&type={2}" -f $this.baseUrl, $filterType, $type

        # Récupération de la liste
		$sectionList = $this.callAPI($uri, "GET", $null).results
        
        # Isolation de la section que l'on veut.
        $fwSection = $sectionList | Where-Object {$_.display_name -eq $name }

        # Si on a trouvé ce qu'on cherchait 
        if($null -ne $fwSection)
        {
            # On ajoute dans le cache
            $this.addInCache($fwSection, $cacheKey)
        }
        return $fwSection
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
        $uri = "{0}/firewall/sections/{1}" -f $this.baseUrl, $id

        # Création du NSGroup
		return $this.callAPI($uri, "GET", $null)
    }



    <#
		-------------------------------------------------------------------------------------
        BUT : Crée une section de firewall 
        
        IN  : $name	        -> Le nom de la section de firewall
        IN  : $desc         -> Description de la section
        IN  : $beforeId     -> (optionnel) ID de la section avant laquelle il faut insérer
        IN  : $nsGroup      -> NS Group créé auquel la section doit être liée

		RET : la section créée
    #>
    [PSObject] addFirewallSection([string]$name, [string]$desc, [string]$beforeId, [PSObject]$nsGroup)
    {
        
        $uri = "{0}/firewall/sections" -f $this.baseUrl
        
        # Si on doit insérer avant un ID donné
        if($beforeId -ne "")
        {
            $uri += ("?id={0}&operation=insert_before" -f $beforeId)
        }

		# Valeur à mettre pour la configuration de la section de firewall
		$replace = @{name = $name
                    desc = $desc
                    nsGroupId = $nsGroup.id
                    nsGroupName = $nsGroup.display_name}

        $body = $this.createObjectFromJSON("nsx-firewall-section.json", $replace)
        
		# Création de la section de firewall
        return $this.callAPI($uri, "Post", $body)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : met à jour une section de firewall 
        
        IN  : $section      -> Objet représentant la section à mettre à jour
        IN  : $newName      -> Nouveau nom de la section
        IN  : $newDesc      -> Nouvelle description
        IN  : $nsGroup      -> Le NSGroup à associer à la section 
                                ATTENTION!! Il est impératif que le NSGroup soit le même que celui
                                            qui est déjà configuré dans la section!! Il y a juste 
                                            son nom qui peut changer

        NOTE: Aucune idée s'il faut faire un "unlock" de la section avant de pouvoir modifier certains
                détails. Dans tous les cas, le nom (display_name) peut être changé sans faire un
                "unlock"

        RET : Section mise à jour
    #>
    [PSObject] updateFirewallSection([PSObject]$section, [string]$newName, [string]$newDesc, [PSObject]$nsGroup)
    {
        
        $uri = "{0}/firewall/sections/{1}" -f $this.baseUrl, $section.id

        $section.display_name = $newName
        $section.description = $newDesc
        ($section.applied_tos | Where-Object { $_.target_id -eq $nsGroup.id}).target_display_name = $nsGroup.display_name
        
		# Création de la section de firewall
        $this.callAPI($uri, "PUT", $section) | Out-Null
        
        return $this.getFirewallSectionById($section.id)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Efface une section de firewall et toutes les règles qui sont dedans
        
        IN  : $id	        -> ID de la section de firewall
    #>
    [void] deleteFirewallSection([string]$id)
    {
        
        $uri = "{0}/firewall/sections/{1}?cascade=true" -f $this.baseUrl, $id
        
		# Création de la section de firewall
        $this.callAPI($uri, "Delete", $null) | Out-Null
        
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Verrouille une section de firewall.
        
        IN  : $id       -> ID de la section à verrouiller

		RET : la section modifiée
    #>
    [PSObject] lockFirewallSection([string]$id)
    {
        return $this.lockUnlockFirewallSection($id, "lock")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Déverrouille une section de firewall.
        
        IN  : $id       -> ID de la section à déverrouiller

		RET : la section modifiée
    #>
    [PSObject] unlockFirewallSection([string]$id)
    {
        return $this.lockUnlockFirewallSection($id, "unlock")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Verrouille ou déverrouille une section de firewall. Quitte si celle-ci est déjà verrouillée.
        
        IN  : $id       -> ID de la section à verrouiller ou déverrouiller
        IN  : $action   -> Action à effectuer 
                            "lock"
                            "unlock"

		RET : la section modifiée
    #>
    hidden [PSObject] lockUnlockFirewallSection([string]$id, [string]$action)
    {
        # on commence par récupérer les informations de la section
        $section = $this.getFirewallSectionById($id)

        if($null -eq $section)
        {
            Throw ("Firewall section with ID {0} not found!" -f $id)
        }

        # Si la section est déjà dans l'état où on veut la mettre, on la retourne tout simplement
        if(($action -eq "lock" -and $section.locked) -or ($action -eq "unlock" -and !$section.locked))
        {
            return $section
        }

        # Ensuite on va la modifier en prenant soin de mettre le bon no de révision 
        $uri = "{0}/firewall/sections/{1}?action={2}" -f $this.baseUrl, $id, $action


        # Valeur à mettre pour la configuration de la section de firewall
		$replace = @{
            sectionRevision = $section._revision
            comment = ("Section action: {0}" -f $action)
        }

        $body = $this.createObjectFromJSON("nsx-firewall-section-lock-unlock.json", $replace)

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
        $uri = "{0}/firewall/sections/{1}/rules" -f $this.baseUrl, $firewallSectionId

        return $this.callAPI($uri, "GET", $null).results
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute les règles dans une section de firewall
        
        IN  : $firewallSectionId    -> ID de la section de firewall
        IN  : $ruleIn               -> Tableau associatif pour la règle "in"
        IN  : $ruleComm             -> Tableau associatif pour la règle "communication"
        IN  : $ruleOut              -> Tableau associatif pour la règle "out"
        IN  : $ruleDeny             -> Tableau associatif pour la règle "deny"
        IN  : $nsGroup              -> Objet représentant le NS Group lié aux règles

        Tableau associatif pour les règles :
        - name
        - tag

        RET : La liste des règles pour la section donnée
    #>
    [Array] addFirewallSectionRules([string]$firewallSectionId, [Hashtable]$ruleIn, [Hashtable]$ruleComm, [Hashtable]$ruleOut, [hashtable]$ruleDeny, [PSObject]$nsGroup)
    {
        $uri = "{0}/firewall/sections/{1}/rules?action=create_multiple" -f $this.baseUrl, $firewallSectionId

		# Valeur à mettre pour la configuration des règles
        $replace = @{
            # IN
            ruleNameIn             = $ruleIn.name
            ruleTagIn              = $ruleIn.tag
            # Communication
            ruleNameCommunication  = $ruleComm.name
            ruleTagCommunication   = $ruleComm.tag
            # Out
            ruleNameOut            = $ruleOut.name
            ruleTagOut             = $ruleOut.tag
            # Deny
            ruleNameDeny           = $ruleDeny.name
            ruleTagDeny            = $ruleDeny.tag
            # NSGroup
            nsGroupName            = $nsGroup.display_name
            nsGroupId              = $nsGroup.id}

        $body = $this.createObjectFromJSON("nsx-firewall-section-rules.json", $replace)

        # Création des règles
        $this.callAPI($uri, "Post", $body) | Out-Null

        return $this.getFirewallSectionRules($firewallSectionId)
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Efface les règles de Firewall d'une section
        
        IN  : $firewallSectionId    -> ID de la section de firewall
    #>
    [void] deleteFirewallSectionRules([string]$firewallSectionId)
    {
        # Déverrouillage de la section au cas où, histoire de pas se chopper une exception
        $this.unlockFirewallSection($firewallSectionId)

        $ruleList = $this.getFirewallSectionRules($firewallSectionId)

        ForEach($rule in $ruleList)
        {
            $uri = "{0}/firewall/sections/{1}/rules/{2}" -f $this.baseUrl, $firewallSectionId, $rule.id

            $this.callAPI($uri, "DELETE", $null) | Out-Null
        }
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    							        ENTITES
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
    #> 

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une virtual machine définie dans NSX
        
        IN  : $vmName    -> Nom de la VM

        RET :  Objet représentant la VM
                $null si pas trouvé
      
        https://code.vmware.com/apis/222/nsx-t#/Fabric/ListVirtualMachines
    #>
    [PSObject] getVirtualMachine([string]$vmName)
    {
        $uri = "{0}/fabric/virtual-machines?display_name={1}" -f $this.baseUrl, $vmName

        $res = $this.callAPI($uri, "GET", $null).results

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
                                            TAGS
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
    #> 

    <#
		-------------------------------------------------------------------------------------
        BUT : Initialise les tags d'une VM
        
        IN  : $vm       -> Objet représentant la VM (renvoyé par getVirtualMachine() )
        IN  : $tagList  -> Tableau associatif avec la liste des tags, avec en clef
                            le nom du tag et en valeur, ben sa valeur...
      
        RET : Objet représentant la VM mise à jour

        https://code.vmware.com/apis/222/nsx-t#/Fabric/ListVirtualMachines
    #>
    [PSObject] setVirtualMachineTags([PSObject]$vm, [Hashtable]$tagList)
    {
        $uri = "{0}/fabric/virtual-machines?action=update_tags" -f $this.baseUrl

        $replace = @{
            externalId = $vm.external_id
        }

        $body = $this.createObjectFromJSON("nsx-vm-tag-list.json", $replace)

        $tagList.keys | Foreach-Object {
            $replace = @{
                tag = $_
                scope = $tagList.Item($_)
            }
            $body.tags += $this.createObjectFromJSON("nsx-tag.json", $replace)
        }

        # Création des règles
        $this.callAPI($uri, "Post", $body) | Out-Null

        return $this.getVirtualMachine($vm.display_name)
    }


}