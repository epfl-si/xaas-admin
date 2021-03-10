<#
USAGES:
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action genDataFile -dataFile <dataFile>
    xaas-nas-onboarding.ps1 -targetEnv prod|test|dev -targetTenant epfl|research -action import -dataFile <dataFile>
#>
<#
    BUT 		: Script permettant d'effectuer le onboarding des volumes NAS
                  

	DATE 	: Mars 2021
    AUTEUR 	: Lucien Chaboudez
    
#>
param([string]$targetEnv, 
      [string]$targetTenant,
      [string]$action,
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
$configNAS = [ConfigReader]::New("config-xaas-nas.json")



# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_GEN_DATA_FILE       = "genDataFile"
$ACTION_IMPORT              = "import"


# -------------------------------------------- FONCTIONS ---------------------------------------------------

function getVolToOnboard([SQLDB]$sqldb)
{
    $conditions = @(
        "nas_fs.infra_vserver_id = infra_vserver.infra_vserver_id"
        "nas_fs.nas_fs_date_delete_asked IS NULL",
        "nas_fs.nas_fs_name NOT IN (SELECT vol_name FROM nas2020_onboarding)"
    )

    $columns = @(
        "nas_fs.*",
        "infra_vserver.infra_vserver_name"
    )

    $request = ("SELECT {0} FROM nas_fs, infra_vserver WHERE {1} ORDER BY nas_fs_unit,infra_vserver_name,nas_fs_name" -f `
                ($columns -join ","), ($conditions -join " AND "))

    $list = $sqldb.execute($request)                

    $list
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
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
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
                        $configNAS.getConfigValue(@("webisteDB", "port")))                                

    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $netapp.activateDebug($logHistory)    
    }

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
    }
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                    ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)



    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_GEN_DATA_FILE 
        {
            $list = getVolToOnboard -sqldb $sqldb
        }


        # -- Importation depuis un fichier de données
        $ACTION_IMPORT
        {

        }

    }


}
catch
{

    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace


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
                                                