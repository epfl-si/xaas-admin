<#
USAGES:
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action create -bgName <bgName> -plan <plan> -netProfile <netProfile>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delete -bgName <bgName> -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action setNbWorkers -clusterName <clusterName> -nbWorkers <nbWorkers>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getWorkersInfos -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newNamespace -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getNamespaceList -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delNamespace -clusterName <clusterName> -namespace <namespace>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newLB -clusterName <clusterName> -lbName <lbName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getLBList -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delLB -clusterName <clusterName> -lbName <lbName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action newStorage -clusterName <clusterName>
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
      [string]$bgName,
      [string]$plan,
      [int]$nbWorkers,
      [string]$netProfile,
      [string]$clusterName,
      [string]$namespace,
      [string]$lbName)


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
$ACTION_CREATE                  = "create"
$ACTION_DELETE                  = "delete"
$ACTION_GET_WORKERS_INFOS       = "getWorkersInfos"
$ACTION_SET_NB_WORKERS          = "setNbWorkers"
$ACTION_NEW_NAMESPACE           = "newNamespace"
$ACTION_GET_NAMESPACE_LIST      = "getNamespaceList"
$ACTION_DELETE_NAMESPACE        = "delNamespace"
$ACTION_NEW_LOAD_BALANCER       = "newLB"
$ACTION_GET_LOAD_BALANCER_LIST  = "getLBList"
$ACTION_DELETE_LOAD_BALANCER    = "delLB"
$ACTION_NEW_STORAGE             = "newStorage"



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
    IN  : $ipPoolName       -> Nom du pool IP dans NSX
    IN  : $targetTenant     -> Tenant cible
