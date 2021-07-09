<#
USAGES:
    xaas-k8s-tools.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl -action robotReminder
    xaas-k8s-tools.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl -action delOldRobots
#>
<#
    BUT 		: Script contenant diverses commandes pour effectuer des actinos sur l'infrastructure K8s
                  

	DATE 	: Juin 2021
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

#>
param([string]$targetEnv,
      [string]$targetTenant,
      [string]$action)


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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "K8s", "functions.inc.ps1"))
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
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVra      = [ConfigReader]::New("config-vra.json")
$configK8s      = [ConfigReader]::New("config-xaas-k8s.json")
$configLdapAD   = [ConfigReader]::New("config-ldap-ad.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_ROBOT_REMINDER                          = "robotReminder"
$ACTION_DEL_OLD_ROBOTS                          = "delOldRobots"


# Nombre de jours à partir desquels (avant l'expiration d'un robot) on va commencer à envoyer un mail pour ceux qui vont disparaître
$BEFORE_EXPIRE_NB_DAYS_REMINDER                 = 7
# Durée après laquelle on peut supprimer un robot expiré
$OLD_ROBOTS_GRACE_PERIOD_DAYS                   = 7


# -------------------------------------------- FONCTIONS ---------------------------------------------------




# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new(@('xaas', 'k8s', 'tools'), $global:LOGS_FOLDER, 30)
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                        ($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)
                        
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

    # Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
    $nameGeneratorK8s = [NameGeneratorK8s]::new($targetEnv, $targetTenant)

    # Pour faire les recherches dans LDAP
	$ldap = [EPFLLDAP]::new($configLdapAd.getConfigValue(@("user")), $configLdapAd.getConfigValue(@("password")))      

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Création d'une connexion au serveur Harbor pour accéder à ses API REST
	$harbor = [HarborAPI]::new($configK8s.getConfigValue(@($targetEnv, "harbor", "server")),
            $configK8s.getConfigValue(@($targetEnv, "harbor", "user")),
            $configK8s.getConfigValue(@($targetEnv, "harbor", "password")),
            $ldap)


    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $vra.activateDebug($logHistory)
        $harbor.activateDebug($logHistory)        
    }

    # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $counters = [Counters]::new()
    

    $now = getUnixTimestamp

    # -------------------------------------------------------------------------
    # En fonction de l'action demandée
    switch ($action)
    {
        <#
        ----------------------------------
        ------------- CLUSTER ------------
        #>

        # --- Rappel sur les robots qui vont bientôt expirer
        $ACTION_ROBOT_REMINDER
        {
            Throw "To finalize !"
            # Pour savoir à quel BG est attaché chaque robot
            $bgToRobots = @{}

            $expireBeforeNbSec = ($BEFORE_EXPIRE_NB_DAYS_REMINDER * 24 * 60 * 60)

            $logHistory.addLineAndDisplay("Getting all robots list...")
            $robotList = $harbor.getRobotList()

            # Parcours des robots qui existent
            ForEach($robot in $robotList)
            {
                $logHistory.addLineAndDisplay((">> Robot '{0}'" -f $robot.name))
                
                $robotInfos = $nameGeneratorK8s.extractInfosFromRobotName($robot.name)
                
                $logHistory.addLineAndDisplay((">> Belongs to BG id '{0}'" -f $robotInfos.bgId))

                # Si le robot va expirer bientôt
                if(( $now -gt ($robotInfos.expirationTime - $expireBeforeNbSec)) -and ($now -lt $robotInfos.expirationTime))
                {
                    $logHistory.addLineAndDisplay((">> Robot will expire in less than {0} days" -f $BEFORE_EXPIRE_NB_DAYS_REMINDER))
                    # SI on n'a pas encore d'infos pour le BG du robot
                    if($bgToRobots.keys -notcontains $robotInfos.bgId)
                    {
                        # Ajout d'une liste vide
                        $bgToRobots.add($robotInfos.bgId, @())
                    }

                    $bgToRobots.($robotInfos.bgId) += $robotInfos

                }# FIN SI le robot expire bientôt

            } # FIN BOUCLE de parcours des robots

            $logHistory.addLineAndDisplay(("There is/are {0} BG with robots" -f $bgToRobots.Count))
            # Parcours des BG pour lequels on a des robots
            ForEach($bgId in $bgToRobots.keys)
            {
                $bg = $vra.getBGByCustomId($bgId)
                $logHistory.addLineAndDisplay(("> BG ID '{0}' => '{1}'" -f $bgId, $bg.name))

                $accessGroupList = @(getProjectAccessGroupList -project $bg -targetTenant $targetTenant)
                $logHistory.addLineAndDisplay(("> Access groups are:`n- {0}" -f ($accessGroupList -join '`n- ')))

                #TODO: Finaliser
                #$mailList =
            }

        }# FIN CASE rappel sur les robots qui vont bientôt expirer


        # --- Effacement des robots expirés depuis un certain temps
        $ACTION_DEL_OLD_ROBOTS
        {
            $counters.add('robots', '# total Robots')
            $counters.add('robotsDeleted', '# deleted Robots')
            $counters.add('robotsGracePeriod', '# Robots in grace period')

            $logHistory.addLineAndDisplay("Getting all robots list...")
            $robotList = $harbor.getRobotList()
            $logHistory.addLineAndDisplay(("{0} robot(s) found" -f $robotList.count))

            $counters.set('robots', $robotList.count)

            $gracePeriodNbSec = ($OLD_ROBOTS_GRACE_PERIOD_DAYS * 24 * 60 * 60)

            # Parcours des robots trouvés
            ForEach($robot in $robotList)
            {
                $logHistory.addLineAndDisplay(("> Robot '{0}'... " -f $robot.name))

                # Si le robot est expiré
                if($now -gt $robot.expires_at)
                {
                    # Si le robot a dépassé sa période de grâce
                    if($now -gt ($robot.expires_at + $gracePeriodNbSec))
                    {
                        $logHistory.addLineAndDisplay(("> Robos is expired and {0} days grace period over, deleting robot..." -f $OLD_ROBOTS_GRACE_PERIOD_DAYS))

                        $harbor.deleteRobot($robot)
                        $counters.inc('robotsDeleted')
                    }
                    else # Le robot est dans sa période de grâce
                    {
                        $logHistory.addLineAndDisplay(("> Robot is expired but in grace period"))
                        $counters.inc('robotsGracePeriod')
                    }

                }# FIN SI le robot est expiré

            }# FIN BOUCLE parcours des robots

        }

        default
        {

        }
    }

    $logHistory.addLine("Script execution done!")

    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

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
finally
{
    if($null -ne $vra)
    {
        $vra.disconnect()
    }
}


