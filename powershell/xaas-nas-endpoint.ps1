<#
USAGES:
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType col -sizeGB <sizeGB> -bgName <bgName> -access cifs -svm <svm>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType col -sizeGB <sizeGB> -bgName <bgName> -access nfs3 -svm <svm> -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType app -sizeGB <sizeGB> -bgName <bgName> -access cifs|nfs3 -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW> -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action delete -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action appVolExists -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action canHaveNewVol -bgName <bgName> -access cifs|nfs3
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action resize -sizeGB <sizeGB>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action getVolSize [-volName <volName>]
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action getSVMList -bgName <bgName>
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
      [string]$bgName,
      # Volume
      [string]$volName,
      [int]$sizeGB,
      # Accès
      [string]$access,
      [string]$IPsRoot,
      [string]$IPsRW,
      [string]$IPsRO)

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

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "NameGeneratorNAS.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))


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

$global:APP_VOL_DEFAULT_FAC = "si"

# Type de volume
$global:VOL_TYPE_COLL       = "col"
$global:VOL_TYPE_APP        = "app"

$global:ACCESS_TYPE_CIFS    = "cifs"
$global:ACCESS_TYPE_NFS3    = "nfs3"

# Limites
$global:MAX_VOL_PER_UNIT    = 10

# Autre
$global:EXPORT_POLICY_DENY_NFS_ON_CIFS = "deny_nfs_on_cifs"
$global:SNAPSHOT_POLICY = "epfl-default"
$global:SNAPSHOT_SPACE_PERCENT = 30

# -------------------------------------------- CONSTANTES ---------------------------------------------------

<#
    -------------------------------------------------------------------------------------
    BUT : Retourne le prochain nom de volume utilisable

    IN  : $netapp           -> Objet de la classe NetAppAPI pour se connecter au NetApp
    IN  : $nameGeneratorNAS -> Objet de la classe NameGeneratorNAS
    IN  : $faculty          -> La faculté pour laquelle le volume sera
    IN  : $unit             -> L'unité pour laquelle le volume sera
    IN  : $access           -> le type d'accès
                                $global:ACCESS_TYPE_CIFS
                                $global:ACCESS_TYPE_NFS3

    RET : Nouveau nom du volume
            $null si on a atteint le nombre max de volumes pour l'unité
