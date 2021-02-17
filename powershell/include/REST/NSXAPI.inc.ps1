<#
   BUT : Contient les fonctions donnant accès à l'API NSX

   Documentation: 
    - API: https://code.vmware.com/apis/222/nsx-t
    - Fichiers JSON utilisés: https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976#Ressources-PRJ0011976-NSX

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base
   0.2 - Ajout d'un filtre dans la récupération des NSGroups
   0.3 - Ajout d'un cache pour certains éléments.

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
        $this.headers.Add('X-Allow-Overwrite', 'true')
        
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
        IN  : $memberType   -> Ce à quoi s'applique le NSGroup:
                                VirtualMachine
                                LogicalSwitch

		RET : Le NS group 
    #>
    [PSObject] getNSGroupByName([string]$name, [string]$memberType)
    {
        # Note: On filtre exprès avec 'member_types=VirtualMachine' car sinon tous les NSGroup attendus ne sont pas renvoyés... 
        $uri = "{0}/ns-groups/?populate_references=false&member_types={1}" -f $this.baseUrl, $memberType

        $id =  ($this.callAPI($uri, "Get", $null).results | Where-Object {$_.display_name -eq $name}).id
     
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
		BUT : Crée un NS Group pour des machines virtuelles

		IN  : $name	        -> Le nom du groupe
		IN  : $description	-> La description
		IN  : $tag	        -> Le nom du tag pour le membership

		RET : Le NS group créé
	#>
    [PSObject] addNSGroupVirtualMachine([string]$name, [string]$desc, [string] $tag)
    {
		$uri = "{0}/ns-groups" -f $this.baseUrl

		# Valeur à mettre pour la configuration du NS Group
		$replace = @{name = $name
					description = $desc
					tag = $tag}

        $body = $this.createObjectFromJSON("nsx-nsgroup-virtual-machine.json", $replace)
        
		# Création du NS Group
        $this.callAPI($uri, "Post", $body) | Out-Null
        
        # Retour du NS Group en le cherchant par son nom
        return $this.getNSGroupByName($name, "VirtualMachine")
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Crée un NS Group pour un cluster K8s donné

		IN  : $name	        -> Le nom du groupe
		IN  : $description	-> La description
		IN  : $clusterUUID  -> UUID du cluster K8s

		RET : Le NS group créé
	#>
    [PSObject] addNSGroupK8sCluster([string]$name, [string]$desc, [string] $clusterUUID)
    {
		$uri = "{0}/ns-groups" -f $this.baseUrl

		# Valeur à mettre pour la configuration du NS Group
		$replace = @{name = $name
					description = $desc
					clusterUUID = $clusterUUID}

        $body = $this.createObjectFromJSON("nsx-nsgroup-xaas-k8s-cluster.json", $replace)
        
		# Création du NS Group
        $this.callAPI($uri, "Post", $body) | Out-Null
        
        # Retour du NS Group en le cherchant par son nom
        return $this.getNSGroupByName($name, "LogicalSwitch")
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un membre de type NSGroup à un NSGroup existant

		IN  : $nsGroup          -> Objet représentant le NSGroup auquel ajouter le membre
		IN  : $nsGroupToAdd     -> Objet représentant le NSGroup à ajouter

		RET : Le NS group modifié
	#>
    [PSObject] addNSGroupMemberNSGroup([PSObject]$nsGroup, [PSObject]$nsGroupToAdd)
    {
        # Si le membre n'est pas encore présent
        if($null -eq ($nsGroup.members | Where-Object { $_.value -eq $nsGroupToAdd.id}))
        {
            $uri = "{0}/ns-groups/{1}" -f $this.baseUrl, $nsGroup.id

            # Valeur à mettre pour ajouter le membre
            $replace = @{nsGroupId = $nsGroupToAdd.id }

            $newMember = $this.createObjectFromJSON("nsx-nsgroup-member-nsgroup.json", $replace)

            $nsGroup.members += $newMember

            $this.callAPI($uri, "PUT", $nsGroup) | Out-Null
        }

        return $nsGroup
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Ajoute un membre de type NSGroup à un NSGroup existant

		IN  : $nsGroup          -> Objet représentant le NSGroup auquel ajouter le membre
		IN  : $nsGroupToAdd     -> Objet représentant le NSGroup à ajouter

		RET : Le NS group modifié
	#>
    [PSObject] removeNSGroupMemberFromNSGroup([PSObject]$nsGroup, [PSObject]$nsGroupToRemove)
    {
        # On génère la liste des membres en enlevant celui qu'on doit enlever
        # On met @() pour être sûr d'avoir une liste et pas un $null dans le cas où ça serait
        # le dernier NSGroup membre que l'on voudrait supprimer
        $newMembers = @(($nsGroup.members | Where-Object { $_.value -ne $nsGroupToRemove.id}))

        # Si le NSGroup à supprimer était bien présent dans la liste,
        if($newMembers.count -ne $nsGroup.Members.count)
        {
            $uri = "{0}/ns-groups/{1}" -f $this.baseUrl, $nsGroup.id

            $nsGroup.members = $newMembers

            $this.callAPI($uri, "PUT", $nsGroup) | Out-Null
        }

        return $nsGroup
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
    [PSObject] updateFirewallSection([PSObject]$section, [string]$newName, [string]$newDesc, [string]$nsGroup)
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
        $uri = "{0}/firewall/sections/{1}?action=lock" -f $this.baseUrl, $id


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
        BUT : Renvoie la liste des règles pour une section de Firewall
        
        IN  : $firewallSectionId    -> ID de la section de firewall
        
        RET : La liste des règles pour la section donnée
    #>
    [Array] getFirewallSectionRulesList([string]$firewallSectionId)
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
    #>
    [void] addFirewallSectionRules([string]$firewallSectionId, [Hashtable]$ruleIn, [Hashtable]$ruleComm, [Hashtable]$ruleOut, [hashtable]$ruleDeny, [PSObject]$nsGroup)
    {
        $uri = "{0}/firewall/sections/{1}/rules?action=create_multiple" -f $this.baseUrl, $firewallSectionId

		# Valeur à mettre pour la configuration des règles
        $replace = @{ruleNameIn             = $ruleIn.name
                     ruleTagIn              = $ruleIn.tag
                     ruleNameCommunication  = $ruleComm.name
                     ruleTagCommunication   = $ruleComm.tag
                     ruleNameOut            = $ruleOut.name
                     ruleTagOut             = $ruleOut.tag
                     ruleNameDeny           = $ruleDeny.name
                     ruleTagDeny            = $ruleDeny.tag
                     nsGroupName            = $nsGroup.display_name
                     nsGroupId              = $nsGroup.id}

        $body = $this.createObjectFromJSON("nsx-firewall-section-rules.json", $replace)

        # Création des règles
        $this.callAPI($uri, "Post", $body) | Out-Null
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    									IP POOLS
		-------------------------------------------------------------------------------------
        -------------------------------------------------------------------------------------
	#>

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des Pools IP existants
        
        RET : La liste des règles pour la section donnée

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool Management/ListIpPools
    #>
    [Array] getIPPoolList()
    {
        $uri = "{0}/pools/ip-pools" -f $this.baseUrl

        return $this.callAPI($uri, "GET", $null).results
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une pool IP par son nom
        
        IN  : $name -> nom de la pool que l'on désire

        RET : Info sur la pool 
                $null si pas trouvé

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool Management/ListIpPools
    #>
    [PSObject] getIPPoolByName([string]$name)
    {
        return $this.getIPPoolList() | Where-Object { $_.display_name -eq $name }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un pool IP par son ID
        
        IN  : $poolId -> nom du pool que l'on désire

        RET : Info sur la pool 
                $null si pas trouvé

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool Management/ListIpPools
    #>
    [PSObject] getIPPoolByID([string]$poolId)
    {
        $uri = "{0}/pools/ip-pools/{1}" -f $this.baseUrl, $poolId

        return $this.callAPI($uri, "GET", $null).results
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Alloue et renvoie une adresse IP disponible dans un pool
        
        IN  : $id -> nom du pool dans lequel piocher l'adresse IP

        RET : Adresse IP

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool Management/ListIpPools
    #>
    [string] allocateIPAddressInPool([string]$poolId)
    {
        $uri = "{0}/pools/ip-pools/{1}?action=ALLOCATE" -f $this.baseUrl, $poolId

         # Valeur à mettre pour la configuration des règles
         $replace = @{
            ipAddress = @("null", $true)
        }

        $body = $this.createObjectFromJSON("nsx-allocate-release-ip-address.json", $replace)

        return $this.callAPI($uri, "POST", $body).allocation_id
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Libère une adresse IP disponible dans un pool.
        
        IN  : $id -> nom du pool dans lequel piocher l'adresse IP

        RET : Adresse IP

        NOTE : Il faut savoir que la restitution d'adresse IP est beaucoup plus lente que l'allocation.
                L'appel à la commande sera rapide mais d'ici à ce que l'IP soit libérée de manière
                effective dans le pool, il pourra s'écouler quelques minutes.

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool Management/ListIpPools
    #>
    [void] releaseIPAddressInPool([string]$poolId, [string]$ipAddress)
    {
        $uri = "{0}/pools/ip-pools/{1}?action=RELEASE" -f $this.baseUrl, $poolId

        # Valeur à mettre pour la configuration des règles
        $replace = @{
            ipAddress = $ipAddress
        }

        $body = $this.createObjectFromJSON("nsx-allocate-release-ip-address.json", $replace)

        $this.callAPI($uri, "Post", $body) | Out-Null
    }
    

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des adresses IP allouées dans un Pool
        
        IN  : $poolId -> ID du pool dans lequel on veut lister les adresses IP

        RET : Tableau avec les adresses IP

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Pool%20Management/ListIpPoolAllocations
    #>
    [Array] getPoolIPAllocatedAddressList([string]$poolId)
    {
        $uri = "{0}/pools/ip-pools/{1}/allocations" -f $this.baseUrl, $poolId

        return $this.callAPI($uri, "GET", $null).results | Select-Object -ExpandProperty allocation_id
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Permet de savoir si une IP est allouée dans le pool donné
        
        IN  : $poolId       -> ID du pool dans lequel on veut veut savoir si une IP est allouée
        IN  : $ipAddress    -> Adresse IP dont on veut savoir si elle a été allouée

        RET : $true ou $false pour dire si alloué ou pas.
    #>
    [bool] isIPAllocated([string]$poolId, [string]$ipAddress)
    {
        return ($this.getPoolIPAllocatedAddressList($poolId) -contains $ipAddress)
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    							LOAD BALANCER - SERVICES
		-------------------------------------------------------------------------------------
        -------------------------------------------------------------------------------------
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des services de load balancing
        
        RET : Tableau avec les services

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/ListLoadBalancerServices
    #>
    [Array] getLBServiceList()
    {
        $uri = "{0}/loadbalancer/services" -f $this.baseUrl

        return $this.callAPI($uri, "GET", $null).results
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un service du load balancer
        
        IN  : $serviceId    -> ID du service à supprimer

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/DeleteLoadBalancerService
    #>
    [void] deleteLBService([string]$serviceId)
    {
        $uri = "{0}/loadbalancer/services/{1}" -f $this.baseUrl, $serviceId

        $this.callAPI($uri, "DELETE", $null) | Out-Null
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le service de load balancer associé à un cluster

        IN  : $clusterId    -> ID du cluster
        
        RET : Objet avec le service

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/ListLoadBalancerServices
    #>
    [PSObject] getClusterLBService([string]$clusterId)
    {
        return $this.getLBServiceList() | Where-Object { $_.display_name -eq ("lb-pks-{0}" -f $clusterId) }
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    						LOAD BALANCER - VIRTUAL SERVERS
		-------------------------------------------------------------------------------------
        -------------------------------------------------------------------------------------
    #>
    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie les infos d'un serveur virtuel
        
        IN  : $virtualServerId -> ID du serveur virtuel

        RET : Objet avec les infos

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/ListLoadBalancerVirtualServers
    #>
    [PSObject] getLBVirtualServer([string]$virtualServerId)
    {
        $uri = "{0}/loadbalancer/virtual-servers/{1}" -f $this.baseUrl, $virtualServerId

        return $this.callAPI($uri, "GET", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un virtual server d'un load balancer
        
        IN  : $virtualServerId    -> ID du virtual server à supprimer

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/DeleteLoadBalancerVirtualServer
    #>
    [void] deleteLBVirtualServer([string]$virtualServerId)
    {
        $uri = "{0}/loadbalancer/virtual-servers/{1}/?delete_associated_rules=true" -f $this.baseUrl, $virtualServerId

        $this.callAPI($uri, "DELETE", $null) | Out-Null
    }


    <#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	    						LOAD BALANCER - PROFILES
		-------------------------------------------------------------------------------------
        -------------------------------------------------------------------------------------
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des services de load balancing
        
        RET : Tableau avec les services

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/ListLoadBalancerApplicationProfiles
    #>
    [Array] getLBAppProfileList()
    {
        $uri = "{0}/loadbalancer/application-profiles" -f $this.baseUrl

        return $this.callAPI($uri, "GET", $null).results
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des applications profiles associés à un cluster

        IN  : $clusterId    -> ID du cluster
        
        RET : Tableau des Application profiles

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/ListLoadBalancerApplicationProfiles
    #>
    [Array] getClusterLBAppProfileList([string]$clusterId)
    {
        return $this.getLBAppProfileList() | Where-Object { $_.display_name.startswith("ncp-pks-{0}" -f $clusterId) }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un application profile d'un load balancer
        
        IN  : $appProfileId    -> ID de l'application profile à supprimer

        https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api#/Services/DeleteLoadBalancerApplicationProfile
    #>
    [void] deleteLBAppProfile([string]$appProfileId)
    {
        $uri = "{0}/loadbalancer/application-profiles/{1}" -f $this.baseUrl, $appProfileId

        $this.callAPI($uri, "DELETE", $null) | Out-Null
    }

}