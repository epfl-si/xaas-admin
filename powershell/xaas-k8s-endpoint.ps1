<#
USAGES:
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action create -bgId <bgId> -plan <plan> -netProfile <netProfile>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delete -bgId <bgId> -clusterName <clusterName> [-clusterUUID <clusterUUID>]
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getClusterInfos -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action setNbWorkers -clusterName <clusterName> -nbWorkers <nbWorkers>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNbWorkers -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action addNamespace -bgId <bgId> -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNamespaceList -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delNamespace -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNamespaceResources -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action addLB -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNBLB -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delLB -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action extendNamespaceStorage -clusterName <clusterName> -namespace <namespace> -extSizeGB <extSizeGB>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action addRobot -bgId <bgId> -clusterName <clusterName>
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service K8s (Kubernetes) en tant que XaaS.
                  

	DATE 	: Octobre 2020
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    Confluence :
        Documentation - https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=99188910                                

#>
param([string]$targetEnv,
      [string]$targetTenant,
      [string]$action,
      [string]$bgId,
      [string]$plan,
      [int]$nbWorkers,
      [string]$netProfile,
      [string]$clusterName,
      [string]$clusterUUID,
      [string]$namespace,
      [int]$extSizeGB)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLDNS.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "NameGeneratorK8s.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "TKGIKubectl.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NSXAPI.inc.ps1"))

