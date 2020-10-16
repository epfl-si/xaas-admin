<#
USAGES:
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action create -bgName <bgName> -plan <plan> -netProfile <netProfile>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delete -clusterName <clusterName>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action changePlan -clusterName <clusterName> -plan <plan>
    xaas-k8s-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getPlan -clusterName <clusterName>
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
$ACTION_CHANGE_PLAN             = "changePlan"
$ACTION_GET_PLAN                = "getPlan"
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
    BUT : Efface un cluster

    IN  : $pks              -> Objet permettant d'accéder à l'API de PKS
    IN  : $nsx              -> Objet permettant d'accéder à l'API de NSX
    IN  : $EPFLDNS          -> Objet permettant de jouer avec le DNS
    IN  : $nameGeneratorK8s -> Objet pour la génération des noms
    IN  : $clusterName      -> Nom du cluster à supprimer
    IN  : $ipPoolName       -> Nom du pool IP dans NSX
#>
function deleteCluster([PKSAPI]$pks, [NSXAPI]$nsx, [EPFLDNS]$EPFLDNS, [NameGeneratorK8s]$nameGeneratorK8s, [string]$clusterName, [string]$ipPoolName)
{
    
    # - Cluster
    $cluster = $pks.getCluster($clusterName)
    if($null -ne $cluster)
    {
        $logHistory.addLine(("Deleting cluster '{0}'..." -f $clusterName))
        $pks.deleteCluster($clusterName)
    }
    else
    {
        $logHistory.addLine(("Cluster '{0}' doesn't exists" -f $clusterName))
    }


    # - Adresses IP
    # Recherche du pool dans lequel on va demander les adresses IP
    $pool = $nsx.getIPPoolByName($ipPoolName)
    $hostnameList = @(
        # On efface d'abord l'entrée 'ingress' car elle a été créé en dernier
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryIngress)    
        $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryMain)
    )
    $logHistory.addLine("Deleting IPs...")
    ForEach($hostname in $hostnameList)
    {
        $logHistory.addLine(("> IP {0} and host '{1}'" -f $ip, $hostname))
        try
        {
            # Si l'entrée n'existe pas dans le DNS, ça va générer une exception
            $ip = [System.Net.Dns]::GetHostAddresses( ("{0}.{1}" -f $hostname, $global:K8S_DNS_ZONE_NAME))
            $logHistory.addLine("> Unregistering IP for host in DNS...")
            $EPFLDNS.unregisterDNSIP($hostname, $ip, $global:K8S_DNS_ZONE_NAME)
        }
        catch
        {
            $logHistory.addLine(("> IP doesn't exists in DNS"))
        }
        
        # Si l'IP est allouée dans NSX,
        if($nsx.isIPAllocated($pool.id, $ip))
        {
            $logHistory.addLine("> Releasing IP in NSX...")
            $nsx.releaseIPAddressInPool($pool.id, $ip)
        }
        else
        {
            $logHistory.addLine("> IP is not allocated in NSX")
        }
        
    }# FIN BOUCLE de parcours des IP à supprimer
    
    
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
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
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

    # Connexion à NSX pour pouvoir allouer/restituer des adresses IP
    $nsx = [NSXAPI]::new($configNSX.getConfigValue($targetEnv, "server"), `
                            $configNSX.getConfigValue($targetEnv, "user"), `
                            $configNSX.getConfigValue($targetEnv, "password"))

    # Création du nécessaire pour interagir avec le DNS EPFL
	$EPFLDNS = [EPFLDNS]::new($configK8s.getConfigValue($targetEnv, "dns", "server"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "psEndpointServer"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "user"), 
                                $configK8s.getConfigValue($targetEnv, "dns", "password"))

                                
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
            # Initialisation pour récupérer les noms des éléments
            $nameGeneratorK8s.initDetailsFromBGName($bgName)

            $logHistory.addLine("Generating cluster name...")
            # Recherche du nom du nouveau cluster
            $clusterName = getNextClusterName -pks $pks -nameGeneratorK8s $nameGeneratorK8s
            $logHistory.addLine(("Cluster name will be '{0}" -f $clusterName))

            # Génération des noms pour le DNS
            $logHistory.addLine("Generating DNS hostnames...")
            $dnsHostName = $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryMain)
            $dnsHostNameIngress = $nameGeneratorK8s.getClusterDNSName($clusterName, [K8sDNSEntryType]::EntryIngress)
            $logHistory.addLine(("DNS hosnames will be '{0}' for main cluster and '{1}' for Ingress part" -f $dnsHostName, $dnsHostNameIngress))

            $ipPoolName = $configK8s.getConfigValue($targetEnv, "nsx", "ipPoolName")
            $logHistory.addLine(("Getting NSX IP pool '{0}'..." -f $ipPoolName))
            # Recherche du pool dans lequel on va demander les adresses IP
            $pool = $nsx.getIPPoolByName($ipPoolName)
            $logHistory.addLine(("There are {0} free IP addresses in pool (for total of {1})" -f $pool.pool_usage.free_ids, $pool.pool_usage.total_ids))
            # Si plus assez d'adresses IP de libre
            if($pool.pool_usage.free_ids -lt 2)
            {
                Throw ("Not enough free IPs in NSX '{0}' IP pool (only {1} left)" -f $ipPoolName, $pool.pool_usage.free_ids)
            }

            $logHistory.addLine("Allocating IP addresses...")
            $ipMain = $nsx.allocateIPAddressInPool($pool.id)
            $ipIngress = $nsx.allocateIPAddressInPool($pool.id)
            $logHistory.addLine(("IP adresses will be: {0} for cluster and {1} for Ingress" -f $ipMain, $ipIngress))
            
            $logHistory.addLine(("Adding DNS entries in {0} zone..." -f $global:K8S_DNS_ZONE_NAME))
            $EPFLDNS.registerDNSIP($dnsHostName, $ipMain, $global:K8S_DNS_ZONE_NAME)
            $EPFLDNS.registerDNSIP($dnsHostNameIngress, $ipIngress, $global:K8S_DNS_ZONE_NAME)

            $logHistory.addLine(("Creating cluster '{0}' with '{1}' plan and '{2}' network profil..." -f $clusterName, $plan, $netProfile))
            $cluster = $pks.addCluster($clusterName, $plan, $netProfile, $dnsHostName)

            # $cluster

            $output.results += @{
                name = $clusterName
                uuid = $cluster.uuid
                dnsHostName = $dnsHostName
            }
        }


        # --- Effacer
        $ACTION_DELETE
        {
            deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -clusterName $clusterName `
                        -ipPoolName $configK8s.getConfigValue($targetEnv, "nsx", "ipPoolName")
        }


        <#
        ----------------------------------
        --------------- PLAN -------------
        #>

        # -- Changer le plan
        $ACTION_CHANGE_PLAN
        {

        }

        # -- Renvoyer le plan
        $ACTION_GET_PLAN
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
    
    # Si on était en train de créer un cluster
    if($action -eq $ACTION_CREATE)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating cluster '{0}', deleting it so everything is clean" -f $clusterName))
        deleteCluster -pks $pks -nsx $nsx -EPFLDNS $EPFLDNS -nameGeneratorK8s $nameGeneratorK8s -clusterName $clusterName -ipPoolName $ipPoolName
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
