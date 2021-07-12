<#
USAGES:
    tools-send-approval-reminder.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research
#>
<#
    BUT 		: Récupère la liste des requêtes en attente d'approbation depuis X heures et 
                    fait une relance par mail aux approbateurs avec le demandeur en copie
                  

	DATE 	: Avril 2021
    AUTEUR 	: Lucien Chaboudez
    

#>
param ( [string]$targetEnv, 
        [string]$targetTenant)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "SnowAPI.inc.ps1"))

Throw ("To finalize")

# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVra      = [ConfigReader]::New("config-vra.json")

# Le nombre de jours au bout desquels on se permet d'envoyer un mail pour rappeler qu'il faut approuver
$NB_DAYS_REMINDER_DEADLINE = 4

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logPath = @('tools', ('send-approval-reminder-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.toLower()))
    $logHistory = [LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
        targetEnv = $targetEnv
        targetTenant = $targetTenant
    }

    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                ($global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT -f $targetEnv), $valToReplace)


    $logHistory.addLineAndDisplay("Connecting to vRA...")
    $vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))


    $logHistory.addLineAndDisplay("Getting waiting requests list...")

    $waitingRequestList = $vra.getWaitingCatalogItemRequest()

    $logHistory.addLineAndDisplay(("{0} request found" -f $waitingRequestList.count))

    $aMomentInThePast = (Get-Date).addDays(-$NB_DAYS_REMINDER_DEADLINE)

    # Parcours des requêtes
    ForEach($waitingRequest in $waitingRequestList)
    {
        $logHistory.addLineAndDisplay(("-> Request '{0}' for Item '{1}'..." -f $waitingRequest.id, $waitingRequest.requestedItemName))
        <# Il peut arriver (cas rare mais vu en test...) que des requêtes soient encore en attente pour un BG qui n'existe plus.
        Elles ne sont donc pas visibles dans la console Web mais seulement via REST. Et il est impossible de les annuler ou autre donc... 
        Du coup, elles seront renvoyées dans la liste des requêtes en attente. On va simplement regarder si le BG auquel elles sont
        liées existe encore et si c'est le cas, on ira plus loin dans le processus. #>
        if($null -ne ($vra.getBGById($waitingRequest.organization.subtenantRef)))
        {
            $lastUpdate = [DateTime]::Parse($waitingRequest.lastUpdated)

            $logHistory.addLineAndDisplay(("--> Last request update was: {0}" -f $lastUpdate))
            # Si la dernière mise à jour de la requête date de plus de $NB_DAYS_REMINDER_DEADLINE jours
            if($lastUpdate -lt $aMomentInThePast)
            {
                $waitingRequest.preapprovalId
            }
            else
            {
                $logHistory.addLineAndDisplay("--> Not waited long enough, skipping!")
            }

        }
        else # Le BG n'existe plus
        {
            $logHistory.addLineAndDisplay("--> Parent Business Group doesn't exists anymore, skipping!")
        }

        
    }
    
}
catch
{
    
    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace

    $logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
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