#>
function deleteCluster([PKSAPI]$pks, [NSXAPI]$nsx, [EPFLDNS]$EPFLDNS, [NameGeneratorK8s]$nameGeneratorK8s, [HarborAPI]$harbor, [string]$clusterName, [string]$ipPoolName, [string]$targetTenant)
{
    # Le nom du cluster peut être encore vide dans le cas où une erreur surviendrait avait que le nom soit initialisé. 
    # Dans ce cas, on ne fait rien
    if($clusterName -eq "")
    {
        $logHistory.addLine("Cluster to delete has empty name, maybe it wasn't initialized before and error occured and the this 'delete' function was called.")
        return
    }

    # ------------
    # ---- Cluster
    $cluster = $pks.getCluster($clusterName)
    if($null -ne $cluster)
    {
        $logHistory.addLine(("Deleting cluster '{0}'. This also can take a while... so... another coffee ?..." -f $clusterName))
        # On attend que le cluster ait été effacé avant de rendre la main et passer à la suite du job
        $pks.deleteCluster($clusterName)
        $logHistory.addLine("Cluster deleted")
    }
    else
    {
        $logHistory.addLine(("Cluster '{0}' doesn't exists" -f $clusterName))
    }
    

    # -----------
    # ---- Réseau
    # Recherche du pool dans lequel on va demander les adresses IP
    $pool = $nsx.getIPPoolByName($ipPoolName)
    $hostnameList = @(
        # On efface d'abord l'entrée 'ingress' car elle a été créé en dernier
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryIngress)    
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryMain)
    )
    
    $logHistory.addLine("Deleting IPs...")
    # On commence par nettoyer le cache local pour être sûr de bien interroger le DNS et pas le cache... 
    Clear-DnsClientCache 
    ForEach($hostname in $hostnameList)
    {
        try
        {
            # Si l'entrée n'existe pas dans le DNS, ça va générer une exception
            $ip = ([System.Net.Dns]::GetHostAddresses( ("{0}.{1}" -f $hostname, $global:K8S_DNS_ZONE_NAME))).IPAddressToString   
        }
        catch
        {
            # Pas trouvé, on passe au hostname suivant
            $logHistory.addLine(("> IP doesn't exists in DNS"))
            Continue
        }
        
        $logHistory.addLine(("> IP {0} and host '{1}'" -f $ip, $hostname))
        $logHistory.addLine("> Unregistering IP for host in DNS...")
        $EPFLDNS.unregisterDNSIP($hostname, $ip, $global:K8S_DNS_ZONE_NAME)

        # Si l'IP est allouée dans NSX,
        if($nsx.isIPAllocated($pool.id, $ip))
        {
            $logHistory.addLine("> Releasing IP in NSX (it will take some time before it is available again in pool)...")
            $nsx.releaseIPAddressInPool($pool.id, $ip)
        }
        else
        {
            $logHistory.addLine("> IP is not allocated in NSX")
        }
        
    }# FIN BOUCLE de parcours des IP à supprimer

    # --------
    # ---- NSX
    # Si on avait pu trouver le cluster
    if($null -ne $cluster)
    {
        $logHistory.addLine("Deleting Load Balancer application profiles...")
        $appProfileList = $nsx.getClusterLBAppProfileList($cluster.uuid)

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

    # ------------------
    # ---- Projet Harbor
    $harborProjectName = $nameGeneratorK8s.getHarborProjectName()
    $logHistory.addLine(("Cleaning Harbor project ({0}) if needed..." -f $harborProjectName))
    
    if($targetTenant -eq $global:VRA_TENANT__EPFL)
    {
        <# Rien besoin de faire pour ce tenant car il y a un projet Harbor par faculté donc on n'a pas besoin 
            de supprimer quoi que ce soit. On pourrait supprimer le groupe AD correspondant au BG mais il n'est 
            pertinent de supprimer ce groupe d'accès uniquement si on vient de supprimer le tout dernier cluster
            pour le Business Group #>
        $logHistory.addLine("> We're on EPFL tenant, one project per Faculty so no cleaning")
    }
    else # Tenant ITServices ou Research
    {
        $harborProject = $harbor.getProject($harborProjectName)
        if($null -ne $harborProject)
        {
            # On a un Projet Harbor par service donc on peut faire du ménage d'office
            $logHistory.addLine(("> Removing Project '{0}'..." -f $harborProjectName))
            $harbor.deleteProject($harborProjectName)
        }
        else # Le projet n'existe pas
        {
            $logHistory.addLine(("> Project '{0}' doesn't exists" -f $harborProjectName))
        }
    }
    
    
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
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "infra", "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "user"), 
                         $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "password"))
    
    # Création d'une connexion au serveur PKS pour accéder à ses API REST
	$pks = [PKSAPI]::new($configK8s.getConfigValue($targetEnv, "pks", "server"), 
                            $configK8s.getConfigValue($targetEnv, "pks", "user"), 
                            $configK8s.getConfigValue($targetEnv, "pks", "password"))

    # Création d'une connexion au serveur Harbor pour accéder à ses API REST
	$harbor = [HarborAPI]::new($configK8s.getConfigValue($targetEnv, "harbor", "server"), 
            $configK8s.getConfigValue($targetEnv, "harbor", "user"), 
            $configK8s.getConfigValue($targetEnv, "harbor", "password"))

    # Connexion à NSX pour pouvoir allouer/restituer des adresses IP
    $nsx = [NSXAPI]::new($configNSX.getConfigValue($targetEnv, "server"), `
                            $configNSX.getConfigValue($targetEnv, "user"), `
                            $configNSX.getConfigValue($targetEnv, "password"))

    # Création du nécessaire pour interagir avec le DNS EPFL
	$EPFLDNS = [EPFLDNS]::new($configK8s.getConfigValue($targetEnv, "dns", "server"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "psEndpointServer"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "user"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "password"))

    # Objet pour passer des commandes TKGI et Kubectl
    $tkgiKubectl = [TKGIKubectl]::new($configK8s.getConfigValue($targetEnv, "tkgi", "server"), 
                                        $configK8s.getConfigValue($targetEnv, "tkgi", "user"), 
                                        $configK8s.getConfigValue($targetEnv, "tkgi", "password"),
                                        $configK8s.getConfigValue($targetEnv, "tkgi", "certificate"))
                                
    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, `
                        ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

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
            # Initialisation pour récupérer les noms des éléments
            $nameGeneratorK8s.initDetailsFromBGName($bgName)

            # Recherche du Business Group
            $bg = $vra.getBG($bgName)
            # Récupération des utilisateurs qui ont le droit de demander des cluster, ça sera ceux
            # qui pourront gérer le cluster
            $userAndGroupList = $vra.getBGRoleContent($bg.id, "CSP_CONSUMER")

            $logHistory.addLine("Generating cluster name...")
            # Recherche du nom du nouveau cluster
            $clusterName = getNextClusterName -pks $pks -nameGeneratorK8s $nameGeneratorK8s
            $logHistory.addLine(("Cluster name will be '{0}'" -f $clusterName))

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

            # -------------------
            # ---- Droits d'accès 
            # Ajout des droits d'accès mais uniquement pour le premier groupe de la liste, et on admet que c'est un nom de groupe et pas
            # d'utilisateur. On explose l'infos <group>@intranet.epfl.ch pour n'extraire que le nom du groupe
            $groupName, $null = $userAndGroupList[0] -split '@'

            $logHistory.addLine(("Adding rights on cluster for '{0}' group..." -f $groupName))
            # Préparation des lignes de commande à exécuter
            $tkgiKubectl.addTkgiCmdWithPassword(("get-credentials {0}" -f $clusterName))
            $tkgiKubectl.addKubectlCmd(("config use-context {0}" -f $clusterName))
            $tkgiKubectl.addKubectlCmdWithYaml("psp-cluster-role.yaml")
            $tkgiKubectl.addKubectlCmdWithYaml("psp-restrict.yaml")
            $tkgiKubectl.addKubectlCmdWithYaml("cluster-role-bindings.yaml", @{ groupName = $groupName} )
            # Exécution
            $tkgiKubectl.exec() | Out-Null

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

            # # Si le groupe n'est pas encore dans le projet
            # if(! ($harbor.isMemberInProject($harborProject, $groupName)))
            # {
            #     $logHistory.addLine(("Add group '{0}' in Harbor Project" -f $groupName))
            #     $harbor.addProjectMember($harborProject, $groupName, [HarborProjectRole]::Master)
            # }
            # else # Le groupe est déjà dans le projet
            # {
            #     $logHistory.addLine(("Group '{0}' is already in Harbor project" -f $groupName))
            # }

            # Résultat
            $output.results += @{
                name = $clusterName
                uuid = $cluster.uuid
                dnsHostName = $dnsHostNameFull
            }
        }


        # --- Effacer
        $ACTION_DELETE
        {
            # Initialisation pour récupérer les noms des éléments
            $nameGeneratorK8s.initDetailsFromBGName($bgName)

            deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -clusterName $clusterName `
                        -harbor $harbor -ipPoolName $configK8s.getConfigValue($targetEnv, "nsx", "ipPoolName") -targetTenant $targetTenant
        }


        <#
        -------------------------------------
        --------------- WORKERS -------------
        #>

        # -- Infos sur les workeres
        $ACTION_GET_WORKERS_INFOS
        {

        }

        # -- Initialiser le nombre de Workers
        $ACTION_SET_NB_WORKERS
        {

        }


        <#
        ----------------------------------
        ------------ NAMESPACE -----------
        #>

        # -- Nouveau namespace
        $ACTION_NEW_NAMESPACE
        {

        }


        # -- Liste des namespaces
        $ACTION_GET_NAMESPACE_LIST
        {

        }


        # -- Effacer un namespace
        $ACTION_DELETE_NAMESPACE
        {

        }


        <#
        ----------------------------------
        ---------- LOAD BALANCER ---------
        #>

        # -- Nouveau Load Balancer
        $ACTION_NEW_LOAD_BALANCER
        {

        }


        # -- Liste des Load Balancer
        $ACTION_GET_LOAD_BALANCER_LIST
        {

        }


        # -- Effacement d'un Load Balancer
        $ACTION_DELETE_LOAD_BALANCER
        {

        }


        <#
        ----------------------------------
        ------------- STORAGE ------------
        #>

        # -- Nouveau stockag
        $ACTION_NEW_STORAGE
        {

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
    
    # Si on était en train de créer un cluster et qu'on peut effectivement faire du ménage
    if(($action -eq $ACTION_CREATE) -and $cleaningCanBeDoneIfError)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating cluster '{0}', deleting it so everything is clean" -f $clusterName))
        deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -harbor $harbor `
                -clusterName $clusterName -ipPoolName $ipPoolName -targetTenant $targetTenant
    }

	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
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