#>
function getNextColVolName([NetAppAPI]$netapp, [NameGeneratorNAS]$nameGeneratorNAS, [string]$faculty, [string]$unit, [string]$access)
{
    $unit = $unit.toLower() -replace "-", ""
    $faculty = $faculty.toLower()

    $isNFS = ($access -eq $global:ACCESS_TYPE_NFS3)

    # Définition de la regex pour trouver les noms de volumes
    $volNameRegex = $nameGeneratorNAS.getCollaborativeVolRegex($isNFS)
    $unitVolList = $netapp.getVolumeList() | Where-Object { $_ -match $volNameRegex } | Sort-Object | Select-Object -ExpandProperty name

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

    RET : Objet représentant la SVM
#>
function chooseAppSVM([NetAppAPI]$netapp, [Array]$svmList)
{
    $lessCharged = $null
    $targetSVM = $null
    # Parcours des SVM
    ForEach($svmName in $svmList)
    {
        # Recherche des infos de la SVM puis de son aggregat
        $svm = $netapp.getSVMByName($svmName)

        # Si la SVM n'a pas été trouvée, il doit y avoir une erreur dans le fichier de données
        if($null -eq $svm)
        {
            Throw ("Defined applicative SVM ({0}) not found. Please check 'data/xaas/nas/applicatives-svm.json' content")
        }

        $aggr = $netapp.getAggregateById($svm.aggregates[0].uuid)

        # Si l'aggregat courant est moins utilisé
        if( ($null -eq $lessCharged) -or ($aggr.space.block_storage.used -lt $lessCharged.space.block_storage.used))
        {
            $lessCharged = $aggr
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
    $vol = $netapp.getVolumeByName($volumeName)

    # Si le volume n'existe pas
    if($null -eq $vol)
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
        $logHistory.addLine( ("Getting SVM '{0}'..." -f $vol.svm.name) )
        $svmObj = $netapp.getSVMByID($vol.svm.uuid)

        $logHistory.addLine("Getting CIFS Shares for Volume...")
        $shareList = $netapp.getVolCIFSShareList($volumeName)
        $logHistory.addLine(("{0} CIFS shares found..." -f $shareList.count))

        # Suppression des shares CIFS
        ForEach($share in $shareList)
        {
            $logHistory.addLine( ("Deleting CIFS Share '{0}'..." -f $share.name) )
            $netapp.deleteCIFSShare($share)
        }

        $logHistory.addLine( ("Deleting Volume {0}" -f $volumeName) )
        $netapp.deleteVolume($vol.uuid)

        # Export Policy (on la supprime tout à la fin sinon on se prend une erreur "gnagna elles utilisée par le volume"
        # donc on vire le volume ET ENSUITE l'export policy)
        $exportPolicyName = $nameGeneratorNAS.getExportPolicyName($volumeName)
        $logHistory.addLine(("Getting NFS export policy '{0}'"))
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
    BUT : Ajoute une export policy pour un volume avec les règles adéquates

    IN  : $nameGeneratorNAS ->  Objet pour générer les noms pour le NAS
    IN  : $netapp       -> Objet de la classe NetAPPAPI permettant d'accéder au NAS
    IN  : $volumeName   -> Nom du volume à effacer
    IN  : $svmObj       -> Objet représentant la SVM sur laquelle ajouter l'export policy
    IN  : $IPsRO        -> Chaine de caractères avec les IP RO
    IN  : $IPsRW        -> Chaine de caractères avec les IP RW
    IN  : $IPsRoot      -> Chaine de caractères avec les IP Root
    IN  : $protocol     -> Le protocole d'accès ([NetAppProtocol])
    IN  : $result       -> Objet représentant l'output du script. Peut être $null
                            si on n'a pas envie de le modifier

    RET : Tableau avec :
            - l'export policy ajoutée
            - l'objet renvoyé par le script (JSON) avec les infos du point de montage
#>
function addNFSExportPolicy([NameGeneratorNAS]$nameGeneratorNAS, [NetAppAPI]$netapp, [string]$volumeName, [PSObject]$svmObj, [string]$IPsRO, [string]$IPsRW, [string]$IPsRoot, [string]$protocol, [PSObject]$result)
{
    $exportPolicyName = $nameGeneratorNAS.getExportPolicyName($volumeName)

    $logHistory.addLine(("Creating export policy '{0}'..." -f $exportPolicyName))
    # Création de l'export policy 
    $exportPolicy = $netapp.addExportPolicy($exportPolicyName, $svmObj)

    $logHistory.addLine("Add rules to export policy...")
    $netapp.updateExportPolicyRules($exportPolicy, ($IPsRO -split ","), ($IPsRW -split ","), ($IPsRoot -split ","), $protocol)

    # On ajoute le nom du share CIFS au résultat renvoyé par le script
    $result.mountPath = ("{0}:/{1}" -f $svmObj.name, $volumeName)

    return @($exportPolicy, $result)
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
    $logHistory = [LogHistory]::new('xaas-nas', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
    $nameGeneratorNAS = [NameGeneratorNAS]::new($targetEnv, $targetTenant)

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "infra", "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "user"), 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "password"))

    # Création de l'objet pour se connecter aux clusters NetApp
    $netapp = [NetAppAPI]::new($configNAS.getConfigValue($targetEnv, "serverList"), `
                                $configNAS.getConfigValue($targetEnv, "user"), `
                                $configNAS.getConfigValue($targetEnv, "password"))

    # Objet pour pouvoir envoyer des mails de notification
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)

    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_CREATE 
        {

            # En fonction du type de volume
            switch($volType)
            {
                # ---- Volume Applicatif
                $global:VOL_TYPE_APP
                {
                    $nameGeneratorNAS.setApplicativeDetails($global:APP_VOL_DEFAULT_FAC, $volName)

                    # Chargement des informations sur le mapping des facultés
                    $appSVMFile = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "nas", "applicative-svm.json"))
                    $appSVMList = (Get-Content -Path $appSVMFile -raw) | ConvertFrom-Json

                    # Choix de la SVM
                    $logHistory.addLine("Choosing SVM for volume...")
                    $svmObj = chooseAppSVM -netapp $netapp -svmList $appSVMList.($targetEnv.ToLower()).($access.ToLower())
                    $logHistory.addLine( ("SVM will be '{0}'" -f $svmObj.name) )

                    # Pas d'espace réservé pour les snapshots
                    $snapSpacePercent = 0

                    # Génération du "nouveau" nom du volume
                    $volName = $nameGeneratorNAS.getVolName()
                    $logHistory.addLine(("Final Volume name will be '{0}'" -f $volName))
                }

                # ---- Volume Collaboratif
                $global:VOL_TYPE_COLL
                {
                    # Initialisation des détails
                    $nameGeneratorNAS.setCollaborativeDetails($bgName)

                    $logHistory.addLine( "Generating volume name..." )
                    # Recheche du prochain nom de volume
                    $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -faculty $details.faculty -unit $details.unit -access $access
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

                    # Il faut qu'on mette les snapshot en place
                    $logHistory.addLine("Getting Snapshot Policy...")
                    $snapPolicy = $netapp.getSnapshotPolicyByName($global:SNAPSHOT_POLICY)
                    # Si on ne trouve pas la policy de snapshot,
                    if($null -eq $snapPolicy)
                    {
                        Throw ("Snapshot policy '{0}' doesn't exists" -f $global:SNAPSHOT_POLICY)
                    }

                    $snapSpacePercent = $global:SNAPSHOT_SPACE_PERCENT

                }

                default
                {
                    Throw ("Incorrect parameter given for 'volType' ({0})" -f $volType)
                }
            } # FIN en fonction du type de volume

            # En fonction du type d'accès qui a été demandé
            switch($access.toLower())
            {
                "cifs"
                {
                    $securityStyle = "ntfs"
                }

                "nfs3"
                {
                    $securityStyle = "unix"
                }
            }

            # -----------------------------------------------
            # 1. Création du volume

            $logHistory.addLine( ("Creating Volume {0} on SVM {1} and aggregate {2}..." -f $volName, $svmObj.name, $svmObj.aggregates[0].name) )

            # Définition du chemin de montage du volume
            $mountPath = "/{0}" -f $volName

            # Redéfinition de la taille du volume en fonction du pourcentage à conserver pour les snapshots
            $sizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB $sizeGB -snapSpacePercent $snapSpacePercent

            # Création du nouveau volume
            $newVol = $netapp.addVolume($volName, $sizeWithSnapGB, $svmObj, $svmObj.aggregates[0], $securityStyle, $mountPath, $snapSpacePercent)

            # Pour le retour du script
            $result = @{
                volName = $volName
                sizeGB = $sizeGB
                svm = $svmObj.name
            }
            # Il faut mainteannt créer le nécessaire pour accéder au volume


            # -----------------------------------------------
            # 2. Mise en place des accès

            # En fonction du type d'accès qui a été demandé
            switch($access.toLower())
            {
                # ------------ CIFS
                "cifs"
                {
                    $logHistory.addLine( ("Adding CIFS share '{0}' to point on '{1}'..." -f $volName, $mountPath) )
                    $netapp.addCIFSShare($volName, $svmObj, $mountPath)

                    # On ajoute le nom du share CIFS au résultat renvoyé par le script
                    $result.mountPath = ("\\{0}\{1}" -f $svm, $volName)

                    # En fonction du type de volume
                    switch($volType)
                    {
                        # ---- Volume Applicatif
                        $global:VOL_TYPE_APP
                        {
                            # Ajout de l'export policy
                            $exportPol, $result = addNFSExportPolicy -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -svmObj $svmObj `
                                                        -IPsRO $IPsRO -IPsRW $IPsRW -IPsRoot $IPsRoot -protocol $access.ToLower() -result $result
                        }

                        # ---- Volume Collaboratif
                        $global:VOL_TYPE_COLL
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

                            # Recherche du Business Group
                            $bg = $vra.getBG($bgName)
                            # Récupération des utilisateurs qui ont le droit de demander des volumes
                            $userAndGroupList = $vra.getBGRoleContent($bg.id, "CSP_CONSUMER")

                            # Récupération des ACLs actuelles
                            $acl = Get-ACL $result.mountPath
                            
                            # Parcours des utilisateurs/groupes à ajouter
                            ForEach($userOrGroupFQDN in $userAndGroupList)
                            {
                                # $userOrGroup contient un groupe ou un utilisateur au format <userOrGroup>@intranet.epfl.ch.
                                # Il faut donc reformater ceci pour avoir INTRANET\<userOrGroup>
                                $userOrGroup, $null = $userOrGroupFQDN -split '@'
                                $userOrGroup = "INTRANET\{0}" -f $userOrGroup
                                $ar = New-Object  system.security.accesscontrol.filesystemaccessrule($userOrGroup,  "FullControl", "ContainerInherit,ObjectInherit",  "None", "Allow")
                                $acl.AddAccessRule($ar)
                            }

                            Set-Acl $result.mountPath $acl
                            # On vire les accès Everyone (on ne peut pas le faire avant sinon on se coupe l'herbe sous le pied pour ce qui est de l'établissement des droits)
                            $acl.access | Where-Object { $_.IdentityReference -eq "Everyone"} | ForEach-Object { $acl.RemoveAccessRule($_)} | Out-Null
                            # Et on fini par mettre à jour sans les Everyone
                            Set-Acl $result.mountPath $acl
                        }
                    }# FIN EN FONCTION du type de volume
                    
                }


                # ------------ NFS
                "nfs3"
                {
                    # Ajout de l'export policy
                    $exportPol, $result = addNFSExportPolicy -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -svmObj $svmObj `
                                                -IPsRO $IPsRO -IPsRW $IPsRW -IPsRoot $IPsRoot -protocol $access.ToLower() -result $result
                }
            }# FIN En fonction du type d'accès demandé 

            $logHistory.addLine(("Applying Export Policy '{0}' to SVM '{1}' on Volume '{2}'" -f $exportPol.name, $svmObj.name, $volName))
            $netapp.applyExportPolicyOnVolume($exportPol, $newVol)

            # -----------------------------------------------
            # 3. Politique de snapshot

            # Si volume collaboratif
            if($volType -eq $global:VOL_TYPE_COLL)
            {
                # On applique la policy de snapshot
                $logHistory.addLine(("Applying Snapshot Policy '{0}' on Volume '{1}'" -f $global:SNAPSHOT_POLICY, $volName))
                $netapp.applySnapshotPolicyOnVolume($snapPolicy, $newVol)
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
            $vol = $netapp.getVolumeByName($volName)
            
            # Si volume pas trouvé
            if($null -eq $vol)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else # Volume trouvéc
            {
                # Recherche des infos sur les snapshots
                $volSizeInfos = $netapp.getVolumeSnapshotInfos($vol)

                # Redéfinition de la taille du volume en fonction du pourcentage à conserver pour les snapshots
                $sizeWithSnapGB = getCorrectVolumeSize -requestedSizeGB $sizeGB -snapSpacePercent $volSizeInfos.space.snapshot.reserve_percent

                $logHistory.addLine( ("Resizing Volume {0} to {1} GB" -f $volName, $sizeGB) )
                $netapp.resizeVolume($vol.uuid, $sizeWithSnapGB)
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
                $vol = $netapp.getVolumeByName($_)

                # Si volume pas trouvé, c'est qu'on a probablement donné un nom unique en paramètre
                if($null -eq $vol)
                {
                    $output.error = ("Volume {0} doesn't exists" -f $_)
                    $logHistory.addLine($output.error)
                    return
                }

                $volSizeInfos = $netapp.getVolumeSizeInfos($vol)

                $volSizeGB = $vol.space.size / 1024 / 1024 / 1024
                # Suppression de l'espace réservé pour les snapshots
                $userSizeGB = $volSizeGB * (1 - ($volSizeInfos.space.snapshot.reserve_percent/100))
                $snapSizeGB = $volSizeGB * ($volSizeInfos.space.snapshot.reserve_percent/100)

                $output.results += @{
                    volName = $vol.name
                    user = @{
                        sizeGB = (truncateToNbDecimal -number $userSizeGB -nbDecimals 2)
                        usedGB = (truncateToNbDecimal -number ($vol.space.used / 1024 / 1024 / 1024) -nbDecimals 2)
                        usedFiles = $volSizeInfos.files.used
                        maxFiles = $volSizeInfos.files.maximum
                    }
                    snap = @{
                        reservePercent = $volSizeInfos.space.snapshot.reserve_percent
                        reserveSizeGB = (truncateToNbDecimal -number $snapSizeGB -nbDecimals 2)
                        usedGB = (truncateToNbDecimal -number ($volSizeInfos.space.snapshot.used / 1024 / 1024 / 1024) -nbDecimals 2)
                    }
                }
            }

        }# FIN Action Delete


        # -- Renvoie la liste des SVM pour une faculté
        $ACTION_GET_SVM_LIST 
        {
            # Récupération du nom de la faculté et de l'unité
            $details = $nameGeneratorNAS.getDetailsFromBGName($bgName)
            $faculty = $details.faculty

            # Chargement des informations sur le mapping des facultés
            $facultyMappingFile = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "nas", "faculty-mapping.json"))
            $facultyMappingList = (Get-Content -Path $facultyMappingFile -raw) | ConvertFrom-Json

            # Chargement des informations 
            $facultyToSVMFile = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "nas", "faculty-to-svm.json"))
            $facultyToSVM = (Get-Content -Path $facultyToSVMFile -raw) | ConvertFrom-Json

            # On commence par regarder s'il y a un mapping pour la faculté donnée
            $targetFaculty = $faculty
            Foreach($facMapping in $facultyMappingList)
            {
                if($facMapping.fromFac.toLower() -eq $faculty.toLower())
                {
                    $targetFaculty = $facMapping.toFac
                    break
                }
            }
            
            # Liste des SVM pour la faculté (avec la bonne nommenclature)
            $svmList = $netapp.getSVMList() | Where-Object { $_.name -match ('^{0}[0-9].*' -f $targetFaculty)}
            
            # Si on a une liste hard-codée de SVM pour la faculté
            if([bool]($facultyToSVM.PSobject.Properties.name.toLower() -eq $faculty.toLower()))
            {
                # On ajoute la liste hard-codée
                $svmList += $facultyToSVM.$faculty
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
            $nameGeneratorNAS.setApplicativeDetails($global:APP_VOL_DEFAULT_FAC, $volName)
                
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
           
            $nameGeneratorNAS.setCollaborativeDetails($bgName)

            $logHistory.addLine( "Looking for next volume name..." )
            # Recheche du prochain nom de volume
            $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -faculty $details.faculty -unit $details.unit -access $access
            $logHistory.addLine( ("Next volume name is '{0}'" ) -f $volName)
            $output.results += @{
                canHaveNewVol = ($null -ne $volName)
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

    # Si on était en train de créer un volume
    if($action -eq $ACTION_CREATE)
    {
        # On efface celui-ci pour ne rien garder qui "traine"
        $logHistory.addLine(("Error while creating Volume '{0}', deleting it so everything is clean" -f $volName))
        deleteVolume -nameGeneratorNAS $nameGeneratorNAS -netapp $netapp -volumeName $volName -output $null
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