<#
USAGES:
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType col -sizeGB <sizeGB> -bgName <bgName> -access cifs -svm <svm>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType col -sizeGB <sizeGB> -bgName <bgName> -access nfs3 -svm <svm> -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -volType app -sizeGB <sizeGB> -bgName <bgName> -access cifs|nfs3 -IPsRoot <IPsRoot> -IPsRO <IPsRO> -IPsRW <IPsRW> -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action delete -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action volExists -volName <volName>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action canHaveNewVol -bgName <bgName>
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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "NAS", "NameGeneratorNAS.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configNAS = [ConfigReader]::New("config-xaas-nas.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_DELETE              = "delete"
$ACTION_RESIZE              = "resize"
$ACTION_GET_SIZE            = "getVolSize"
$ACTION_GET_SVM_LIST        = "getSVMList"
$ACTION_VOL_EXISTS          = "volExists"
$ACTION_CAN_HAVE_NEW_VOL    = "canHaveNewVol"

# Type de volume
$global:VOL_TYPE_COLL       = "col"
$global:VOL_TYPE_APP        = "app"

# Limites
$global:MAX_VOL_PER_UNIT    = 10

# Autre
$global:EXPORT_POLICY_DENY_NFS_ON_CIFS = "deny_nfs_on_cifs"

# -------------------------------------------- CONSTANTES ---------------------------------------------------

<#
    -------------------------------------------------------------------------------------
    BUT : Retourne le prochain nom de volume utilisable

    IN  : $netapp           -> Objet de la classe NetAppAPI pour se connecter au NetApp
    IN  : $nameGeneratorNAS -> Objet de la classe NameGeneratorNAS
    IN  : $faculty          -> La faculté pour laquelle le volume sera
    IN  : $unit             -> L'unité pour laquelle le volume sera

    RET : Nouveau nom du volume
            $null si on a atteint le nombre max de volumes pour l'unité
