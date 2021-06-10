<#
USAGES:
    xaas-nas-check-volume-use.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl [-sendNotifMail]
#>
<#
    BUT 		: Permettant de contrôler l'utilisation des volumes NAS et d'envoyer des mails aux
                admins si besoin.
                ATTENTION! Ce script ne fonctionne que pour les volumes qui sont onboardés dans vRA car
                            il n'y a que là que l'on a les infos sur les adresses de notification!
                  

	DATE 	: Juin 2021
    AUTEUR 	: Lucien Chaboudez
    
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
      [switch]$sendNotifMail)

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

$PERCENT_WARNING_USAGE  = 80
$PERCENT_CRITICAL_USAGE = 90

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
    $logHistory = [LogHistory]::new(@('xaas','nas', 'check-volume-use'), $global:LOGS_FOLDER, 120)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

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


    # S'il a été demandé d'envoyer des mails
    if($sendNotifMail)
    {
        $mailFrom = ("noreply+{0}" -f $configGlobal.getConfigValue(@("mail", "admin")))
        # Template pour le sujet et le contenu du mail
        $mailSubjectTemplate = "[IaaS] NAS - {{usageStatus}} - Volume {{volName}} usage is between {{percentUsageMin}}% and {{percentUsageMax}}%"
        $mailMessageTemplate = (Get-Content -Raw -Path ( Join-Path $global:NAS_MAIL_TEMPLATE_FOLDER "volume-use.html" ) -Encoding:UTF8)
    }

    $BGList = $vra.getBGList()

    # Parcours des BG
    Foreach($bg in $BGList)
    {
        
        $logHistory.addLineAndDisplay(("Processing BG '{0}'..." -f $bg.name))

        $logHistory.addLineAndDisplay("> Getting volumes list...")

        $volList = $vra.getBGItemList($bg, $global:VRA_XAAS_NAS_DYNAMIC_TYPE)

        $volNo = 1
        ForEach($vol in $volList)
        {
            $logHistory.addLineAndDisplay(("> [{0}/{1}] Volume {2}..." -f $volNo, $volList.count, $vol.name))

            # Recherche des infos du volume directement sur le NAS
            $netAppVol = $netapp.getVolumeByName($vol.name)

            # Si par hasard le volume n'a pas été trouvé
            if($null -eq $netAppVol)
            {
                $logHistory.addWarningAndDisplay(("> Volume '{0}' exists on vRA but not on NAS" -f $vol.name))
            }
            else # Le volume existe bel et bien sur le NAS
            {
                $usagePercent = truncateToNbDecimal -number ($netAppVol.space.used / $netAppVol.space.size * 100) -nbDecimals 1

                $usageColor = $null

                # Si utilisation critique
                if($usagePercent -ge $PERCENT_CRITICAL_USAGE)
                {
                    $usageColor = "#e61717"
                    $usageStatus = "CRITICAL"
                    $percentUsageMin = $PERCENT_CRITICAL_USAGE
                    $percentUsageMax = 100
                }
                # Utilisation Warning
                elseif($usagePercent -ge $PERCENT_WARNING_USAGE)
                {
                    $usageColor = "#fca50d"
                    $usageStatus = "WARNING"
                    $percentUsageMin = $PERCENT_WARNING_USAGE
                    $percentUsageMax = $PERCENT_CRITICAL_USAGE
                }

                # Si le volume a une utilisation élevée
                if($null -ne $usageColor)
                {
                    $logHistory.addLineAndDisplay(("-> Usage is {0} ({1} %)" -f $usageStatus, $usagePercent))

                    if($sendNotifMail)
                    {
                        $logHistory.addLineAndDisplay(("-> Getting notification mails..."))

                        $mailList = getvRAObjectNotifMailList -vraObj $vol -mailPropName "notificationMail"

                        # Définition des valeurs à remplacer dans le mail et son sujet
                        $valToReplace = @{
                            color = $usageColor
                            volName = $vol.name
                            percentUsed = $usagePercent
                            usedGB = (truncateToNbDecimal -number ($netAppVol.space.used / 1024 / 1024 / 1024) -nbDecimals 2)
                            totGB = (truncateToNbDecimal -number ($netAppVol.space.size / 1024 / 1024 / 1024) -nbDecimals 2)
                            usageStatus = $usageStatus
                            percentUsageMin = $percentUsageMin
                            percentUsageMax = $percentUsageMax
                        }

                        # Création du sujet du mail ainsi que du message
                        $mailSubject, $mailMessage = replaceInStrings -stringList @($mailSubjectTemplate, $mailMessageTemplate) -valToReplace $valToReplace

                        ForEach($mailTo in $mailList)
                        {
                            $logHistory.addLineAndDisplay(("--> Sending mail to {0}" -f $mailTo))
                            Send-MailMessage -From $mailFrom -to $mailTo -Subject $mailSubject  `
                                -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding:UTF8
                        }

                        # Pour ne pas faire de spam
                        Start-Sleep -Milliseconds 500

                    } # FIN S'il faut envoyer le mail
            
                }# FIN SI le volume a une utilisation élevée 

            }# FIN SI Le volume existe sur le NAS

            $volNo++

            #break
        }# FIN BOUCLE de parcours des volumes du BG

    }# FIN BOUCLE de parcours des BG

    $logHistory.addLineAndDisplay("Script execution done!")

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

if($null -ne $vra)
{
    $vra.disconnect()
}
