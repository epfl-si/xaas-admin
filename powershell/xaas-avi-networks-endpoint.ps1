<#
USAGES:
    xaas-avi-networks-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action create -bgId <bgId> -ipList <ipList>
    xaas-avi-networks-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action modify -bgId <bgId> -lbName <lbName> -ipList <ipList>
    xaas-avi-networks-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl|research -action delete -bgId <bgId> -lbName <lbName>
 
#>
<#
    BUT 		: Permet de gérer le service AVI Network qui fourni des Load Balancers

	DATE 	: Février 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
    - Ce script prend du temps à s'exécuter car il charge le PowerCLI Amazon S3 et ce dernier étant énoOOOrme, 
        ça prend du temps... une tentative de ne  charger que les CmdLets nécessaires a été faite mais ça 
        n'accélère en rien...


    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    DOCUMENTATION: TODO:

#>

param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$bgId,
      [string]$ipList,
      [switch]$lbName)

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))

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

. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "AviNetworksAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configAviNetworks = [ConfigReader]::New("config-xaas-avi-networks.json")
$configVra = [ConfigReader]::New("config-vra.json")
$configE2E = [ConfigReader]::New("config-e2e.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_MODIFY              = "modify"
$ACTION_DELETE              = "delete"


<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le code.

	IN  : $notifications-> Dictionnaire
	IN  : $targetEnv	-> Environnement courant
	IN  : $targetTenant	-> Tenant courant
#>
function handleNotifications
{
	param([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications.$notif.count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications.$notif | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{

                # TODO: Créer les différentes notifications
				# ---------------------------------------
				# Erreur dans la récupération de stats d'utilisation pour un Bucket
				# 'bucketUsageError'
				# {
                #     $valToReplace.bucketList = ($uniqueNotifications -join "</li>`n<li>")
                #     $valToReplace.nbBuckets = $uniqueNotifications.count
				# 	$mailSubject = "Warning - S3 - Usage info not found for {{nbBuckets}} Buckets"
				# 	$templateName = "xaas-s3-bucket-usage-error"
				# }
			

				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			$notificationMail.send($mailSubject, $templateName, $valToReplace)

		} # FIN S'il y a des notifications pour la catégorie courante

	}# FIN BOUCLE de parcours des catégories de notifications
}


<#
-------------------------------------------------------------------------------------
	BUT : Efface un load balancer AVI Networks liés à un Business Group vRA

    IN  : $aviNetworks  -> Objet permettant de communiquer avec Avi Networks
	IN  : $bgId         -> ID "epfl" du BG vRA
    IN  : $lbName       -> le nom du Load Balancer
#>
function deleteLB([AviNetworkAPI]$aviNetworks, [string]$bgId, [string]$lbName)
{
    # TODO:
    # $ruleDeleted = $false

    # [enum]::getValues([XaaSAviNetworksTenantType]) | ForEach-Object {

    #     $name, $desc = $nameGeneratorAviNetworks.getTenantNameAndDesc($bgId, $_)

    #     $tenant = $aviNetworks.getTenantByName($name)
    #     if($null -ne $tenant)
    #     {
    #         # Si on n'a pas encore effacé la "rule"
    #         if(!$ruleDeleted)
    #         {
    #             $logHistory.addLine(("> Searching auth rule for tenant '{0}'..." -f $name))
    #             $rule = $aviNetworks.getTenantAdminAuthRule($tenant)

    #             if($null -ne $rule)
    #             {
    #                 $logHistory.addLine(("> Deleting rule '{0}'..." -f $rule.uuid))
    #                 $aviNetworks.deleteAdminAuthRule($rule)
    #                 $ruleDeleted = $true
    #             }
    #             else
    #             {
    #                 $logHistory.addLine("> No auth rule found")
    #             }
    #         }# FIN SI on n'a pas encore effacé la rule

    #         $logHistory.addLine(("> Tenant '{0}' exists, deleting..." -f $name))
    #         $tenant = $aviNetworks.deleteTenant($tenant)
    #     }
    #     else
    #     {
    #         $logHistory.addLine(("> Tenant '{0}' doesn't exists" -f $name))
    #     }

    # }# FIN BOUCLE de suppression des tenants pour le Business Group
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
    # TODO: Adapter la ligne suivante
    $logHistory = [LogHistory]::new(@('xaas','avi-networks', 'endpoint'), $global:LOGS_FOLDER, 30)
    
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
                                                
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()


	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                        $targetTenant, 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))	

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
        $vra.activateDebug($logHistory)
        $aviNetworks.activateDebug($logHistory)
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

    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau LoadBalancer
        $ACTION_CREATE {
            $deleteTenants = $true

            # Labels à ajouter. On a fait le choix de reprendre ceux qui sont utilisés dans vRA car ils auront en fait
            # la même valeur et seront mis à jour par un script de synchro
            $initialLabels = @{}
            $initialLabels.add($global:VRA_CUSTOM_PROP_EPFL_BG_ID, $bgId)
            $initialLabels.add($global:VRA_CUSTOM_PROP_VRA_BG_STATUS, $global:VRA_BG_STATUS__ALIVE)

            # -- Liste des mails de notification
            $logHistory.addLine(("Getting notification mail list for BG '{0}'..." -f $bg.name))
            $notificationMailList = getBGAccessGroupList -vra $vra -bg $bg -targetTenant $targetTenant -returnMails
            $logHistory.addLine(("{0} mail address(es) found:`n{1}" -f $notificationMailList.count, ($notificationMailList -join "`n")))

            # -- Création des Tenants AVI Networks si besoin
            $logHistory.addLine(("Creating tenant for BG '{0}'..." -f $bg.name))
            $tenantList = @()
            # Parcours des types de tenant (notion Avi Networks) possibles pour un BG
            [enum]::getValues([XaaSAviNetworksTenantType]) | ForEach-Object {

                $name, $desc = $nameGeneratorAviNetworks.getTenantNameAndDesc($bg.name, $_)

                $tenant = $aviNetworks.getTenantByName($name)
                # Si le tenant n'existe pas, on le créé
                if($null -eq $tenant)
                {
                    $logHistory.addLine(("> Tenant '{0}' doesn't exists, creating..." -f $name))
                    $tenantLabels = $initialLabels.Clone()
                    # Ajout du label spécifique pour le type de tenant
		            $tenantLabels.add($global:XAAS_AVI_NETWORKS_TENANT_TYPE, $_.toString())
                    $tenant = $aviNetworks.addTenant($name, $desc, $tenantLabels)

                    # Ajout de la notification mail
                    $logHistory.addLine(">> Creating alert mail config for tenant...")
                    $alertMailConfig = $aviNetWorks.addAlertMailConfig($tenant, $notificationMailList)

                    # Création des niveaux d'alerte
                    [enum]::getValues([XaaSAviNetworksAlertLevel]) | ForEach-Object {
                        $alertName, $alertLevelName = $nameGeneratorAviNetworks.getAlertNameAndLevel($_)

                        $logHistory.addLine((">>> Creating alert action level '{0}'..." -f $alertName))
                        $alertActionLevel = $aviNetworks.addActionGroupConfig($tenant, $alertMailConfig, $alertName, $alertLevelName)

                        # En fonction du niveau d'alerte, on défini le status que l'on va monitorer
                        $monitoredStatus = switch($_)
                        {
                            Medium { [XaaSAviNetworksMonitoredStatus]::Up } 
                            High {[XaaSAviNetworksMonitoredStatus]::Down }
                        }

                        $logHistory.addLine((">>> Adding monitored elements when status is '{0}" -f $monitoredStatus.toString()))

                        # Parcours des éléments à monitorer
                        [enum]::getValues([XaaSAviNetworksMonitoredElements]) | ForEach-Object {

                            $logHistory.addLine((">>>> Adding monitored element '{0}'..." -f $_.toString()))
                            # Ajout du nécessaire pour le statut défini
                            $alertConfig = $aviNetworks.addAlertConfig($tenant, $alertActionLevel, $_, $monitoredStatus)
                        }

                    }# FIN BOUCLE de parcours de niveaux d'alerte
                }
                else
                {
                    $logHistory.addLine(("> Tenant '{0}' already exists" -f $name))
                    # Si au moins un tenant existait, on ne fera pas de ménage dans ceux-ci en cas d'erreur
                    $deleteTenants = $false
                }

                $tenantList += $tenant
            }# FIN BOUCLE de création des tenants pour le Business Group


            # -- Recherche du rôle pour les utilisateurs
            $logHistory.addLine(("Getting '{0}' role ID..." -f $global:XAAS_AVI_NETWORKS_USER_ROLE_NAME))
            $role = $aviNetworks.getRoleByName($global:XAAS_AVI_NETWORKS_USER_ROLE_NAME)
            if($null -eq $role)
            {
                Throw ("Role '{0}' not found" -f $global:XAAS_AVI_NETWORKS_USER_ROLE_NAME)
            }
            $logHistory.addLine(("Role '{0}' has ID '{1}'" -f $global:XAAS_AVI_NETWORKS_USER_ROLE_NAME, $role.uuid))


            # -- Récupération des groupes de sécurité
            $logHistory.addLine(("Getting security groups from Business Group '{0}'..." -f $bg.name))
            # Groupe de support
            $groupList = @($vra.getBGRoleContent($bg.id, "CSP_SUPPORT") | ForEach-Object { ($_ -split '@')[0]})
            # Groupe "utilisateur"
            $groupList += getBGAccessGroupList -vra $vra -bg $bg -targetTenant $targetTenant

            if($groupList.count -eq 0)
            {
                Throw ("Not security group found for Business Group '{0}'" -f $bg.name)
            }
            $logHistory.addLine(("Security Groups will be:`n- {0}" -f ($groupList -join "`n- ")))


            # -- Ajout de la règle de sécurité
            $logHistory.addLine(("Adding security rule for Business Group's tenants"))
            $ruleList = $aviNetworks.addAdminAuthRule($tenantList, $role, $groupList)


        }# FIN Action Create


        # -- Modification d'un LoadBalancer
        $ACTION_MODIFY {

        }


        # -- Effacement d'un LoadBalancer
        $ACTION_DELETE {
            $logHistory.addLine(("Deleting Tenants for Business Group '{0}'..." -f $bg.name))
            deleteLB -aviNetworks $aviNetworks -bgId $bgId -lbName $lbName
        }

    }

    $logHistory.addLine("Script execution done!")


    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

    # Gestion des erreurs s'il y en a
    handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant
    

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

    # Si on était en train de créer un bucket et qu'on peut faire le cleaning
    if(($action -eq $ACTION_CREATE))
    {
        
        deleteLB -aviNetworks $aviNetworks -bgId $bgId -lbName $lbName
        
    }

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