#>
function getNextColVolName([NetAppAPI]$netapp, [NameGeneratorNAS]$nameGeneratorNAS, [string]$faculty, [string]$unit)
{
    $unit = $unit.toLower() -replace "-", ""
    $faculty = $faculty.toLower()
    $unitVolList = $netapp.getVolumeList() | Where-Object { $_ -match $nameGeneratorNAS.getCollaborativeVolRegex() } | Sort-Object

    # Recherche du prochain numéro libre
    for($i=1; $i -lt $global:MAX_VOL_PER_UNIT; $i++)
    {
        $curVolName = $nameGeneratorNAS.getVolName($i)
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
    $nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)
    
    $nameGeneratorNAS = [NameGeneratorNAS]::new()

    $netapp = $null

    # Parcours des serveurs qui sont définis
    $configNAS.getConfigValue($targetEnv, "serverList") | ForEach-Object {

        if($null -eq $netapp)
        {
            # Création de l'objet pour communiquer avec le NAS
            $netapp = [NetAppAPI]::new($_, $configNAS.getConfigValue($targetEnv, "user"), $configNAS.getConfigValue($targetEnv, "password"))
        }
        else
        {
            $netapp.addTargetServer($_)
        }
    }# Fin boucle de parcours des serveurs qui sont définis

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
                    # Chargement des informations sur le mapping des facultés
                    $appSVMFile = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "nas", "applicative-svm.json"))
                    $appSVMList = (Get-Content -Path $appSVMFile -raw) | ConvertFrom-Json

                    # Choix de la SVM
                    $logHistory.addLine("Choosing SVM for volume...")
                    $svmObj = chooseAppSVM -netapp $netapp -svmList = $appSVMList.$access
                    $logHistory.addLine( ("SVM will be '{0}'" -f $svmObj.name) )
                }

                # ---- Volume Collaboratif
                $global:VOL_TYPE_COLL
                {
                    # Récupération du nom de la faculté et de l'unité
                    $details = $nameGenerator.getDetailsFromBGName($bgName)

                    $nameGeneratorNAS.setCollaborativeDetails($details.faculty, $details.unit)

                    $logHistory.addLine( "Generating volume name..." )
                    # Recheche du prochain nom de volume
                    $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -faculty $details.faculty -unit $details.unit
                    $logHistory.addLine( ("New volume name will be '{0}'" -f $volName) )
                    if($null -eq $volName)
                    {
                        Throw ("Maximum number of volumes for unit ({0}) reached" -f $global:MAX_VOL_PER_UNIT)
                    }

                    # Recherche de la SVM
                    $svmObj = $netapp.getSVMByName($svm)
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

            $logHistory.addLine( ("Creating Volume {0} on SVM {1} and aggregate {2}..." -f $volName, $svmObj.name, $svmObj.aggregates[0].name) )

            # Définition du chemin de montage du volume
            $mountPath = "/{0}" -f $volName

            # Création du nouveau volume
            $newVol = $netapp.addVolume($volName, $sizeGB, $svmObj, $svmObj.aggregates[0], $securityStyle, $mountPath)

            # Pour le retour du script
            $result = @{
                volName = $volName
                sizeGB = $sizeGB
                svm = $svmObj.name
            }
            # Il faut mainteannt créer le nécessaire pour accéder au volume

            # En fonction du type d'accès qui a été demandé
            switch($access.toLower())
            {
                "cifs"
                {
                    $logHistory.addLine( ("Adding CIFS share '{0}' to point on '{1}'..." -f $volName, $mountPath) )
                    $netapp.addCIFSShare($volName, $svmObj, $mountPath)

                    # On ajoute le nom du share CIFS au résultat renvoyé par le script
                    $result.cifsShare = $volName

                    $logHistory.addLine(("Checking if Export Policy '{0}' exists on SVM '{1}'..." -f $global:EXPORT_POLICY_DENY_NFS_ON_CIFS, $svmObj.name))
                    $denyExportPol = $netapp.getExportPolicyByName($svmObj, $global:EXPORT_POLICY_DENY_NFS_ON_CIFS)

                    if($null -eq $denyExportPol)
                    {
                        $logHistory.addLine("Export Policy doesn't exists, creating...")
                        # Création de l'export policy
                        $denyExportPol = $netapp.addExportPolicy($global:EXPORT_POLICY_DENY_NFS_ON_CIFS, $svmObj)
                    }

                    $logHistory.addLine(("Applying Export Policy '{0}' to SVM '{1}' on Volume '{2}'" -f $global:EXPORT_POLICY_DENY_NFS_ON_CIFS, $svmObj.name, $volName))
                    $netapp.applyExportPolicyOnVolume($denyExportPol, $newVol)

                }

                "nfs3"
                {
                    
                }
            }


            $output.results += $result
           

        }# FIN Action Create


        # -- Effacement d'un Volume
        $ACTION_DELETE 
        {
            $logHistory.addLine( ("Getting Volume {0}..." -f $volName) )
            # Recherche du volume à effacer et effacement
            $vol = $netapp.getVolumeByName($volName)

            $logHistory.addLine( ("Getting SVM {0}..." -f $vol.svm.name) )
            $svmObj = $netapp.getSVMByID($vol.svm.uuid)

            $logHistory.addLine("Getting CIFS Shares for Volume...")
            $shareList = $netapp.getVolCIFSShareList($volName)
            $logHistory.addLine(("{0} CIFS shares found..." -f {$shareList.count}))

            # Suppression des shares CIFS
            ForEach($share in $shareList)
            {
                $logHistory.addLine( ("Deleting CIFS Share {0}..." -f $share.name) )
                $netapp.deleteCIFSShare($share)
            }

            $logHistory.addLine( ("Deleting Volume {0}" -f $volName) )
            $netapp.deleteVolume($vol.uuid)
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
            else
            {
                $logHistory.addLine( ("Resizing Volume {0} to {1} GB" -f $volName, $sizeGB) )
                $netapp.resizeVolume($vol.uuid, $sizeGB)
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

                $output.results += @{
                    volName = $vol.name
                    sizeGB = $vol.space.size / 1024 / 1024 / 1024
                }
            }

        }# FIN Action Delete


        # -- Renvoie la liste des SVM pour une faculté
        $ACTION_GET_SVM_LIST 
        {
            # Récupération du nom de la faculté et de l'unité
            $details = $nameGenerator.getDetailsFromBGName($bgName)
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
        $ACTION_VOL_EXISTS
        {
            $output.results += @{
                volName = $volName
                exists = ($null -ne $netapp.getVolumeByName($volName))
            }

        }


        # -- Pour savoir si une unité a le droit d'avoir un nouveau volume
        $ACTION_CAN_HAVE_NEW_VOL
        {
           
            # Récupération du nom de la faculté et de l'unité
            $details = $nameGenerator.getDetailsFromBGName($bgName)

            $nameGeneratorNAS.setCollaborativeDetails($details.faculty, $details.unit)

            $logHistory.addLine( "Looking for next volume name..." )
            # Recheche du prochain nom de volume
            $volName = getNextColVolName -netapp $netapp -nameGeneratorNAS $nameGeneratorNAS -faculty $details.faculty -unit $details.unit
            
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