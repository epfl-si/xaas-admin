<#
   BUT : Contient les fonctions donnant accès à l'API vRA

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019

    Un peu de documentation:
    http://cloudmaniac.net/nsx-t-api-embedded-documentation-and-postman-collection/
    https://sostechblog.com/2018/08/07/nsx-t-a-k-a-nsx-cloud-api-tips-and-tricks/

    et celui-ci spécifique sur Postman:
    http://cloudmaniac.net/why-postman-api-client/
    Doc API
    https://code.vmware.com/apis/270/nsx-t-data-center-nsx-t-data-center-rest-api

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NSXAPI: RESTAPI
{
    hidden [string]$authInfos
    hidden [System.Collections.Hashtable]$headers
    
    <#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $username     	-> Nom d'utilisateur (local)
		IN  : $password			-> Mot de passe
	#>
	NSXAPI([string] $server, [string] $username, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
        $this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')
        
        $this.authInfos = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(("{0}:{1}" -f $username,$password)))

        # Mise à jour des headers
        $this.headers.Add('Authorization', ("Basic {0}" -f $this.authInfos))
        
        <# Pour autoriser les certificats self-signed, on créé une policy que l'on assigne ensuite au bon endroit. 
         https://stackoverflow.com/questions/31360980/runspace-issus-using-async-apis-from-powershell
        
         En effet, avec NSX, pour une raison inconnue, utiliser les 2 lignes plus bas pour ignorer les certificats "Self-Signed",
         ça ne fonctionne pas et ça amène à l'erreur : 
        
         There is no Runspace available to run scripts in this thread. You can provide one in the DefaultRunspace property of the 
         System.Management.Automation.Runspaces.Runspace type. The script block you attempted to invoke was: $true
        
         [System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }
         [Net.ServicePointManager]::SecurityProtocol += [Net.SecurityProtocolType]::Tls12
        #>

        Add-Type " 
            using System.Net; 
            using System.Security.Cryptography.X509Certificates; 
        
            public class NoSSLCheckPolicy : ICertificatePolicy { 
                public NoSSLCheckPolicy() {} 
                public bool CheckValidationResult( 
                    ServicePoint sPoint, X509Certificate cert, 
                    WebRequest wRequest, int certProb) { 
                    return true; 
                } 
            } 
        "
        [System.Net.ServicePointManager]::CertificatePolicy = new-object NoSSLCheckPolicy 

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

        return $this.callAPI($uri, "Get", "").content
        
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

        $id = (($this.callAPI($uri, "Get", "").content) | Where-Object {$_.display_name -eq $name}).id
     
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

        $body = $this.loadJSON("nsx-nsgroup.json", $replace)
        
		# Création du NS Group
        $res = $this.callAPI($uri, "Post", (ConvertTo-Json -InputObject $body -Depth 20))       
        
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

        # Création du NSGroup
		$res = $this.callAPI($uri, "GET", "")
        
        # Retour de celui-ci
        return $res | Where-Object {$_.display_name -eq $name }
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
		return $this.callAPI($uri, "GET", "").content
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
					description = $desc}

        $body = $this.loadJSON("nsx-firewall-section.json", $replace)
        
		# Création de la section de firewall
        $res = $this.callAPI($uri, "Post", (ConvertTo-Json -InputObject $body -Depth 20))       
        
        # Retour de la section de firewall en la cherchant par son nom
        return $this.getFirewallSection($name)
    }



    <#
		-------------------------------------------------------------------------------------
        BUT : Verrouille une section de firewall
        
        IN  : $id       -> ID de la section à verrouiller

		RET : la section modifiée
    #>
    [void] lockFirewallSection([string]$id)
    {
        # on commence par récupérer les informations de la section
        $section = $this.getFirewallSectionById($id)

        if($null -eq $section)
        {
            Throw ("Firewall section with ID {0} not found!" -f $id)
        }

        # Ensuite on va la modifier en prenant soin de mettre le bon no de révision 
        $uri = "https://{0}/api/v1/firewall/sections/{1}?action=lock" -f $this.server


        # Valeur à mettre pour la configuration de la section de firewall
		$replace = @{sectionRevision = $section._revision}

        $body = $this.loadJSON("nsx-firewall-section-lock.json", $replace)

        # Verrouillage de la section
        $res = $this.callAPI($uri, "Put", (ConvertTo-Json -InputObject $body -Depth 20))   
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
        IN  : $nameIn               -> Nom pour la règle "in"
        IN  : $nameCommunication    -> Nom pour la règle "communication"
        IN  : $nameOut              -> Nom pour la règle "out"
        IN  : $nsGroup              -> Objet représentant le NS Group lié aux règles
    #>
    [void] addFirewallSectionRules([string]$firewallSectionId, [string]$nameIn, [string]$nameCommunication, [string]$nameOut, [PSObject]$nsGroup)
    {
        $uri = "https://{0}/api/v1/firewall/sections/{1}/rules?action=create_multiple&operation=insert_top" -f $this.server, $firewallSectionId

		# Valeur à mettre pour la configuration des règles
		$replace = @{ruleNameIn             = $nameIn
                     ruleNameCommunication  = $nameCommunication
                     ruleNameOut            = $nameOut
                     nsGroupName            = $nsGroup.display_name
                     nsGroupId              = $nsGroup.id}

        $body = $this.loadJSON("nsx-firewall-section-rules", $replace)

        # Création des règles
        $res = $this.callAPI($uri, "Post", (ConvertTo-Json -InputObject $body -Depth 20))       
    }





















    [psobject]getNSGroups()
    {
        $uri = "https://{0}/api/v1/ns-groups" -f $this.server
        return $this.callAPI($uri, "Get", "")
        
    }
}