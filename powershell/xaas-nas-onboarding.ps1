<#
USAGES:
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action genDataFile -volType col|app -dataFile <dataFile>
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action import -volType col|app -dataFile <dataFile>
#>
<#
    BUT 		: Script permettant d'effectuer le onboarding des volumes NAS
                  

	DATE 	: Mars 2021
    AUTEUR 	: Lucien Chaboudez
    
#>
param([string]$targetEnv, 
      [string]$targetTenant,
      [string]$action,
      [string]$volType,
      [string]$dataFile)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))
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
$configvRA = [ConfigReader]::New("config-vra.json")
$configNAS = [ConfigReader]::New("config-xaas-nas.json")



# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_GEN_DATA_FILE       = "genDataFile"
$ACTION_IMPORT              = "import"

$CSV_SEPARATOR = ";"

$XAAS_NAS_ONBOARD_COLL_CATALOG_ITEM =  "NAS(C) Onboard"


# -------------------------------------------- FONCTIONS ---------------------------------------------------

function getVolToOnboard([SQLDB]$sqldb, [string]$volType)
{

    $volTypeIdList = switch($volType) 
    {
        "col"{ @(2,4,5)}
        "app"{ @(1) }
    }

    $tables = @(
        "nas_fs",
        "infra_vserver",
        "nas_service_type",
        "nas_fs_admin_mail"
    )

    $conditions = @(
        "nas_fs.infra_vserver_id = infra_vserver.infra_vserver_id",
        "nas_fs.nas_fs_svc_type_id = nas_service_type.nas_svc_type_id",
        "nas_fs.nas_fs_date_delete_asked IS NULL",
        ("nas_fs_svc_type_id IN ({0})" -f ($volTypeIdList -join ",")),
        "nas_fs.nas_fs_name NOT IN (SELECT vol_name FROM nas2020_onboarding)",
        "nas_fs.nas_fs_id=nas_fs_admin_mail.nas_fs_id"
    )

    $columns = @(
        "nas_fs.*",
        "nas_service_type.nas_svc_type_name",
        "infra_vserver.infra_vserver_name",
        "GROUP_CONCAT(nas_fs_admin_mail.nas_fs_admin_mail)AS mailList"
    )

    
    $request = ("SELECT {0} FROM {1} WHERE {2} GROUP BY nas_fs_admin_mail.nas_fs_id ORDER BY nas_fs_unit,infra_vserver_name,nas_fs_name " -f `
                ($columns -join ","), ($tables -join ","), ($conditions -join " AND "))

    $list = $sqldb.execute($request)                


    return $list
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
    $logHistory = [LogHistory]::new(@('xaas','nas', 'onboarding'), $global:LOGS_FOLDER, 30)
    
    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
    }
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                    ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Création de l'objet pour se connecter aux clusters NetApp
    $netapp = [NetAppAPI]::new($configNAS.getConfigValue(@($targetEnv, "serverList")),
                                $configNAS.getConfigValue(@($targetEnv, "user")),
                                $configNAS.getConfigValue(@($targetEnv, "password")))



    # Pour accéder à la base de données
	$sqldb = [SQLDB]::new([DBType]::MySQL,
                        $configNAS.getConfigValue(@("webisteDB", "host")),
                        $configNAS.getConfigValue(@("webisteDB", "dbName")),
                        $configNAS.getConfigValue(@("webisteDB", "user")),
                        $configNAS.getConfigValue(@("webisteDB", "password")),
                        $configNAS.getConfigValue(@("webisteDB", "port")), $false)                                

    $logHistory.addLineAndDisplay("Connecting to vRA...")
    $vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                            $targetTenant, 
                            $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                            $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $netapp.activateDebug($logHistory)    
    }

    

    #$dataFile = ([IO.Path]::Combine("$PSScriptRoot", $dataFile))
    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_GEN_DATA_FILE 
        {
            Write-Host -NoNewLine "Getting volume list... "
            $volList = getVolToOnboard -sqldb $sqldb -volType $volType
            Write-Host "done" -foregroundColor:DarkGreen

            $cols = @(
                @("nas3VolName", "nas_fs_name"),
                @("unitId", "nas_fs_unit"),
                @("Rattachement", "nas_fs_rattachement"),
                @("vServer", "infra_vserver_name"),
                @("SizeGB", "nas_fs_quota_gb"),
                @("Mail List", "mailList"), 
                "nas2020VolName",
                "Owner (user@intranet.epfl.ch)",
                "targetTenantName",
                "targetBgName")

            (($cols | ForEach-Object{@($_)[0]}) -join $CSV_SEPARATOR) | Out-File $dataFile -Encoding:utf8

            Write-Host -NoNewLine "Extracting data... " 
            # Parcours des volumes récupérés
            Foreach($vol in $volList)
            {
                $valList = @()

                $cols | ForEach-Object {
                    $tag, $dbCol = $_
                    if($null -eq $dbCol)
                    {
                        $val = ""
                    }
                    else
                    {
                        $val = $vol.$dbCol
                    }

                    $valList += $val
                }

                ($valList -join $CSV_SEPARATOR) | Out-File $dataFile -Encoding:utf8 -append
            }
            Write-Host "done" -foregroundColor:DarkGreen

            Write-Host ("Output can be found in '{0}' file" -f $dataFile)
        }


        # -- Importation depuis un fichier de données
        $ACTION_IMPORT
        {
            $catalogItemName = Switch($volType)
            {
                "col" { $XAAS_NAS_ONBOARD_COLL_CATALOG_ITEM }
                "app" { Throw "Not handled"}
            }
        

            $catalogItem = $vra.getCatalogItem($catalogItemName)

            if($null -eq $catalogItem)
            {
                Throw ("Catalog Item '{0}' not found on {1}::{2}" -f $catalogItemName, $targetEnv.toUpper(), $targetTenant)
            }

            $bg = $vra.getBG("epfl_vposi_itop_sddc")


            $template = $vra.getCatalogItemRequestTemplate($catalogItem, $bg, "chaboude@intranet.epfl.ch")

            $template
        }

    }


}
catch
{

    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace


    $logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))

    if($null -ne $vra)
    {
        $vra.disconnect()
    }

    Throw
}

if($null -ne $vra)
{
    $vra.disconnect()
}
                                                