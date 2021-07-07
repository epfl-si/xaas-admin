<#
USAGES:
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action create -volType col -sizeGB <sizeGB> -bgId <bgId> -access cifs -svm <svm> -snapPercent <snapPercent> -snapPolicy <snapPolicy>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action create -volType col -sizeGB <sizeGB> -bgId <bgId> -access nfs3 -svm <svm> -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW> -snapPercent <snapPercent> -snapPolicy <snapPolicy>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|research -action create -volType app -sizeGB <sizeGB> -bgId <bgId> -access cifs|nfs3 -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW> -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action delete -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|research -action appVolExists -volName <volName> -bgId <bgId>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action canHaveNewVol -bgId <bgId> -access cifs|nfs3
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action resize -sizeGB <sizeGB> -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getVolSize [-volName <volName>]
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action getSVMList -bgId <bgId>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getIPList -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action updateIPList -volName <volName> -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research -action getVolInfos -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action setSnapshots -volName <volName> -snapPercent <snapPercent> -snapPolicy <snapPolicy>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant epfl -action getPrice -sizeGB <sizeGB> -snapPercent <snapPercent> [-userFeeLevel 1|2|3]
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service NAS en tant que XaaS.
                  

	DATE 	: Septembre 2020
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
      [string]$volType,
      # Pour la localisation
      [string]$svm,
      [string]$bgId, # ID d'unité, no de service (SVCxxx) ou numéro de projet
      # Volume
      [string]$volName,
      [int]$sizeGB,
      # Snapshots
      [int]$snapPercent,
      [string]$snapPolicy,
      # Accès
      [string]$access,
      [string]$IPsRoot,
      [string]$IPsRW,
      [string]$IPsRO,
      # Prix
      [int]$userFeeLevel) # Est égal à 0 si pas donné

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

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "NameGeneratorNAS.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configVra = [ConfigReader]::New("config-vra.json")
$configNAS = [ConfigReader]::New("config-xaas-nas.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_DELETE              = "delete"
$ACTION_RESIZE              = "resize"
$ACTION_GET_SIZE            = "getVolSize"
$ACTION_GET_SVM_LIST        = "getSVMList"
$ACTION_APP_VOL_EXISTS      = "appVolExists"
$ACTION_CAN_HAVE_NEW_VOL    = "canHaveNewVol"
$ACTION_GET_IP_LIST         = "getIPList"
$ACTION_UPDATE_IP_LIST      = "updateIPList"
$ACTION_GET_VOL_INFOS       = "getVolInfos"
$ACTION_SET_SNAPSHOTS       = "setSnapshots"
$ACTION_GET_PRICE           = "getPrice"

# Limites
$global:MAX_VOL_PER_UNIT    = 999

# Autre
$global:EXPORT_POLICY_DENY_NFS_ON_CIFS = "deny_nfs_on_cifs"

<#
    -------------------------------------------------------------------------------------
    BUT : Retourne le prochain nom de volume utilisable

    IN  : $netapp           -> Objet de la classe NetAppAPI pour se connecter au NetApp
    IN  : $nameGeneratorNAS -> Objet de la classe NameGeneratorNAS
    IN  : $access           -> le type d'accès -> [NetAppProtocol]

    RET : Nouveau nom du volume
            $null si on a atteint le nombre max de volumes pour l'unité
#>
function getNextColVolName([NetAppAPI]$netapp, [NameGeneratorNAS]$nameGeneratorNAS, [NetAppProtocol]$access)
{
    $isNFS = ($access -eq [NetAppProtocol]::nfs3)

    # Définition de la regex pour trouver les noms de volumes
    $volNameRegex = $nameGeneratorNAS.getCollaborativeVolDetailedRegex($isNFS)
    $unitVolList = $netapp.getVolumeList() | Where-Object { [Regex]::Match($_.name, $volNameRegex).Success } | Sort-Object | Select-Object -ExpandProperty name

    # Recherche du prochain numéro libre
    for($i=1; $i -lt $global:MAX_VOL_PER_UNIT; $i++)
    {
        $curVolName = $nameGeneratorNAS.getVolName($i, $isNFS)
        if($unitVolList -notcontains $curVolName)
        {
            return $curVolName
            break
        }	
    }

    return $null
}


<#
    -------------------------------------------------------------------------------------
    BUT : Retourne la SVM à utiliser pour héberger un volume applicatif

    IN  : $netapp           -> Objet de la classe NetAppAPI pour se connecter au NetApp
    IN  : $svmList          -> Liste des SVM parmi lesquelles choisir
    IN  : $protocol         -> Nom du protocol qui a été demandé pour le volume

    RET : Objet représentant la SVM
#>
function chooseAppSVM([NetAppAPI]$netapp, [Array]$svmList, [NetAppProtocol]$protocol)
{
    $iops = $null
    $targetSVM = $null
    # Parcours des SVM
    ForEach($svmName in $svmList)
    {
        # Recherche des infos de la SVM puis de son aggregat
        $svm = $netapp.getSVMByName($svmName)

        # Si la SVM n'a pas été trouvée, il doit y avoir une erreur dans le fichier de données
        if($null -eq $svm)
        {
            Throw ("Defined applicative SVM ({0}) not found. Please check 'data/xaas/nas/applicatives-svm.json' content" -f $smvName)
        }

        # Recherche des IOPS de la SVM
        $svmIOPS = $netapp.getSVMMetrics($svm, $protocol, [NetAppMetricType]::total).iops

        # Si l'aggregat courant est moins utilisé
        if( ($null -eq $iops) -or ($svmIOPS -lt $iops))
        {
            $iops = $svmIOPS
            $targetSVM = $svm
        }
    }

    return $targetSVM
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie la taille correcte à initialiser pour le volume au vu du pourcentage à 
            réserver pour les snapshots

    IN  : $requestedSizeGB  -> Taille demandée pour le Volume
    IN  : $snapSpacePercent -> Pourcentage d'espace à réserver pour les snapshots

    RET : Taille "réelle" à utiliser pour créer le volume
#>
function getCorrectVolumeSize([int]$requestedSizeGB, [int]$snapSpacePercent)
{
    return $requestedSizeGB * 100 / (100 - $snapSpacePercent)
    
}


<#
    -------------------------------------------------------------------------------------
    BUT : Efface un volume et tout ce qui lui est lié

    IN  : $nameGeneratorNAS -> Objet de la clases NameGeneratorNAS pour gérer la nomenclature
    IN  : $netapp           -> Objet de la classe NetAPPAPI permettant d'accéder au NAS
    IN  : $volumeName       -> Nom du volume à effacer
    IN  : $output           -> Objet représentant l'output du script. Peut être $null
                                si on n'a pas envie de le modifier

    RET : Objet $output potentiellement modifié.
#>
function deleteVolume([NameGeneratorNAS]$nameGeneratorNAS, [NetAPPAPI]$netapp, [string]$volumeName, [PSObject]$output)
{
    $logHistory.addLine( ("Getting Volume {0}..." -f $volumeName) )
    # Recherche du volume à effacer et effacement
    $volObj = $netapp.getVolumeByName($volumeName)

    # Si le volume n'existe pas
    if($null -eq $volObj)
    {
        # Si on a passé un objet, 
        if($null -ne $output)
        {
            $output.error = ("Volume {0} doesn't exists" -f $volumeName)
        }
        
        $logHistory.addLine($output.error)
    }
    else
    {
        $logHistory.addLine( ("Getting SVM '{0}'..." -f $volObj.svm.name) )
        $svmObj = $netapp.getSVMByID($volObj.svm.uuid)

        $logHistory.addLine(("Getting CIFS Shares for Volume '{0}'..." -f $volumeName))
        $shareList = $netapp.getVolCIFSShareList($volObj)
        $logHistory.addLine(("{0} CIFS share(s) found..." -f $shareList.count))

        # Suppression des shares CIFS
        ForEach($share in $shareList)
        {
            $logHistory.addLine( ("> Deleting CIFS Share '{0}'..." -f $share.name) )
            $netapp.deleteCIFSShare($share)
        }

        $logHistory.addLine( ("Deleting Volume {0}" -f $volumeName) )
        $netapp.deleteVolume($volObj)

        # Export Policy (on la supprime tout à la fin sinon on se prend une erreur "gnagna elles utilisée par le volume"
        # donc on vire le volume ET ENSUITE l'export policy)
        $exportPolicyName = $nameGeneratorNAS.getExportPolicyName($volumeName)
        $logHistory.addLine(("Getting NFS export policy '{0}'" -f $exportPolicyName))
        $exportPolicy = $netapp.getExportPolicyByName($svmObj, $exportPolicyName)
        if($null -ne $exportPolicy)
        {
            $logHistory.addLine(("> Deleting export policy '{0}'...") -f $exportPolicyName)
            $netapp.deleteExportPolicy($exportPolicy)
        }
        else
        {
            $logHistory.addLine("> Export policy doesn't exists")
        }
    }

    return $output
}


<#
    -------------------------------------------------------------------------------------
    BUT : Démonte une lettre de lecteur

    IN  : $driveLetter ->  La lettre de lecteur à démonter
#>
function unMountPSDrive([string]$driveLetter)
{
    $drive = Get-PSDrive $driveLetter -errorVariable errorVar -errorAction:SilentlyContinue

    # Si on a pu trouver le drive
    if($errorVar.count -eq 0)
    {
        # On fait "sale" pour démonter le lecteur. On devrait normalement utiliser "Remove-PSDrive"
        # mais ça ne fonctionne pas à tous les coups donc... 
        net.exe use ("{0}:" -f $drive.Name) /del | Out-Null
    }
    
}


<#
    -------------------------------------------------------------------------------------
    BUT : Ajoute une export policy pour un volume avec les règles adéquates

    IN  : $nameGeneratorNAS ->  Objet pour générer les noms pour le NAS
    IN  : $netapp       -> Objet de la classe NetAPPAPI permettant d'accéder au NAS
    IN  : $volumeName   -> Nom du volume à effacer
    IN  : $svmObj       -> Objet représentant la SVM sur laquelle ajouter l'export policy
    IN  : $IPsRO        -> Chaine de caractères avec les IP RO
    IN  : $IPsRW        -> Chaine de caractères avec les IP RW
    IN  : $IPsRoot      -> Chaine de caractères avec les IP Root
    IN  : $protocol     -> Le protocole d'accès ([NetAppProtocol])
    IN  : $result       -> Tableau associatif représentant le résultat du script. Peut être $null
                            si on n'a pas envie de le modifier

    RET : Tableau avec :
            - l'export policy ajoutée
            - l'objet renvoyé par le script (JSON) avec les infos du point de montage
#>
function addNFSExportPolicy([NameGeneratorNAS]$nameGeneratorNAS, [NetAppAPI]$netapp, [string]$volumeName, [PSObject]$svmObj, [string]$IPsRO, [string]$IPsRW, [string]$IPsRoot, [NetAppProtocol]$protocol, [Hashtable]$result)
{
    $exportPolicyName = $nameGeneratorNAS.getExportPolicyName($volumeName)

    $logHistory.addLine(("Creating export policy '{0}'..." -f $exportPolicyName))
    # Création de l'export policy 
    $exportPolicy = $netapp.addExportPolicy($exportPolicyName, $svmObj)

    $logHistory.addLine("Add rules to export policy...")
    $netapp.updateExportPolicyRules($exportPolicy, ($IPsRO -split ","), ($IPsRW -split ","), ($IPsRoot -split ","), $protocol)

    # Si on doit mettre l'objet à jour
    if($null -ne $result)
    {
        # On ajoute le nom du share CIFS au résultat renvoyé par le script
        $result.mountPath = $nameGeneratorNAS.getVolMountPath($volumeName, $svmObj.name, [NetAppProtocol]::nfs3)
    }
    
    return @($exportPolicy, $result)
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie les infos d'une export Policy

    IN  : $volObj       -> Objet représentant le volume pour lequel on veut les infos de 
                            l'export Policy
    IN  : $svmObj       -> Objet représentant la SVM sur laquelle le volume se trouve

    RET : Objet avec les infos de l'export policy
#>
function getExportPolicyInfos([PSObject]$volObj, [PSObject]$svmObj)
{
    # Recherche de l'export policy qui "devrait" être définie sur le volume s'il fallait limiter les accès
    $exportPolicyObj = $netapp.getExportPolicyByName($svmObj, $volObj.nas.export_policy.name)

    # Si pas d'export Policy
    if($null -eq $exportPolicyObj)
    {
        $rules = @()
    }
    else
    {
        $rules = $netapp.getExportPolicyRuleList($exportPolicyObj)
    }

    return @{
        protocol = $netapp.getVolumeAccessProtocol($volObj).ToString()
        rules = $rules
    }
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie les infos de taille d'un volume

    IN  : $netapp       -> Objet permettant d'accéder à l'API de NetApp
    IN  : $volObj       -> Objet représentant le volume

    RET : Objet avec les infos de taille
#>
function getVolumeSizeInfos([NetAppAPI]$netapp, [PSObject]$volObj)
{
    $volSizeInfos = $netapp.getVolumeSizeInfos($volObj)

    $volSizeB = $volObj.space.size
    # Suppression de l'espace réservé pour les snapshots
    $userSizeB = $volSizeB * (1 - ($volSizeInfos.space.snapshot.reserve_percent/100))
    $snapSizeB = $volSizeB * ($volSizeInfos.space.snapshot.reserve_percent/100)

    return @{
        # Infos "globales"
        totSizeB = (truncateToNbDecimal -number ($volSizeB) -nbDecimals 2)
        # Taille niveau "utilisateur"
        user = @{
            sizeB = (truncateToNbDecimal -number $userSizeB -nbDecimals 2)
            usedB = (truncateToNbDecimal -number $volObj.space.used -nbDecimals 2)
            usedFiles = $volSizeInfos.files.used
            maxFiles = $volSizeInfos.files.maximum
        }
        # Taille niveau "snapshot"
        snap = @{
            reservePercent = $volSizeInfos.space.snapshot.reserve_percent
            reserveSizeB = (truncateToNbDecimal -number $snapSizeB -nbDecimals 2)
            usedB = (truncateToNbDecimal -number $volSizeInfos.space.snapshot.used -nbDecimals 2)
        }
    }
}


<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie toutes les infos d'un volume

    IN  : $netapp           -> Objet permettant d'accéder à l'API de NetApp
    IN  : $nameGeneratorNAS -> Objet permettant de générer les noms pour le NAS
    IN  : $volObj           -> Objet représentant le volume

    RET : Objet avec les infos de taille
#>
function getVolumeInfos([NetAppAPI]$netapp, [NameGeneratorNAS]$nameGeneratorNAS, [PSObject]$volObj)
{
    # Première partie des infos
    $result = @{
        volume = @{
            name = $volObj.name
            uuid = $volObj.uuid
            type = $nameGeneratorNAS.getVolumeType($volObj.name).ToString()
        }
    }

    # Pour la suite, on va avoir besoin de la SVM
    $svmObj = $netapp.getSVMByID($volObj.svm.uuid)

    # -- Accès
    $result.access = getExportPolicyInfos -volObj $volObj -svmObj $svmObj
    $result.access.svm = $svmObj.name
    $result.access.rootMountPath = $nameGeneratorNAS.getVolMountPath($volObj.name, $svmObj.name, $result.access.protocol) 

    # -- Taille
    $result.size = getVolumeSizeInfos -netapp $netapp -volObj $volObj

    # -- Snapshots
    $snapshotPolicyObj = $netapp.getVolumeSnapshotPolicy($volObj)
    if($null -ne $snapshotPolicyObj)
    {
        $result.snapshots = @{
            policy = $snapshotPolicyObj.name
            reservePercent = $result.size.snap.reservePercent
        }
    }
    else
    {
        $result.snapshots = $null
    }

    # -- Share CIFS
    $shareList = $netapp.getVolCIFSShareList($volObj) | Select-Object -ExpandProperty name
    # Si la liste est vide, le fait de sélectionner 'name' va renvoyer $null en fait, et pas un tableau vide
    if($null -eq $shareList)
    {
        $shareList = @()
    }

    # Sélection du nom du share et transformation en tableau pour éviter de se retrouver avec un objet uniquement s'il n'y a qu'un share
    $result.access.cifsShares = $shareList 

    return $result
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
    $logHistory = [LogHistory]::new(@('xaas','nas', 'endpoint'), $global:LOGS_FOLDER, 120)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
    $nameGeneratorNAS = [NameGeneratorNAS]::new($targetEnv, $targetTenant)

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
						 $targetTenant, 
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Création de l'objet pour se connecter aux clusters NetApp
    $netapp = [NetAppAPI]::new($configNAS.getConfigValue(@($targetEnv, "serverList")),
                                $configNAS.getConfigValue(@($targetEnv, "user")),
                                $configNAS.getConfigValue(@($targetEnv, "password")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $netapp.activateDebug($logHistory)    
        $vra.activateDebug($logHistory)
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

    }


    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_CREATE 
        {

            # Pour dire si on peut effectuer du cleaning dans le cas d'une erreur
            $cleaningCanBeDoneIfError = $true

            # En fonction du type de volume
            switch($volType)
            {
                # ---- Volume Applicatif
                app
                {
                    $nameGeneratorNAS.setApplicativeDetails($bgId, $volName)

                    # Chargement des informations sur le mapping des facultés
                    $appSVMFile = ([IO.Path]::Combine($global:DATA_FOLDER, "XaaS", "NAS", "applicative-svm.json"))
                    $appSVMList = loadFromCommentedJSON -jsonFile $appSVMFile

                    # Choix de la SVM
                    $logHistory.addLine("Choosing SVM for volume...")
                    $svmObj = chooseAppSVM -netapp $netapp -svmList $appSVMList.($targetEnv.ToLower()).($access.ToLower()) -protocol ([NetAppProtocol]$access)
                    $logHistory.addLine( ("SVM will be '{0}'" -f $svmObj.name) )

                    # Pas d'espace réservé pour les snapshots
                    $snapPercent = 0

                    # Génération du "nouveau" nom du volume
                    $volName = $nameGeneratorNAS.getVolName()
                    $logHistory.addLine(("Final Volume name will be '{0}'" -f $volName))

                }

                # ---- Volume Collaboratif
                col
                {
                    # Check des valeurs passées pour les snapshots
                    if( (($snapPercent -eq 0) -and ($snapPolicy -ne "")) -or ( ($snapPercent -ne 0) -and ($snapPolicy -eq "") ))
                    {
                        Throw ("Incorrect value combination for snapPercent ({0}) and snapPolicy ({1})" -f $snapPercent, $snapPolicy)
                    }

                    # Initialisation des détails
                    $nameGeneratorNAS.setCollaborativeDetails($bg.name, $bgId)

                    $logHistory.addLine( "Generating volume name..." )
                    # Recheche du prochain nom de volume
                    $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -access $access
                    $logHistory.addLine( ("New volume name will be '{0}'" -f $volName) )
                    if($null -eq $volName)
                    {
                        Throw ("Maximum number of volumes for unit ({0}) reached" -f $global:MAX_VOL_PER_UNIT)
                    }

                    # Recherche de la SVM
                    $svmObj = $netapp.getSVMByName($svm)

                    if($null -eq $svmObj)
                    {
                        Throw ("SVM '{0}' doesn't exists" -f $svm)
                    }

                }

                default
                {
                    Throw ("Incorrect parameter given for 'volType' ({0})" -f $volType)
                }
            } # FIN en fonction du type de volume

            # On regarde si le volume existe (normalement pas mais on fait un check quand même au cas où, mieux vaut ceintures et bretelles !)
            if($null -ne $netapp.getVolumeByName($volName))
            {
                # Pour s'assurer de ne pas tout effacer en cas d'erreur !
                $cleaningCanBeDoneIfError = $false
                Throw ("Volume with name '{0}' already exists" -f $volName)
            }

            # En fonction du type d'accès qui a été demandé
            switch($access)
            {
                cifs
                {
                    $securityStyle = "ntfs"
                }

                nfs3
                {
                    $securityStyle = "unix"
                }
            }

            # -----------------------------------------------
            # 1. Création du volume

            $logHistory.addLine( ("Creating Volume {0} on SVM {1} and aggregate {2}..." -f $volName, $svmObj.name, $svmObj.aggregates[0].name) )

            # Définition du chemin de montage du volume
            $mountPoint = "/{0}" -f $volName

            # Redéfinition de la taille du volume en fonction du pourcentage à conserver pour les snapshots
            $sizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB $sizeGB -snapSpacePercent $snapPercent

            # Création du nouveau volume
            $newVol = $netapp.addVolume($volName, $sizeWithSnapGB, $svmObj, $svmObj.aggregates[0], $securityStyle, $mountPoint, $snapPercent)

            # Pour le retour du script
            $result = @{
                volName = $volName
                volUUID = $newVol.uuid
                sizeGB = $sizeGB
                svm = $svmObj.name
            }
            # Il faut mainteannt créer le nécessaire pour accéder au volume


            # -----------------------------------------------
            # 2. Mise en place des accès

            # En fonction du type d'accès qui a été demandé
            switch($access)
            {
                # ------------ CIFS
                cifs
                {
                    $logHistory.addLine( ("Adding CIFS share '{0}' to point on '{1}'..." -f $volName, $mountPoint))
                    $netapp.addCIFSShare($volName, $svmObj, $mountPoint)

                    # On ajoute le nom du share CIFS au résultat renvoyé par le script
                    $result.mountPath = $nameGeneratorNAS.getVolMountPath($volName, $svmObj.name, [NetAppProtocol]::cifs) 
                    
                    # En fonction du type de volume
                    switch($volType)
                    {
                        # ---- Volume Applicatif
                        app
                        {
                            # Ajout de l'export policy
                            $exportPol, $null = addNFSExportPolicy -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -svmObj $svmObj `
                                                        -IPsRO $IPsRO -IPsRW $IPsRW -IPsRoot $IPsRoot -protocol ([NetAppProtocol]$access) -result $null
                        }

                        # ---- Volume Collaboratif
                        col
                        {
                            $logHistory.addLine(("Checking if Export Policy '{0}' exists on SVM '{1}'..." -f $global:EXPORT_POLICY_DENY_NFS_ON_CIFS, $svmObj.name))
                            $exportPol = $netapp.getExportPolicyByName($svmObj, $global:EXPORT_POLICY_DENY_NFS_ON_CIFS)

                            if($null -eq $exportPol)
                            {
                                $logHistory.addLine("Export Policy doesn't exists, creating...")
                                # Création de l'export policy
                                $exportPol = $netapp.addExportPolicy($global:EXPORT_POLICY_DENY_NFS_ON_CIFS, $svmObj)
                            }

                            # --- ACLs

                            # Récupération des utilisateurs qui ont le droit de demander des volumes
                            $userAndGroupList = $vra.getBGRoleContent($bg.id, "CSP_CONSUMER")

                            <# Pour modifier les ACLs, on pourrait accéder directement via le chemin UNC \\<svm>.epfl.ch\<share> et ça fonctionne... MAIS ... 
                                ça ne fonctionne par contre plus dès que le script est exécuté depuis vRO... pourquoi? aucune foutue idée... semblerait que même
                                s'il est "soi-disant" exécuté avec un utilisateur du domaine, bah celui-ci n'a en fait aucun credential lui permettant par exemple
                                d'accéder au share réseau. Donc, pour palier à ceci, on fait les choses d'une manière différente. On récupère les credentials de
                                l'utilisateur et on monte un lecteur réseau temporaire pour pouvoir utiliser celui-ci pour mettre à jour les ACLs.
                             #>
                            $secPassword = ConvertTo-SecureString $configNAS.getConfigValue(@("psGateway", "password")) -AsPlainText -Force
                            $credentials = New-Object System.Management.Automation.PSCredential($configNAS.getConfigValue(@("psGateway", "user")), $secPassword)
                            
                            $logHistory.addLine(("Mounting '{0}' on '{1}'..." -f $result.mountPath, $global:XAAS_NAS_TEMPORARY_DRIVE))
                            # On démonte le dossier monté dans le cas hypothétique où il serait déjà utilisé 
                            unMountPSDrive -driveLetter $global:XAAS_NAS_TEMPORARY_DRIVE
                            $temporaryDrive = New-PSDrive -Persist -name $global:XAAS_NAS_TEMPORARY_DRIVE -PSProvider "Filesystem" -Root $result.mountPath -Credential $credentials
                            
                            $logHistory.addLine(("Getting ACLs on '{0}'..." -f $global:XAAS_NAS_TEMPORARY_DRIVE))
                            # Récupération des ACLs actuelles
                            $acl = Get-ACL $temporaryDrive.Root
                            if($null -eq $acl)
                            {
                                Throw ("Error getting ACLs for Drive '{0}'" -f $temporaryDrive.Root)
                            }
                            
                            # Parcours des utilisateurs/groupes à ajouter
                            ForEach($userOrGroupFQDN in $userAndGroupList)
                            {
                                # $userOrGroup contient un groupe ou un utilisateur au format <userOrGroup>@intranet.epfl.ch.
                                # Il faut donc reformater ceci pour avoir INTRANET\<userOrGroup>
                                $userOrGroup, $null = $userOrGroupFQDN -split '@'
                                $userOrGroup = "INTRANET\{0}" -f $userOrGroup
                                $logHistory.addLine(("> Preparing ACL for '{0}'..." -f $userOrGroup))
                                $ar = New-Object  system.security.accesscontrol.filesystemaccessrule($userOrGroup,  "FullControl", "ContainerInherit,ObjectInherit",  "None", "Allow")
                                $acl.AddAccessRule($ar)
                            }

                            $logHistory.addLine(("Updating ACLs on '{0}'..." -f $global:XAAS_NAS_TEMPORARY_DRIVE))
                            Set-Acl $temporaryDrive.Root $acl
                            # On vire les accès Everyone (on ne peut pas le faire avant sinon on se coupe l'herbe sous le pied pour ce qui est de l'établissement des droits)
                            $acl.access | Where-Object { $_.IdentityReference -eq "Everyone"} | ForEach-Object { $acl.RemoveAccessRule($_)} | Out-Null
                            # Et on fini par mettre à jour sans les Everyone
                            Set-Acl $temporaryDrive.Root $acl

                            $logHistory.addLine(("Unmounting temporary drive '{0}'..." -f $global:XAAS_NAS_TEMPORARY_DRIVE))
                            # On démonte le dossier monté
                            unMountPSDrive -driveLetter $global:XAAS_NAS_TEMPORARY_DRIVE
                        }
                    }# FIN EN FONCTION du type de volume
                }


                # ------------ NFS
                nfs3
                {
                    # Ajout de l'export policy
                    $exportPol, $result = addNFSExportPolicy -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -svmObj $svmObj `
                                                -IPsRO $IPsRO -IPsRW $IPsRW -IPsRoot $IPsRoot -protocol ([NetAppProtocol]$access) -result $result
                }
            }# FIN En fonction du type d'accès demandé 

            $logHistory.addLine(("Applying Export Policy '{0}' to SVM '{1}' on Volume '{2}'" -f $exportPol.name, $svmObj.name, $volName))
            $netapp.applyExportPolicyOnVolume($exportPol, $newVol)

            # -----------------------------------------------
            # 3. Politique de snapshot

            # Si volume collaboratif ET qu'il faut avoir les snapshots
            if(( $volType -eq [XaaSNASVolType]::col) -and $snapPolicy -ne "")
            {
                $snapPolicyObj = $netapp.getSnapshotPolicyByName($snapPolicy)
                if($null -eq $snapPolicyObj)
                {
                    Throw ("Given snapshot policy ({0}) not found" -f $snapPolicy)
                }
                # On applique la policy de snapshot
                $logHistory.addLine(("Applying Snapshot Policy '{0}' on Volume '{1}'" -f $snapPolicy, $volName))
                $netapp.applySnapshotPolicyOnVolume($snapPolicyObj, $newVol)
            }
            else
            {
                $logHistory.addLine("No snapshot policy to apply")
            }

            $output.results += $result
           
        }# FIN Action Create


        # -- Effacement d'un Volume
        $ACTION_DELETE 
        {
            # Effacement du volume 
            $output = deleteVolume -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -output $output
        }# FIN Action Delete


        # -- Resize d'un volume
        $ACTION_RESIZE 
        {

            $logHistory.addLine( ("Getting Volume {0}" -f $volName) )
            $volObj = $netapp.getVolumeByName($volName)
            
            # Si volume pas trouvé
            if($null -eq $volObj)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else # Volume trouvéc
            {
                # Recherche des infos sur les snapshots
                $volSizeInfos = $netapp.getVolumeSizeInfos($volObj)

                # Redéfinition de la taille du volume en fonction du pourcentage à conserver pour les snapshots
                $sizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB $sizeGB -snapSpacePercent $volSizeInfos.space.snapshot.reserve_percent

                $logHistory.addLine( ("Resizing Volume {0} to {1} GB" -f $volName, $sizeGB) )
                $netapp.resizeVolume($volObj, $sizeWithSnapGB, $volSizeInfos.space.snapshot.reserve_percent)
            }
        }# FIN Action resize


        # -- Renvoie la taille d'un Volume
        $ACTION_GET_SIZE 
        {

            if($volName -ne "")
            {
                $volNameList = @($volName)
            }
            else
            {
                $volNameList = $netapp.getVolumeList() | Select-Object -ExpandProperty name
            }

            # Parcours des volumes dont on veut la taille
            $volNameList | ForEach-Object { 

                $logHistory.addLine( ("Getting size for Volume {0}" -f $_) )
                $volObj = $netapp.getVolumeByName($_)

                # Si volume pas trouvé, c'est qu'on a probablement donné un nom unique en paramètre
                if($null -eq $volObj)
                {
                    $output.error = ("Volume {0} doesn't exists" -f $_)
                    $logHistory.addLine($output.error)
                    return
                }

                # Recherche et ajout des infos
                $sizeInfos = getVolumeSizeInfos -netapp $netapp -volObj $volObj
                $sizeInfos += @{
                    volName = $volObj.name
                    volUUID = $volObj.uuid
                }
                $output.results += $sizeInfos
            }
        }# FIN Action Delete


        # -- Renvoie la liste des SVM pour une faculté
        $ACTION_GET_SVM_LIST 
        {
            # Récupération du nom de la faculté et de l'unité
            $details = $nameGeneratorNAS.getDetailsFromBGName($bg.name)
            $faculty = $details.faculty
            $logHistory.addLine( ("Searching SVM for Faculty '{0}'" -f $faculty) )

            # Chargement des informations sur le mapping des facultés
            $facultyMappingFile = ([IO.Path]::Combine($global:DATA_FOLDER, "XaaS", "NAS", "faculty-mapping.json"))
            $facultyMappingList = loadFromCommentedJSON -jsonFile $facultyMappingFile

            # Chargement des informations 
            $facultyToSVMFile = ([IO.Path]::Combine($global:DATA_FOLDER, "XaaS", "NAS", "faculty-svm.json"))
            $facultyToSVM = loadFromCommentedJSON -jsonFile $facultyToSVMFile

            # On commence par regarder s'il y a un mapping pour la faculté donnée
            $targetFaculty = $faculty
            Foreach($facMapping in $facultyMappingList)
            {
                if($facMapping.fromFacList -contains $faculty)
                {
                    $targetFaculty = $facMapping.toFac

                    $logHistory.addLine( ("Mapping found for Faculty '{0}'. We have to use '{1}' faculty" -f $faculty, $targetFaculty) )
                    break
                }
            }

            
            # Liste des SVM pour la faculté (avec la bonne nommenclature)
            $svmList = @($netapp.getSVMList() | Where-Object { $_.name -match ('^{0}[0-9].*' -f $targetFaculty)} | Select-Object -ExpandProperty name)

            # Si on a une liste hard-codée de SVM pour la faculté
            if(objectPropertyExists -obj $facultyToSVM.$targetEnv -propertyName $faculty)
            {
                # On ajoute la liste hard-codée
                $svmList += $facultyToSVM.$targetEnv.$faculty
            }

            # Ajout du résultat trié
            $output.results += $svmList | Sort-Object
        }


        # -- Savoir si un volume existe
        $ACTION_APP_VOL_EXISTS
        {
            $res = @{
                reqVolName = $volName
            }

            # Si on veut savoir pour un volume applicatif, 
            $nameGeneratorNAS.setApplicativeDetails($bgId, $volName)
                
            # on regarde quel nom devrait avoir le volume applicatif
            $volName = $nameGeneratorNAS.getVolName()
            # Et on l'enregistre dans le résultat 
            $res.appVolName = $volName

            $res += @{
                exists = ($null -ne $netapp.getVolumeByName($volName))
            }

            $output.results += $res
        }


        # -- Pour savoir si une unité a le droit d'avoir un nouveau volume
        $ACTION_CAN_HAVE_NEW_VOL
        {
           
            $nameGeneratorNAS.setCollaborativeDetails($bg.name, $bgId)

            $logHistory.addLine( "Looking for next volume name..." )
            # Recheche du prochain nom de volume
            $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -access $access
            if($null -eq $volName)
            {
                $logHistory.addLine(("Maximum number of volume reached for BG {0} ({1})" -f $bg.name, $bgId))
            }
            else
            {
                $logHistory.addLine( ("Next volume name is '{0}'" ) -f $volName)
            }
            
            $output.results += @{
                canHaveNewVol = ($null -ne $volName)
            }
        }


        # -- Retour de la liste des IP d'accès
        $ACTION_GET_IP_LIST
        {
            
            $logHistory.addLine(("Getting Volume '{0}' IP List..." -f $volName))
            $volObj = $netapp.getVolumeByName($volName)

            # Si volume pas trouvé, c'est qu'on a probablement donné un nom unique en paramètre
            if($null -eq $volObj)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else
            {
                $svmObj = $netapp.getSVMByID($volObj.svm.uuid)
                # Ajout des infos d'accès
                $output.results += getExportPolicyInfos -volObj $volObj -svmObj $svmObj
            }
        }


        # -- Mise à jour de la liste des IP
        $ACTION_UPDATE_IP_LIST
        {

            $logHistory.addLine(("Getting Volume '{0}'..." -f $volName))
            $volObj = $netapp.getVolumeByName($volName)

            # Si volume pas trouvé, c'est qu'on a probablement donné un nom unique en paramètre
            if($null -eq $volObj)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else
            {
                # Pour la suite, on va avoir besoin de la SVM
                $svmObj = $netapp.getSVMByID($volObj.svm.uuid)

                $exportPolicyName = $nameGeneratorNAS.getExportPolicyName($volName)
                $logHistory.addLine(("Getting Export Policy '{0}' for volume '{1}'..." -f $exportPolicyName, $volName))
                $exportPolicy = $netapp.getExportPolicyByName($svmObj, $exportPolicyName)

                # Si pas trouvé
                if($null -eq $exportPolicy)
                {
                    $output.error = ("Export policy '{0}' doesn't exists" -f $exportPolicyName)
                    $logHistory.addLine($output.error)
                }
                else
                {
                    $logHistory.addLine(("Getting access protocol for volume '{0}'..." -f $volName))
                    $protocol = $netapp.getVolumeAccessProtocol($volObj)
                    $logHistory.addLine(("Access protocol is {0}" -f $protocol.toString()))

                    $logHistory.addLine("Updating rules in export policy...")
                    $netapp.updateExportPolicyRules($exportPolicy, ($IPsRO -split ","), ($IPsRW -split ","), ($IPsRoot -split ","), $protocol)
                }
            }
        }


        # -- Plein d'informations sur le volume
        $ACTION_GET_VOL_INFOS
        {
            $volObj = $netapp.getVolumeByName($volName)

            if($null -eq $volObj)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else
            {
                # Ajout des détails sur le volume
                $output.results += getVolumeInfos -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -volObj $volObj

            } # FIN SI le volume existe
        }


        # -- Initialise la règle de snapshot pour un volume
        $ACTION_SET_SNAPSHOTS
        {
            $volObj = $netapp.getVolumeByName($volName)

            if($null -eq $volObj)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else
            {
                # Récupération des détails sur le volume
                $volInfos = getVolumeInfos -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -volObj $volObj

                # On contrôle que le pourcentage de réserve pour les snaps soit correct
                if($snapPercent -lt $volInfos.snapshots.reservePercent)
                {
                    $output.error = ("New snapshot reserve ({0}%) is less than current ({1}%)" -f $snapPercent, $volInfos.snapshots.reservePercent)
                }
                else
                {
                    # Si la réserve de snapshot change
                    if($snapPercent -ne $volInfos.snapshots.reservePercent)
                    {
                        # Redéfinition de la taille du volume en fonction du pourcentage à conserver pour les snapshots
                        $newSizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB ($volInfos.size.user.sizeB /1024 /1024 /1024) -snapSpacePercent $snapPercent

                        $logHistory.addLine( ("Change Volume snapshot reserve from {0}% to {1}%" -f $volInfos.snapshots.reservePercent, $snapPercent) )
                        $netapp.resizeVolume($volObj, $newSizeWithSnapGB, $snapPercent)
                    }
                    else
                    {
                        $logHistory.addLine( ("Snapshot reserve ({0}%) doesn't change" -f $snapPercent) )
                    }

                    # Si la policy de snapshot change
                    if($snapPolicy -ne $volInfos.snapshots.policy)
                    {
                        $snapPolicyObj = $netapp.getSnapshotPolicyByName($snapPolicy)

                        if($null -eq $snapPolicyObj)
                        {
                            $output.error = ("Snapshot policy '{0}' doesn't exists" -f $snapPolicy)
                        }
                        else
                        {
                            # Changement de la policy
                            $logHistory.addLine(("Changing snapshot policy from '{0}' to '{1}'" -f $volInfos.snapshots.policy, $snapPolicy))
                            $netapp.applySnapshotPolicyOnVolume($snapPolicyObj, $volObj)
                        }

                    }# FIN SI la policy de snapshot change

                } # FIN Si la réserve de snapshot est correcte

            }# FIN si le volume existe

        }# FIN CASE changement de politique de snapshot


        # -- Renvoi du prix
        $ACTION_GET_PRICE
        {
            # Si paramètre pas passé, on prend le niveau 1 par défaut
            if($userFeeLevel -eq 0)
            {
                $userFeeLevel = 1
            }
            # Fichier JSON contenant les détails du service que l'on veut facturer    
            $serviceBillingInfosFile = ([IO.Path]::Combine("$PSScriptRoot", "data", "billing", "nas", "service.json"))

            if(!(Test-Path -path $serviceBillingInfosFile))
            {
                Throw ("Service file ({0}) for '{1}' not found. Please create it from 'config-sample.json' file." -f $serviceBillingInfosFile, $service)
            }

            # Chargement des informations (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
            $serviceBillingInfos = loadFromCommentedJSON -jsonFile $serviceBillingInfosFile

            # On recherche l'entité de facturation en fonction du tenant
            $entityType = getBillingEntityTypeFromTenant -tenant $targetTenant

            $itemType = "NAS Volume"
            # Recherche des infos sur le type d'élément qu'on facture (vu qu'il peut y en avoir plusieurs pour un service)
            $billedItemInfos = $serviceBillingInfos.billedItems | Where-Object { $_.itemTypeInDB -eq $itemType}
            
            if($null -eq $billedItemInfos)
            {
                Throw("No billing information found for Item Type '{0}'. Have a look at billing JSON configuration file for NAS service ({1})" -f $itemType, $serviceBillingInfosFile)
            }

            # Si on n'a pas d'infos de facturation pour le type d'entité, on ne va pas plus loin, on traite ça comme une erreur
            if(!(objectPropertyExists -obj $billedItemInfos.entityTypesMonthlyPriceLevels -propertyName $entityType))
            {
                Throw ("Error for item type '{0}' because no billing info found for entity '{1}'. Have a look at billing JSON configuration file for NAS service ({2})" -f `
                        $itemType, $entityType, $serviceBillingInfosFile)
            }

            $priceLevel = "U.{0}" -f $userFeeLevel
            # Si on n'a pas d'infos de facturation pour le niveau demandé, on ne va pas plus loin, on traite ça comme une erreur
            if(!(objectPropertyExists -obj $billedItemInfos.entityTypesMonthlyPriceLevels.$entityType -propertyName $priceLevel))
            {
                Throw ("Error for item type '{0}' and entity '{1}' because no billing info found for level '{2}'. Have a look at billing JSON configuration file for NAS service ({3})" -f `
                        $itemType, $entityType, $priceLevel, $serviceBillingInfosFile)
            }
            
            # On récupère la valeur via "Select-Object" car le nom du niveau peut contenir des caractères non alphanumériques qui sont
            # donc incompatibles avec un nom de propriété accessible de manière "standard" ($obj.<propertyName>)
            $TBPricePerMonth = $billedItemInfos.entityTypesMonthlyPriceLevels.$entityType | Select-Object -ExpandProperty $priceLevel
            
            # Calcul de la taille que le volume devrait faire avec les snaps
            $sizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB $sizeGB -snapSpacePercent $snapPercent

            # Ajout des chiffres
            $result = @{
                # Taille et coût des snaps
                snap = @{
                    reserveSizeGB = truncateToNbDecimal -number ($sizeWithSnapGB - $sizeGB) -nbDecimals 2
                    pricePerMonthCHF = ( truncateToNbDecimal -number (($sizeWithSnapGB - $sizeGB) /1024 * $TBPricePerMonth) -nbDecimals 2)
                }
                # Taille et coût de la partie utilisateur
                user = @{
                    sizeGB = $sizeGB
                    pricePerMonthCHF = ( truncateToNbDecimal -number ($sizeGB /1024 * $TBPricePerMonth) -nbDecimals 2)
                }
                # Total
                totSizeGB =  ( truncateToNbDecimal -number $sizeWithSnapGB -nbDecimals 2)
                totPricePerMonthCHF = ( truncateToNbDecimal -number ($sizeWithSnapGB /1024 * $TBPricePerMonth) -nbDecimals 2)
            }

            
            # Ajout d'une chaine de caractère pour le prix
            $result.totPriceString = "Monthly price for {0}GB (= {1}CHF)" -f $sizeGB, $result.user.pricePerMonthCHF
            $result.totPriceStringSimple = "Monthly price: {0} CHF" -f $result.totPricePerMonthCHF
            if($snapPercent -gt 0)
            {
                $result.totPriceString = "{0} +{1}GB ({2}%) of snapshots, equal {3}GB (= {4}CHF)" -f `
                    $result.totPriceString, `
                    ( truncateToNbDecimal -number ($sizeWithSnapGB - $sizeGB) -nbDecimals 2), `
                    $snapPercent, `
                    ( truncateToNbDecimal -number $sizeWithSnapGB -nbDecimals 2), `
                    $result.snap.pricePerMonthCHF
            }
            $result.totPriceString = "{0}. Total= {1}CHF" -f $result.totPriceString, $result.totPricePerMonthCHF

            $output.results += $result
        }

    }# FIN EN fonction du type d'action demandé

    $logHistory.addLine("Script execution done!")

    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

    $logHistory.addLine($netapp.getFuncCallsDisplay("NetApp # func calls"))

}
catch
{

    # Récupération des infos
	$errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace
    
    # Si on était en train de créer un volume
    if(($action -eq $ACTION_CREATE) -and $cleaningCanBeDoneIfError)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating Volume '{0}', deleting it so everything is clean. Error was: {1}" -f $volName, $errorMessage))

        # Suppression du dossier monté s'il existe
        unMountPSDrive -driveLetter $global:XAAS_NAS_TEMPORARY_DRIVE

        try
        {
            deleteVolume -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -output $null
        }
        catch
        {
            $logHistory.addError(("Error while cleaning Volume: `nError: {0}`nTrace: {1}" -f $_.Exception.Message, $_.ScriptStackTrace))
        }
        
    }

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

if($null -ne $vra)
{
    $vra.disconnect()
}
