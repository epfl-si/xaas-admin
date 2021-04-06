<#
USAGES:
    xaas-avi-networks-e2e.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research
 
#>
<#
    BUT : Permet de mettre à jour le End-2-End monitoring avec le statut des Virtual Service et Pool
            de AVI Networks.
            Ce script est conçu pour être exécuté toutes les X minutes, dans avoir besoin de configurer
            l'interval de contrôle. Il va en effet utiliser un fichier de données (data/XaaS/Avi-Networks/e2e.json)
            pour enregistrer la date/heure du dernier check. Ce qui permettra de changer sans autre 
            l'intervalle d'exécution de la tâche planifiée qui lance ce script

	DATE 	: Mars 2021
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
      [string]$targetTenant)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "SnowAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "E2EAPI.inc.ps1"))

# Chargement des fichiers propres à XaaS 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "Avi-Networks", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "Avi-Networks", "NameGeneratorAviNetworks.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "Avi-Networks", "AviNetworksAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configAviNetworks = [ConfigReader]::New("config-xaas-avi-networks.json")
$configE2E = [ConfigReader]::New("config-e2e.json")      


try
{
    
    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    # TODO: Adapter la ligne suivante
    $logHistory = [LogHistory]::new(@('xaas','avi-networks', 'e2e'), $global:LOGS_FOLDER, 30)
    
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
    
    $nameGeneratorAviNetworks = [NameGeneratorAviNetworks]::new($targetEnv, $targetTenant)
    
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
    #>
    # TODO: A adapter en ajoutant des clefs pointant sur des listes
	$notifications=@{
                    }


    # Chemin jusqu'au fichier où on a la date où le dernier check a été fait.
    $pathToE2EData = ([IO.Path]::Combine($global:DATA_FOLDER, "XaaS", "Avi-Networks", "e2e.json"))

    # Par défaut, on part du principe que le contenu du fichier de données est OK
    $initDataFile = $false

    # Si le fichier n'existe pas, on le créé
    if(!(Test-Path $pathToE2EData))
    {
        $logHistory.addLineAndDisplay(("Data file '{0}' doesn't exists, creating it..." -f $pathToE2EData))

        # Création du fichier avec la date/heure actuelle
        @{
            lastCheckTime = (getUnixTimestamp)
            poolList = @()
        } | ConvertTo-Json | Out-File $pathToE2EData -Encoding:UTF8

        # On fait en sorte que le fichier de données soit populé sans qu'aucune info ne soit remontée dans le End-2-End monitoring
        $initDataFile = $true
    }

    $e2eData = Get-Content -Path $pathToE2EData -Raw | ConvertFrom-Json

    $logHistory.addLineAndDisplay(("Last check was done on: {0}" -f (unixTimeToDate -unixTime $e2eData.lastCheckTime)))

    $aviNetworks = [AviNetworksAPI]::new($targetEnv,
                                        $configAviNetworks.getConfigValue(@($targetEnv, "infra", "server")), 
										$configAviNetworks.getConfigValue(@($targetEnv, "infra", "user")), 
										$configAviNetworks.getConfigValue(@($targetEnv, "infra", "password")))

    $e2e = 	[E2EAPI]::new($configE2E.getConfigValue(@("server", $targetEnv)), 
                            $configE2E.getConfigValue(@("serviceList")),
                            $configE2E.getConfigValue(@("proxy")))
    
    # Si on doit activer le Debug,
    if(Test-Path (Join-Path $PSScriptRoot "$($MyInvocation.MyCommand.Name).debug"))
    {
        # Activation du debug
        $e2e.activateDebug($logHistory)
        $aviNetworks.activateDebug($logHistory)
    }


    $logHistory.addLineAndDisplay("Getting tenant list...")
    $tenantList = $aviNetWorks.getTenantList()

    $tenantNo = 1
    
    ForEach($tenant in $tenantList)
    {
        # Recherche de l'id du service dans les custom labels
        $serviceId = ($tenant.suggested_object_labels | Where-Object { $_.key -eq $global:VRA_CUSTOM_PROP_EPFL_BG_ID}).value

        $logHistory.addLineAndDisplay(("[{0}/{1}] Tenant '{2}' (SVCID={3})" -f $tenantNo, $tenantList.count, $tenant.name, $serviceId))

        # Récupération de la liste des pools
        $logHistory.addLineAndDisplay("> Getting Pool list...")

        $poolList = $aviNetWorks.getPoolList($tenant)

        $logHistory.addLineAndDisplay(("> {0} Pool(s) found" -f $poolList.count))

        $poolNo = 1
        ForEach($pool in $poolList)
        {
            $logHistory.addLineAndDisplay((">> [{0}/{1}] Pool '{2}'" -f $poolNo, $poolList.count, $pool.name))

            # Récupération du résumé de l'état
            $runtime = $aviNetWorks.getPoolRuntime($tenant, $pool)

            # Récupération des détails sur les serveurs
            $servers = $aviNetWorks.getPoolRuntime($tenant, $pool, $true)

            # On regarde s'il y a eu un changement depuis le dernier check
            # OU
            # si on est en mode d'initialisation des données du fichier de suivi
            if(($runtime.oper_status.last_changed_time.secs -gt $e2eData.lastCheckTime) -or $initDataFile)
            {

                $poolData = ($e2eData.poolList | Where-Object { $_.uuid -eq $pool.uuid})
                # Si on n'a pas d'infos sur le pool dans le fichier de données (ce qui est notamment 
                # le cas quand on est en mode d'initialisation des données -> $initDataFile )
                if($null -eq $poolData)
                {
                    $logHistory.addLineAndDisplay(">>> No data found for pool, adding in datafile...")

                    $e2eData.poolList += @{
                        uuid = $pool.uuid
                        name = $pool.name
                        percServersUp = $runtime.percent_servers_up_total
                    }
                }
                else # On a les infos sur le pool dans le fichier de données
                {
                    $logHistory.addLineAndDisplay(">>> Data found in file for pool")
                    # S'il y a eu un changement depuis la dernière fois
                    if($poolData.percServersUp -ne $runtime.percent_servers_up_total)
                    {
                        $logHistory.addLineAndDisplay((">>> Percentage of UP servers has changed: {0}% -> {1}%" -f $poolData.percServersUp, $runtime.percent_servers_up_total))

                        $shortDescription = "{0}/{1} servers UP" -f $runtime.num_servers_up, $runtime.num_servers
                        $description = $shortDescription

                        # Si on QUITTE le 100% de serveurs UP
                        if($poolData.percServersUp -eq 100)
                        {
                            $logHistory.addLineAndDisplay(">>> New status is now DEGRADED")
                            $e2eStatusPriority = [E2EStatusPriority]::Degradation
                        }
                        # Si on REVIENT à 100% de serveurs UP
                        elseif($runtime.percent_servers_up_total -eq 100)
                        {
                            $logHistory.addLineAndDisplay(">>> New status is now UP")
                            $e2eStatusPriority = [E2EStatusPriority]::Up
                        }
                        else # On est à moins de 100% de UP et c'est simplement le pourcentage qui a changé
                        {
                            $logHistory.addLineAndDisplay(">>> Status is still DEGRADED")
                            $e2eStatusPriority = [E2EStatusPriority]::DescriptionUpdate
                        }

                        # Si on n'est pas UP, on fait une description un peu plus "élaborée"
                        if($e2eStatusPriority -ne [E2EStatusPriority]::Up)
                        {
                            # Récupération des noms des serveurs qui ne sont pas OPER_UP 
                            # On fait un "Sort-Object|Get-Unique" car pour une raison inconnue, les noms peuvent parfois être à double...
                            $description = "Down servers: {0}" -f `
                                ( ($servers | Where-Object { $_.oper_status.state -ne "OPER_DOWN" } | Select-Object -ExpandProperty hostname | Sort-Object | Get-Unique) -join ", ")
                        }

                        $logHistory.addLineAndDisplay((">>> Updating E2E with following information:`nStatus: {0}`nShort description: {1}`nDescription: {2}" -f `
                                                        $e2eStatusPriority, $shortDescription, $description))
                        #$e2e.setServiceStatus($serviceId, $e2eStatusPriority, $shortDescription, $description)


                        # Mise à jour des infos 
                        ($e2eData.poolList | Where-Object { $_.uuid -eq $pool.uuid}).percServersUp = $runtime.percent_servers_up_total

                    }
                    else # Il n'y a pas eu de changement depuis la dernière fois
                    {
                        $logHistory.addLineAndDisplay(">>> Status hasn't changed since last time")
                    }

                }# FIN Si on a des infos sur le pool dans le fichier de données OU qu'il faut mettre à jour celui-ci
                
            }
            else # Pas de changement depuis le dernier check
            {
                $logHistory.addLineAndDisplay(">>> No status change since last check")
            }

            # Mise à jour du fichier de données
            $e2eData | ConvertTo-Json | Out-File $pathToE2EData -Encoding:UTF8

            $poolNo++
        }# FIN BOUCLE de parcours des pools

        $tenantNo++
    }# FIN BOUCLE de parcours des tenants


    





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