# Chargement des fichiers propres au PKS VMware
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "K8s", "PKSAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "K8s", "HarborAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configVra = [ConfigReader]::New("config-vra.json")
$configK8s = [ConfigReader]::New("config-xaas-k8s.json")
$configNSX = [ConfigReader]::New("config-nsx.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE                      = "create"
$ACTION_DELETE                      = "delete"
$ACTION_GET_CLUSTER_INFOS           = "getClusterInfos"
$ACTION_GET_NB_WORKERS              = "getNbWorkers"
$ACTION_SET_NB_WORKERS              = "setNbWorkers"
$ACTION_ADD_NAMESPACE               = "addNamespace"
$ACTION_GET_NAMESPACE_LIST          = "getNamespaceList"
$ACTION_DELETE_NAMESPACE            = "delNamespace"
$ACTION_ADD_LOAD_BALANCER           = "addLB"
$ACTION_GET_NB_LOAD_BALANCER        = "getNBLB"
$ACTION_DELETE_LOAD_BALANCER        = "delLB"
$ACTION_EXTEND_NAMESPACE_STORAGE    = "extendNamespaceStorage"
$ACTION_GET_NAMESPACE_RESOURCES     = "getNamespaceResources"
$ACTION_ADD_ROBOT                   = "addRobot"

$ROBOT_NB_DAYS_LIFETIME         = 7


# -------------------------------------------- FONCTIONS ---------------------------------------------------

<#
    -------------------------------------------------------------------------------------
    BUT : Recherche et renvoie le prochain nom de cluster qu'on peut utiliser

    IN  : $str -> la chaine de caractères à transformer

    RET : Le nom du cluster
#>
function getNextClusterName([PKSAPI]$pks, [NameGeneratorK8s]$nameGeneratorK8s)
{
    $regex = $nameGeneratorK8s.getClusterRegex()

    $no = 1

    # On recherche maintenant la liste de tous les clusters, 
    # NDLR: Pour une fois, on utilise vraiment la puissance de PowerShell pour le traitement, ça a un côté limite émouvant... mais il 
    # ne faut pas oublier une chose, "un grand pouvoir implique de grandes responsabilités"
    $pks.getClusterList() | `
        Where-Object { [Regex]::Match($_.name, $regex).Length -gt 0 } | ` # On filtre sur les bons noms avec la regex
        Select-Object -ExpandProperty name | ` # On récupère uniquement le nom
        Sort-Object | ` # Et on trie dans l'ordre croissant des noms
        ForEach-Object { # Et on boucle

            # Si le numéro du cluster courant n'existe pas, 
            if([int]([Regex]::Match($_, $regex).Groups[1].value) -ne $no)
            {
                # on le prend
                return
            }
            $no++
        }
    
    # Arrivé ici, $no contient le numéro du prochain cluster, on peut donc le générer
    return $nameGeneratorK8s.getClusterName($no)
}


<#
    -------------------------------------------------------------------------------------
    BUT : Efface un cluster, sans sommation, ni prévenir la famille à la fin.

    IN  : $pks              -> Objet permettant d'accéder à l'API de PKS
    IN  : $nsx              -> Objet permettant d'accéder à l'API de NSX
    IN  : $EPFLDNS          -> Objet permettant de jouer avec le DNS
    IN  : $nameGeneratorK8s -> Objet pour la génération des noms
    IN  : $harbor           -> Objet permettant d'accéder à l'API de Harbor
    IN  : $clusterName      -> Nom du cluster à supprimer
    IN  : $clusterUUID      -> UUID du cluster (peut être $null, à passer si on veut "finaliser" la procédure d'effacement
                                pour un cluster déjà effacé mais que le reste n'a pas pu être traité.)
    IN  : $ipPoolName       -> Nom du pool IP dans NSX
    IN  : $targetTenant     -> Tenant cible
#>
function deleteCluster([PKSAPI]$pks, [NSXAPI]$nsx, [EPFLDNS]$EPFLDNS, [NameGeneratorK8s]$nameGeneratorK8s, [HarborAPI]$harbor, [string]$clusterName, [string]$clusterUUID, [string]$ipPoolName, [string]$targetTenant)
{
    # Le nom du cluster peut être encore vide dans le cas où une erreur surviendrait avait que le nom soit initialisé. 
    # Dans ce cas, on ne fait rien
    if($clusterName -eq "")
    {
        $logHistory.addLine("Cluster to delete has empty name, maybe it wasn't initialized before and error occured and the this 'delete' function was called.")
        return
    }

    # Recherche du cluster par son nom
    $cluster = $pks.getCluster($clusterName)

    # ------------
    # ---- Cluster
    if($null -ne $cluster)
    {
        # Mise à jour pour plus loin
        $clusterUUID = $cluster.uuid

        $logHistory.addLine(("Deleting cluster '{0}' ({1}). This also can take a while... so... another coffee ?..." -f $clusterName, $cluster.uuid))
        # On attend que le cluster ait été effacé avant de rendre la main et passer à la suite du job
        $pks.deleteCluster($clusterName)
        $logHistory.addLine("Cluster deleted")
    }
    else # Cluster pas trouvé
    {
        $logHistory.addLine(("Cluster '{0}' doesn't exists" -f $clusterName))
    }

    # -----------
    # ---- Réseau

    $hostnameList = @(
        # On efface d'abord l'entrée 'ingress' car elle a été créé en dernier
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryIngress)    
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryMain)
    )
    
    $logHistory.addLine("Deleting IPs...")
    # Parcours des noms IP à effacer
    ForEach($hostname in $hostnameList)
    {
        $hostnameFull = ("{0}.{1}" -f $hostname, $global:K8S_DNS_ZONE_NAME)
        
        $logHistory.addLine(("> IP {0} and host '{1}'" -f $ip, $hostnameFull))
        $logHistory.addLine("> Unregistering IP(s) for host in DNS if exists...")
        $EPFLDNS.unregisterDNSName($hostname, $global:K8S_DNS_ZONE_NAME)

        
    }# FIN BOUCLE de parcours des Noms IP à supprimer

    # --------
    # ---- NSX
    # Si on a des infos sur le cluster
    if($clusterUUID -ne "")
    {
        $logHistory.addLine("Deleting Load Balancer application profiles...")
        $appProfileList = $nsx.getClusterLBAppProfileList($clusterUUID)

        if($null -eq $appProfileList)
        {
            $logHistory.addLine("No application profile found... cleaning has been correctly done by PSK while deleting cluster")
        }
        # Parcours des application profiles à supprimer
        Foreach($appProfile in $appProfileList)
        {
            $logHistory.addLine(("> {0}..." -f $appProfile.display_name))
            $nsx.deleteLBAppProfile($appProfile.id)
        }
    }
    else
    {
        $logHistory.addLine("Cluster not found before so we can't delete associated Load Balancer application profiles :-/")
    }

    # # ------------------
    # # ---- Projet Harbor
    # FIXME: Voir pour finaliser cette partie
    # $harborProjectName = $nameGeneratorK8s.getHarborProjectName()
    # $logHistory.addLine(("Cleaning Harbor project ({0}) if needed..." -f $harborProjectName))
    
    # if($targetTenant -eq $global:VRA_TENANT__EPFL)
    # {
    #     <# Rien besoin de faire pour ce tenant car il y a un projet Harbor par faculté donc on n'a pas besoin 
    #         de supprimer quoi que ce soit. On pourrait supprimer le groupe AD correspondant au BG mais il n'est 
    #         pertinent de supprimer ce groupe d'accès uniquement si on vient de supprimer le tout dernier cluster
    #         pour le Business Group #>
    #     $logHistory.addLine("> We're on EPFL tenant, one project per Faculty so no cleaning")
    # }
    # else # Tenant ITServices ou Research
    # {
    #     $harborProject = $harbor.getProject($harborProjectName)
    #     if($null -ne $harborProject)
    #     {
    #         # On a un Projet Harbor par service donc on peut faire du ménage d'office
    #         $logHistory.addLine(("> Removing Project '{0}'..." -f $harborProjectName))
    #         $harbor.deleteProject($harborProject)
    #     }
    #     else # Le projet n'existe pas
    #     {
    #         $logHistory.addLine(("> Project '{0}' doesn't exists" -f $harborProjectName))
    #     }
    # }
    
}


<#
    -------------------------------------------------------------------------------------
    BUT : Cherche quelle est l'adresse IP "ingress" qui a été attribuée automatiquement
            au cluster par PKS en allant la chercher dans NSX.

    IN  : $clusterIP        -> Adresse IP du cluster, pour pouvoir retrouver celle pour Ingress
    IN  : $nsx              -> Objet permettant d'accéder à l'API de NSX
#>
function searchClusterIngressIPAddress([string]$clusterIP, [NSXAPI]$nsx)
{
    $loadBalancerServices = $nsx.getLBServiceList()

    # Parcours des services trouvés
    ForEach($service in $loadBalancerServices)
    {
        $ipList = @()

        # Parcours des serveurs virtuels du LoadBalancer pour récupérer leurs IP
        ForEach($virtualServerId in $service.virtual_server_ids)
        {
            $ipList += $nsx.getLBVirtualServer($virtualServerId).ip_address
        }

        # Si l'adresse IP du cluster se trouve dans la liste du service courant
        if($ipList -contains $clusterIP)
        {
            # On retourne l'ip qui reste
            return $ipList | Where-Object { $_ -ne $clusterIP} | Get-Unique
        }
    }

    return $null
}


<#
    -------------------------------------------------------------------------------------
    BUT : Configure les éléments pour un Namespace existant

    IN  : $clusterName      -> Le nom du cluster
    IN  : $namespace        -> Nom du namespace à configurer
    IN  : $targetEnv        -> Environnement cible (prod/test/dev)
    IN  : $adGroupList      -> Liste des groupe AD sur lesquels donner les droits
    IN  : $nameGeneratorK8s -> Générateur de noms
    IN  : $tkgiKubectl      -> Objet pour accéder aux commandes TKGI et Kubectl
    IN  : $logHistory       -> Objet pour avoir un fichier Log de l'exécution
#>
function configureNamespaceElements([string]$clusterName, [string]$namespace, [string]$targetEnv, [Array]$adGroupList, [NameGeneratorK8s]$nameGeneratorK8s, [TKGIKubectl]$tkgiKubectl, [LogHistory]$logHistory)
{
    # - Resource Quota
    $logHistory.addLine("Adding ResourceQuota...")
    $tkgiKubectl.addOrUpdateClusterNamespaceResourceQuota($clusterName, 
                                                $namespace,                                               
                                                $nameGeneratorK8s.getResourceQuotaName($clusterName, $namespace),
                                                $global:RESOURCE_QUOTA_LB_AND_NODEPORTS, 
                                                $global:RESOURCE_QUOTA_LB_AND_NODEPORTS, 
                                                $configK8s.getConfigValue(@($targetEnv, "pks", "resourceQuota", "spec.hard.requests.storageGi")))

    # - Role
    $logHistory.addLine("Adding Role...")
    $tkgiKubectl.addClusterNamespaceRole($clusterName,
                                        $namespace,
                                        $nameGeneratorK8s.getRoleName($clusterName, $namespace))

    # - RoleBinding
    $logHistory.addLine("Adding RoleBinding...")
    
    # Ajout des droits pour chaque groupe "groups" se trouvant dans le groupe AD utilisé pour les accès au BG dans vRA
    $adGroupList | ForEach-Object {
        $logHistory.addLine(("> For group '{0}'" -f $_))
        $tkgiKubectl.addClusterNamespaceRoleBinding($clusterName, 
                                                    $namespace,
                                                    $nameGeneratorK8s.getRoleName($clusterName, $namespace), 
                                                    $nameGeneratorK8s.getRoleBindingName($clusterName, $namespace), 
                                                    $_)
    }
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie les groupes d'accès à utiliser pour donner les droits sur un cluster

    IN  : $vra          -> Objet permettant d'accéder à vRA
    IN  : $bg           -> Objet représentant le Business Group auquel le cluster est lié
    IN  : $targetTenant -> Tenant sur lequel se trouve le BusinessGroup

    RET : Tableau avec la liste des groupes d'accès à utiliser
#>
function getBGAccessGroupList([vRAAPI]$vra, [PSObject]$bg, [string]$targetTenant)
{
    if($null -eq $bg)
    {
        Throw "Business Group cannot be NULL"
    }
    <# On explose l'infos <group>@intranet.epfl.ch pour n'extraire que le nom du groupe
        Récupération des utilisateurs qui ont le droit de demander des cluster, ça sera ceux
        qui pourront gérer le cluster #>
    $userAndGroupList = $vra.getBGRoleContent($bg.id, "CSP_CONSUMER")
    $groupName, $null = $userAndGroupList[0] -split '@'

    # Si on est dans le tenant ITS
    if($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
    {
        # Récupération de la liste des groupes qui sont présents dans le 1er groupe qui est dans les CONSUMER du BusinessGroup
        # NOTE: On fait ceci car TKGI/Harbor ne gèrent pas les groupes nested... 
        # FIXME: A supprimer une fois que TKGI/Harbor pourra gérer le groupes nested
        $accessGroupList = Get-ADGroupMember $groupName | Where-Object { $_.objectClass -eq "group"} | Select-Object -ExpandProperty name

        if($null -eq $accessGroupList)
        {
            Throw ("AD group '{0}' doesn't exists or is empty" -f $groupName)
        }
    }
    else # Autres tenants
    {
        # On prent le groupe tel quel
        $accessGroupList = @($groupName)
    }

    return $accessGroupList
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie la liste des namespaces d'un cluster

    IN  : $clusterName      -> Nom du cluster
    IN  : $returnOnlyNames  -> Pour dire si on doit retourner uniquement les noms ou la totale
    IN  : $tkgikubectl      -> Objet permettant d'effectuer des actions via les commandes
                                tkgi.exe et kubectl.exe
    
    RET : Tableau avec la liste des namespaces
#>
function getClusterNamespaceList([string]$clusterName, [bool]$returnOnlyNames, [TKGIKubectl]$tkgiKubectl)
{
    # Filtre pour ne pas renvoyer certains namespaces "system"
    $ignoreFilterRegex = "(kube|nsx|pks)-.*"

    $list = $tkgiKubectl.getClusterNamespaceList($clusterName)  | `
                Where-Object { $_.metadata.name -notmatch $ignoreFilterRegex }
    
    # Si on doit retourner uniquement les noms, on extrait ceux-ci
    if($returnOnlyNames)
    {
        $list = $list | Select-Object -ExpandProperty metadata | Select-Object -ExpandProperty name
    }

    return @($list)
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie le resource quota d'un namespace de cluster

    IN  : $clusterName      -> Nom du cluster
    IN  : $namespace        -> Nom du namespace
    IN  : $tkgikubectl      -> Objet permettant d'effectuer des actions via les commandes
                                tkgi.exe et kubectl.exe
    IN  : $logHistory       -> Objet pour avoir un fichier Log de l'exécution
    
    RET : Objet avec les détails du resource quota
#>
function getClusterNamespaceResourceQuota([string]$clusterName, [string]$namespace, [TKGIKubectl]$tkgiKubectl, [LogHistory]$logHistory)
{
    $logHistory.addLine(("Getting ResourceQuota for cluster '{0}' and namespace '{1}'..." -f $clusterName, $namespace))
    # On commence par récupérer les infos sur le stockage existant
    $resourceQuota = $tkgiKubectl.getClusterNamespaceResourceQuota($clusterName, $namespace)

    # Si pas trouvé 
    if($null -eq $resourceQuota)
    {
        Throw ("No ResourceQuota found for cluster '{0}' and namespace '{1}'" -f $clusterName, $namespace)
    }

    $logHistory.addLine(("ResourceQuota is '{0}'" -f $resourceQuota.metadata.name))

    <# Mise à jour de certaines valeurs pour qu'elles soient utilisables par la suite sans faire de mic-mac.
        Pour faire ceci, il faut supprimer et ajouter à nouveau la propriété contenant les valeurs... pourquoi?
        bah parce que pas trouvé comment mettre à jour sa valeur autrement ... 😑
    #>
    $currentSizeGB = [int](($resourceQuota.spec.hard | Select-Object -ExpandProperty requests.storage).replace("Gi", ""))
    $resourceQuota.spec.hard.PSObject.Properties.Remove('requests.storage')
    $resourceQuota.spec.hard | Add-Member -NotePropertyName requests.storage -NotePropertyValue $currentSizeGB -TypeName int

    # On transforme certaines valeurs en entiers
    @("services.loadbalancers", "services.nodeports") | ForEach-Object {
        $val = [int](($resourceQuota.spec.hard | Select-Object -ExpandProperty $_))
        $resourceQuota.spec.hard.PSObject.Properties.Remove($_)
        $resourceQuota.spec.hard | Add-Member -NotePropertyName $_ -NotePropertyValue $val -TypeName int
    }

    return $resourceQuota
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-k8s', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
    $nameGeneratorK8s = [NameGeneratorK8s]::new($targetEnv, $targetTenant)

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
						 $targetTenant, 
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
                         $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))
    
    # Création d'une connexion au serveur PKS pour accéder à ses API REST
	$pks = [PKSAPI]::new($configK8s.getConfigValue(@($targetEnv, "pks", "server")),
                            $configK8s.getConfigValue(@($targetEnv, "pks", "user")),
                            $configK8s.getConfigValue(@($targetEnv, "pks", "password")))

    # Création d'une connexion au serveur Harbor pour accéder à ses API REST
	$harbor = [HarborAPI]::new($configK8s.getConfigValue(@($targetEnv, "harbor", "server")),
            $configK8s.getConfigValue(@($targetEnv, "harbor", "user")),
            $configK8s.getConfigValue(@($targetEnv, "harbor", "password")))

    # Connexion à NSX pour pouvoir allouer/restituer des adresses IP
    $nsx = [NSXAPI]::new($configNSX.getConfigValue(@($targetEnv, "server")),
                            $configNSX.getConfigValue(@($targetEnv, "user")),
                            $configNSX.getConfigValue(@($targetEnv, "password")))

    # Création du nécessaire pour interagir avec le DNS EPFL
	$EPFLDNS = [EPFLDNS]::new($configK8s.getConfigValue(@($targetEnv, "dns", "server")),
                                $configK8s.getConfigValue(@($targetEnv, "dns", "psEndpointServer")),
                                $configK8s.getConfigValue(@($targetEnv, "dns", "user")),
                                $configK8s.getConfigValue(@($targetEnv, "dns", "password")))

    # Objet pour passer des commandes TKGI et Kubectl
    $tkgiKubectl = [TKGIKubectl]::new($configK8s.getConfigValue(@($targetEnv, "tkgi", "server")),
                                        $configK8s.getConfigValue(@($targetEnv, "tkgi", "user")),
                                        $configK8s.getConfigValue(@($targetEnv, "tkgi", "password")),
                                        $configK8s.getConfigValue(@($targetEnv, "tkgi", "certificate")))
    
    # Chargement des informations sur le nombre de Workers pour les plans
    $resourceQuotaLimitsFile = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "k8s", "resource-quota-limits.json"))
    $resourceQuotaLimits = loadFromCommentedJSON -jsonFile $resourceQuotaLimitsFile                                        

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $vra.activateDebug($logHistory)
        $pks.activateDebug($logHistory)
        $harbor.activateDebug($logHistory)
        $tkgiKubectl.activateDebug($logHistory)
    }
    
    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                        ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

    # Si on nous a passé un ID de BG,
    if($bgId -ne "")
    {
        $logHistory.addLine(("Business group ID given ({0}), looking for object in vRA..." -f $bgId))
        # Récupération de l'objet représentant le BG dans vRA
        $bg = $vra.getBGByCustomId($bgId)

        # On check si pas trouvé (on ne sait jamais...)
        if($null -eq $bg)
        {
            Throw ("Business Group with ID '{0}' not found on {1} tenant" -f $bgId, $targetTenant)
        }
        $logHistory.addLine(("Business Group found, name={0}" -f $bg.name))

        # Initialisation pour récupérer les noms des éléments
        $nameGeneratorK8s.initDetailsFromBG($bg.name, $bgId)
    }

    # On efface le cache DNS pour ne pas avoir de surprise par la suite
    Clear-DnsClientCache

    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {
        <#
        ----------------------------------
        ------------- CLUSTER ------------
        #>

        # --- Nouveau
        $ACTION_CREATE
        {
            # Pour dire si on peut effectuer du cleaning dans le cas d'une erreur
            $cleaningCanBeDoneIfError = $true
            
            # Extraction des plans disponibles
            $allowedPlans = $resourceQuotaLimits.nbWorkers | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name

            # On contrôle que la valeur de "plan" soit OK
            if($allowedPlans -notcontains $plan)
            {
                Throw ("Incorrect plan given ({0}). Possible values are: {1}" -f $plan, ($allowedPlans -join ", "))
            }

            $logHistory.addLine("Generating cluster name...")
            # Recherche du nom du nouveau cluster
            $clusterName = getNextClusterName -pks $pks -nameGeneratorK8s $nameGeneratorK8s
            $logHistory.addLine(("Cluster name will be '{0}'" -f $clusterName))

            # -------------------
            # ---- Droits d'accès 
            # Ajout des droits d'accès mais uniquement pour le premier groupe de la liste, et on admet que c'est un nom de groupe et pas
            # d'utilisateur. 
            $accessGroupList = getBGAccessGroupList -vra $vra -bg $bg -targetTenant $targetTenant

            # Histoire d'avoir ceinture et bretelles, on check quand même que le cluster n'existe pas. 
            # On ne devrait JAMAIS arriver dans ce cas de figure mais on le code tout de même afin d'éviter de
            # passer dans le code de "nettoyage" en bas du script
            if($null -ne $pks.getCluster($clusterName))
            {
                $cleaningCanBeDoneIfError = $false
                Throw ("Error while generating cluster name. Choosen one ({0}) already exists!" -f $clusterName)
            }

            # Génération des noms pour le DNS
            $logHistory.addLine("Generating DNS hostnames...")
            $dnsHostName = $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryMain)
            $dnsHostNameFull = ("{0}.{1}" -f $dnsHostName, $global:K8S_DNS_ZONE_NAME)
            $dnsHostNameIngress = $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryIngress)
            $logHistory.addLine(("DNS hosnames will be '{0}' for main cluster and '{1}' for Ingress part" -f $dnsHostName, $dnsHostNameIngress))

            $logHistory.addLine(("Creating cluster '{0}' with '{1}' plan and '{2}' network profile (this will take time, you can go to grab a coffee)..." -f $clusterName, $plan, $netProfile))
            $cluster = $pks.addCluster($clusterName, $plan, $netProfile, $dnsHostNameFull)

            if($null -eq $cluster)
            {
                Throw ("Unknown error while creating cluster '{0}'" -f $clusterName)
            }

            # -----------
            # ---- Réseau
            $ipMain = $cluster.kubernetes_master_ips[0]
            $logHistory.addLine(("IP address for cluster is {0}. Looking for Ingress IP..." -f $ipMain))
            $ipIngress = searchClusterIngressIPAddress -clusterIP $ipMain -nsx $nsx

            if($null -eq $ipIngress)
            {
                Throw "Impossible to find IP address for Ingress part"
            }
            $logHistory.addLine(("Ingress IP address is {0}" -f $ipIngress))
            
            $logHistory.addLine(("Adding DNS entries in {0} zone..." -f $global:K8S_DNS_ZONE_NAME))
            $EPFLDNS.registerDNSIP($dnsHostName, $ipMain, $global:K8S_DNS_ZONE_NAME)
            $EPFLDNS.registerDNSIP($dnsHostNameIngress, $ipIngress, $global:K8S_DNS_ZONE_NAME)

            # - Storage Class
            $logHistory.addLine("Adding StorageClass...")
            $tkgiKubectl.addClusterStorageClass($clusterName, 
                                                $nameGeneratorK8s.getStorageClassName($clusterName), 
                                                $configK8s.getConfigValue(@($targetEnv, "pks", "storageClass", "provisioner")), 
                                                $configK8s.getConfigValue(@($targetEnv, "pks", "storageClass", "parameters.datastore")))
            
            # Configuration du NameSpace par défaut
            configureNamespaceElements -clusterName $clusterName -namespace $global:DEFAULT_NAMESPACE -targetEnv $targetEnv `
                                       -adGroupList $accessGroupList -nameGeneratorK8s $nameGeneratorK8s -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            # - Pod Security Policy
            $logHistory.addLine("Adding PodSecurityPolicy...")
            $tkgiKubectl.addClusterPodSecurityPolicy($clusterName,
                                                     $nameGeneratorK8s.getPodSecurityPolicyName($clusterName),
                                                     $global:PSP_PRIVILEGED,
                                                     $global:PSP_ALLOW_PRIVILEGE_ESCALATION)

            # - Cluster Role
            $logHistory.addLine("Adding ClusterRole...")
            $tkgiKubectl.addClusterRole($clusterName, 
                                        $nameGeneratorK8s.getClusterRoleName($clusterName),
                                        $nameGeneratorK8s.getPodSecurityPolicyName($clusterName))

            # - Cluster Role Binding
            $logHistory.addLine("Adding ClusterRoleBinding...")
            # Ajout des droits pour chaque groupe "groups" se trouvant dans le groupe AD utilisé pour les accès au BG dans vRA
            $accessGroupList | ForEach-Object {
                $logHistory.addLine(("> For group '{0}'" -f $_))
                
                $tkgiKubectl.addClusterRoleBinding($clusterName, 
                                                   $nameGeneratorK8s.getClusterRoleName($clusterName), 
                                                   $nameGeneratorK8s.getClusterRoleBindingName($clusterName), 
                                                   $_)
            }


            # -----------
            # ---- Harbor
            $harborProjectName = $nameGeneratorK8s.getHarborProjectName()
            $logHistory.addLine(("Harbor project will be '{0}'" -f $harborProjectName))
            
            $harborProject = $harbor.getProject($harborProjectName)
            # Si le projet n'existe pas
            if($null -eq $harborProject)
            {
                $logHistory.addLine(("Project '{0}' doesn't exists in Harbor, creating it..." -f $harborProjectName))
                $harborProject = $harbor.addProject($harborProjectName)                
            }
            else
            {
                $logHistory.addLine(("Project '{0}' already exists in Harbor" -f $harborProjectName))
            }

            Write-Warning "Add Harbor group access"
            # $logHistory.addLine("Adding AD groups for Harbor Project access...")
            # $accessGroupList | ForEach-Object {
            #     $logHistory.addLine(("Add group '{0}' in Harbor Project (may already be present)" -f $_))
            #     $harbor.addProjectMember($harborProject, $_, [HarborProjectRole]::Master)
            # }
            
            
            $logHistory.addLine(("Adding temporary robot in Harbor Project '{0}'" -f $harborProjectName))
            # Récupération des informations sur le robot (nom, description, temps unix de fin de validité)
            $robotInfos = $nameGeneratorK8s.getHarborRobotAccountInfos($ROBOT_NB_DAYS_LIFETIME)
            $robot = $harbor.addTempProjectRobotAccount($harborProject, $robotInfos.name, $robotInfos.desc, $robotInfos.expireAt)

            # Résultat
            $output.results += @{
                name = $clusterName
                uuid = $cluster.uuid
                dnsHostName = $dnsHostNameFull
                harbor = @{
                    project = $harborProjectName
                    robot = @{
                        name = $robot.name
                        token = $robot.token
                        validityDays = $ROBOT_NB_DAYS_LIFETIME
                    }
                }
            }
        }# FIN CASE ajout cluster


        # --- Effacer
        $ACTION_DELETE
        {
            deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -clusterName $clusterName -clusterUUID $clusterUUID `
                        -harbor $harbor -ipPoolName $configK8s.getConfigValue(@($targetEnv, "nsx", "ipPoolName")) -targetTenant $targetTenant
        }


        # --- Détails d'un cluster
        $ACTION_GET_CLUSTER_INFOS
        {
            $cluster = $pks.getCluster($clusterName)

            if($null -eq $cluster)
            {
                Throw ("Cluster '{0}' doesn't exists" -f $clusterName)
            }

            # Liste des Namespace du cluster
            $namespaceList = getClusterNamespaceList -tkgiKubectl $tkgiKubectl -clusterName $clusterName -returnOnlyNames $false

            $namespaces = @()
            # Parcours des Namespaces du cluster
            ForEach($namespaceInfos in $namespaceList)
            {
                # Récupération du resourceQuota du namespace du cluster
                $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespaceInfos.metadata.name -tkgiKubectl $tkgiKubectl -logHistory $logHistory
                
                $namespaces += @{ 
                    name = $namespaceInfos.metadata.name
                    infos = $namespaceInfos
                    resourceQuota = $resourceQuota
                }
            }

            $output.results += @{
                cluster = $cluster
                namespaces = $namespaces
            }
        }

        <#
        --------------------------------------
        --------------- WORKERS --------------
        #>

        # -- Renvoyer le nombre de workers
        $ACTION_GET_NB_WORKERS
        {
            $logHistory.addLine(("Getting Cluster '{0}'..." -f $clusterName))
            $cluster = $pks.getCluster($clusterName)

            if($null -eq $cluster)
            {
                Throw ("Cluster '{0}' doesn't exists" -f $clusterName)
            }

            $output.results += @{
                clusterName = $clusterName
                nbWorkers = @{
                    current = $cluster.parameters.kubernetes_worker_instances
                    # On ajoute aussi les informations sur les valeurs min et max
                    min = $resourceQuotaLimits.nbWorkers.($cluster.plan_name).min
                    max = $resourceQuotaLimits.nbWorkers.($cluster.plan_name).max
                }
            }
        }


        # -- Initialiser le nombre de Workers
        $ACTION_SET_NB_WORKERS
        {
            $logHistory.addLine(("Getting Cluster '{0}'..." -f $clusterName))
            $cluster = $pks.getCluster($clusterName)

            if($null -eq $cluster)
            {
                Throw ("Cluster '{0}' doesn't exists" -f $clusterName)
            }

            # On contrôle si le nombre de workers demandés est incorrect par rapport à ce qui est défini dans le plan
            if($nbWorkers -lt $resourceQuotaLimits.nbWorkers.($cluster.plan_name).min -or `
                $nbWorkers -gt $resourceQuotaLimits.nbWorkers.($cluster.plan_name).max)
            {
                Throw ("Incorrect workers number ({0}). With cluster plan '{1}', only {2} to {3} workers are allowed ({4} workers are currently configured)" -f `
                        $nbWorkers, $cluster.plan_name, $resourceQuotaLimits.nbWorkers.($cluster.plan_name).min, 
                        $resourceQuotaLimits.nbWorkers.($cluster.plan_name).max, $cluster.parameters.kubernetes_worker_instances)
            }

            $res = @{
                clusterName = $clusterName
                oldNbWorkers = $cluster.parameters.kubernetes_worker_instances
                newNbWorkers = $nbWorkers
            }

            $logHistory.addLine(("Cluster '{0}' currently have {1} worker(s). New value will be: {2} workers. Updating..." -f `
                                 $clusterName, $cluster.parameters.kubernetes_worker_instances, $nbWorkers))

            # Mise à jour du cluster
            $logHistory.addLine(("Modifying cluster '{0}' to update nb workers from {1} to {2}" -f `
                                 $clusterName, $cluster.parameters.kubernetes_worker_instances, $nbWorkers))
            $pks.updateCluster($clusterName, $nbWorkers)

            $output.results += $res

        }


        <#
        ----------------------------------
        ------------ NAMESPACE -----------
        #>

        # -- Nouveau namespace
        $ACTION_ADD_NAMESPACE
        {
            $logHistory.addLine(("Getting existing namespaces for cluster '{0}'..." -f $clusterName))
            $namespaceList = getClusterNamespaceList -tkgiKubectl $tkgiKubectl -clusterName $clusterName -returnOnlyNames $true
            $logHistory.addLine(("Found {0} namespaces:`n- {0}" -f $namespaceList.count, ($namespaceList -join "`n- ")))

            # On regarde si le namespace à crée existe déjà
            if($namespaceList -contains $namespace)
            {
                Throw "Namespace '{0}' already exists in cluster '{1}'" -f $namespace, $clusterName
            }

            # Ajout du nouveau namespace
            $logHistory.addLine(("Adding namespace '{0}' to cluster '{1}'..." -f $namespace, $clusterName))
            $tkgiKubectl.addClusterNamespace($clusterName, $namespace, $targetEnv)

            $logHistory.addLine(("Getting access group list for Business Group '{0}'..." -f $bg.name))
            $accessGroupList = getBGAccessGroupList -vra $vra -bg $bg -targetTenant $targetTenant
            $logHistory.addLine(("Group list will be: {0}" -f ($accessGroupList -join ", ")))

            try
            {
                $logHistory.addLine("Configuring namespace...")
                configureNamespaceElements -clusterName $clusterName -namespace $global:DEFAULT_NAMESPACE -targetEnv $targetEnv `
                                       -adGroupList $accessGroupList -nameGeneratorK8s $nameGeneratorK8s -tkgiKubectl $tkgiKubectl -logHistory $logHistory
            }
            catch
            {
                $logHistory.addLine(("Error while configuring namespace '{0}', deleting it..." -f $namespace))
                $tkgiKubectl.deleteClusterNamespace($clusterName, $namespace)

                # On continue à propager l'exception
                Throw
            }
            
        }


        # -- Liste des namespaces
        $ACTION_GET_NAMESPACE_LIST
        {
            $logHistory.addLine(("Getting namespace list for cluster '{0}'" -f $clusterName))
            $output.results = getClusterNamespaceList -tkgiKubectl $tkgiKubectl -clusterName $clusterName -returnOnlyNames $true

        }


        # -- Effacer un namespace
        $ACTION_DELETE_NAMESPACE
        {
            $logHistory.addLine(("Getting namespace list for cluster '{0}'" -f $clusterName))
            $namespaceList = getClusterNamespaceList -tkgiKubectl $tkgiKubectl -clusterName $clusterName -returnOnlyNames $true

            # Si le namespace n'existe pas
            if($namespaceList -notcontains $namespace)
            {
                Throw "Namespace '{0}' doesn't exists in cluster '{1}'" -f $namespace, $clusterName
            }

            $logHistory.addLine(("Deleting namespace '{0}' from cluster '{1}'" -f $namespace, $clusterName))
            $tkgiKubectl.deleteClusterNamespace($clusterName, $namespace)

        }


        # -- Resources pour le namespace
        $ACTION_GET_NAMESPACE_RESOURCES
        {
            # Récupération du resourceQuota du namespace du cluster
            $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespace -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            # Ajout du résultat
            $output.results += @{
                clusterName = $clusterName
                namespace = $namespace
                storageGB = $resourceQuota.spec.hard | Select-Object -ExpandProperty requests.storage
                nbLoadBalancers = $resourceQuota.spec.hard | Select-Object -ExpandProperty services.loadbalancers
                nbNodePorts = $resourceQuota.spec.hard | Select-Object -ExpandProperty services.nodeports
            }
        }


        <#
        ----------------------------------
        ---------- LOAD BALANCER ---------
        #>

        # -- Nouveau Load Balancer
        $ACTION_ADD_LOAD_BALANCER
        {
            # Récupération du resourceQuota du namespace du cluster
            $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespace -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            # Récupération du nombre de load balancers actuel
            $currentNBLB = $resourceQuota.spec.hard | Select-Object -ExpandProperty services.loadbalancers

            # Si on est déjà au max
            if($currentNBLB -ge $resourceQuotaLimits.nbLoadBalancers)
            {
                Throw ("Maximum LoadBalancers already reached ({0})" -f $resourceQuotaLimits.nbLoadBalancers)
            }

            # Récupération de la taille en virant l'unité (ex. 10Gi -> 10) et du coup on transforme en entier aussi
            $currentSizeGB = $resourceQuota.spec.hard | Select-Object -ExpandProperty requests.storage

            $logHistory.addLine("Adding 1 LoadBalancer to ResourceQuota")
            $tkgiKubectl.addOrUpdateClusterNamespaceResourceQuota($clusterName, $namespace, $resourceQuota.metadata.name,`
                $currentNBLB+1, $currentNBLB+1, $currentSizeGB)
            
            # Ajout du résultat
            $output.results += @{
                clusterName = $clusterName
                namespace = $namespace
                nbLoadBalancers = @{
                    old = $currentNBLB
                    new = $currentNBLB+1
                }
            }
        }


        # -- Nombre de Load Balancers
        $ACTION_GET_NB_LOAD_BALANCER
        {
            # Récupération du resourceQuota du namespace du cluster
            $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespace -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            $output.results += @{
                clusterName = $clusterName
                namespace = $namespace
                nbLoadBalancers = ($resourceQuota.spec.hard | Select-Object -ExpandProperty services.loadbalancers)
            }
        }


        # -- Effacement d'un Load Balancer
        $ACTION_DELETE_LOAD_BALANCER
        {
            # Récupération du resourceQuota du namespace du cluster
            $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespace -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            # Récupération du nombre de load balancers actuel
            $currentNBLB = $resourceQuota.spec.hard | Select-Object -ExpandProperty services.loadbalancers

            # Si on est déjà au min
            if($currentNBLB -eq 0)
            {
                Throw "No LoadBalancer defined, impossible to delete one"
            }

            # Récupération de la taille en virant l'unité (ex. 10Gi -> 10) et du coup on transforme en entier aussi
            $currentSizeGB = $resourceQuota.spec.hard | Select-Object -ExpandProperty requests.storage

            $logHistory.addLine("Adding 1 LoadBalancer to ResourceQuota")
            $tkgiKubectl.addOrUpdateClusterNamespaceResourceQuota($clusterName, $namespace, $resourceQuota.metadata.name,`
                $currentNBLB-1, $currentNBLB-1, $currentSizeGB)
            
            # Ajout du résultat
            $output.results += @{
                clusterName = $clusterName
                namespace = $namespace
                nbLoadBalancers = @{
                    old = $currentNBLB
                    new = $currentNBLB-1
                }
            }
        }


        <#
        ----------------------------------
        ------------- STORAGE ------------
        #>

        # -- Extension du stockage
        $ACTION_EXTEND_NAMESPACE_STORAGE
        {
            # Récupération du resourceQuota du namespace du cluster
            $resourceQuota = getClusterNamespaceResourceQuota -clusterName $clusterName -namespace $namespace -tkgiKubectl $tkgiKubectl -logHistory $logHistory

            # Récupération de la taille en virant l'unité (ex. 10Gi -> 10) et du coup on transforme en entier aussi
            $currentSizeGB = $resourceQuota.spec.hard | Select-Object -ExpandProperty requests.storage
            $newSizeGB = $currentSizeGB + $extSizeGB

            $logHistory.addLine(("Adding {0}GB to ResourceQuota storage. Old: {1}GB, New:{2}GB" -f $extSizeGB, $currentSizeGB, $newSizeGB))
            $tkgiKubectl.addOrUpdateClusterNamespaceResourceQuota($clusterName, $namespace, $resourceQuota.metadata.name,`
                # On accède avec Select-Object car le nom des propriétés contient un "."... on ne peut donc pas y accéder 
                # via ".<property>" ou via ".(<property>)"
                ($resourceQuota.spec.hard | Select-Object -ExpandProperty services.loadbalancers), `
                ($resourceQuota.spec.hard | Select-Object -ExpandProperty services.nodeports), `
                # Mise à jour de la taille
                $newSizeGB)
            
            # Ajout du résultat
            $output.results += @{
                clusterName = $clusterName
                namespace = $namespace
                storageGB = @{
                    old = $currentSizeGB
                    new = $newSizeGB
                }
            }
        }


        <#
        ----------------------------------
        -------------- ROBOT -------------
        #>

        # -- Nouveau robot
        $ACTION_ADD_ROBOT
        {

            $harborProjectName = $nameGeneratorK8s.getHarborProjectName()
            $logHistory.addLine(("Harbor project name is '{0}'" -f $harborProjectName))
            
            $harborProject = $harbor.getProject($harborProjectName)

            # Ajout du compte temporaire
            $logHistory.addLine(("Adding temporary robots to project"))
            # Récupération des informations sur le robot (nom, description, temps unix de fin de validité)
            $robotInfos = $nameGeneratorK8s.getHarborRobotAccountInfos($ROBOT_NB_DAYS_LIFETIME)
            $robot = $harbor.addTempProjectRobotAccount($harborProject, $robotInfos.name, $robotInfos.desc, $robotInfos.expireAt)

            # Résultat
            $output.results += @{
                name = $robot.name
                token = $robot.token
                validityDays = $ROBOT_NB_DAYS_LIFETIME
            }
        }
    }

    $logHistory.addLine("Script execution done!")

    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

}
catch
{
    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace
    
    # Si on était en train de créer un cluster et qu'on peut effectivement faire du ménage
    if(($action -eq $ACTION_CREATE) -and $cleaningCanBeDoneIfError)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating cluster '{0}', deleting it so everything is clean:`n{1}`nStack Trace:`n{2}" -f $clusterName, $errorMessage, $errorTrace))
        deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -harbor $harbor `
                -clusterName $clusterName -clusterUUID "" -ipPoolName $configK8s.getConfigValue(@($targetEnv, "nsx", "ipPoolName")) -targetTenant $targetTenant
    }

    # Reset des infos s'il y en avait, ajout de l'erreur et affichage
    $output = getObjectForOutput
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }

    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace) 
}

$vra.disconnect()
