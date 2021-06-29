<#
USAGES:
	tools-update-vm-custom-props.ps1 -targetEnv prod|test|dev -targetTenant itservices|epfl|research [-bgName <bgName>]
#>
<#
	BUT 		: Crée/met à jour les customs props des VMs en fonction du tenant et du BG où elles se trouvent.

	DATE 		: Mars 2020
	AUTEUR 	    : Lucien Chaboudez

	PARAMETRES : 
		$targetEnv		-> nom de l'environnement cible. Ceci est défini par les valeurs $global:TARGET_ENV__* 
						dans le fichier "define.inc.ps1"
		$targetTenant 	-> nom du tenant cible. Défini par les valeurs $global:VRA_TENANT__* dans le fichier
						"define.inc.ps1"
		$bgName			-> (optionnel) Nom du BG pour lequel limiter l'exécution du script	
	
	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, [string]$targetTenant, [string]$bgName)


. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))


# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")



try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logPath = @('tools', ('update-vm-custom-props-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()))
	$logHistory =[LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))


    
	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)


	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()
	$counters.add('reconfigActionFound', '# "Reconfigure" action not found')
	$counters.add('vmUpdated', '# VM updated')
	$counters.add('vmOK', '# VM OK')
	$counters.add('vmWithWaitingRequest', '# VM not updated because already having waiting request')

	$vraUser = $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user"))

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
						 $targetTenant, 
						 $vraUser,
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

	$logHistory.addLineAndDisplay("Getting BG list...")
	$bgList = $vra.getBGList()

	# Si on doit limiter à un BG,
	if($bgName -ne "")
	{
		$logHistory.addLineAndDisplay(("Limiting to '{0}' BG" -f $bgName))
		# Filtre
		$bgList = @($bgList | Where-Object { $_.name -eq $bgName } )
	}

	$logHistory.addLineAndDisplay(("{0} BG to process" -f $bgList.count))

    # Parcours de la liste des BG
    Foreach ($bg in $bgList)
    {
        $logHistory.addLineAndDisplay(("Processing BG '{0}'..." -f $bg.name))

        $logHistory.addLineAndDisplay("> Getting VM List...")   

        $vmList = $vra.getBGItemList($bg, $global:VRA_ITEM_TYPE_VIRTUAL_MACHINE)

        $logHistory.addLineAndDisplay(("> {0} VMs found" -f $vmList.count))

		# Pour ne pas récupérer ces données s'il n'y a aucune VM dans le BG (car c'est chronophage)
		if($vmList.count -gt 0)
		{
			# Liste des custom properties à check et des valeurs qu'elles devraient avoir
			$customPropsToCheck = @{
				$global:VRA_CUSTOM_PROP_EPFL_BG_ID = (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID)
				$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER = (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER)
				$global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME = (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME)
				$global:VRA_CUSTOM_PROP_VRA_BG_NAME = $bg.name
				$global:VRA_CUSTOM_PROP_VRA_TENANT_NAME = $targetTenant
			}
		}
		
		# Parcours des VM du BG
		Foreach($vm in $vmList)
        {
            $logHistory.addLineAndDisplay((">> Processing VM '{0}'..." -f $vm.name))

			$reconfigTemplate = $null

			# Parcours des customs properties à contrôler
			ForEach($customPropName in $customPropsToCheck.keys)
			{
				$customPropValue = getvRAObjectCustomPropValue -object $vm -customPropName $customPropName

				# Si la valeur est incorrecte
				if($customPropValue -ne $customPropsToCheck.$customPropName)
				{
					# Si on n'a pas encore le template
					if($null -eq $reconfigTemplate)
					{
						$actionInfos = $vra.getResourceActionInfos($vm, "Reconfigure")

						# Si on n'a pas trouvé l'action reconfigure, c'est qu'il y a un problème
						if($null -eq $actionInfos)
						{
							$counters.inc('reconfigActionFound')
							$logHistory.addWarningAndDisplay(("No 'Reconfigure' action found for '{0}'" -f $vm.name))
							continue
						}

						# On récupère le nécessaire pour corriger la chose
						$reconfigTemplate = $vra.getResourceActionTemplate($vm, "Reconfigure")
					}
				}
				else # Custom prop correcte
				{
					# On passe à la suivante
					continue
				}

				# Si custom prop n'existe pas
				if($null -eq $customPropValue)
				{
					$logHistory.addLineAndDisplay((">>> Custom Prop '{0}' missing" -f $customPropName))

					# Ajout de la custom property à la liste
					$replace = @{
						name = $customPropName
						value = $customPropsToCheck.$customPropName
					}
					$newProp = $vra.createObjectFromJSON('vra-object-custom-prop.json', $replace)
					$reconfigTemplate.data.customProperties += $newProp
				}
				else # Elle est correcte mais n'a pas la bonne valeur
				{
					$logHistory.addLineAndDisplay((">>> Custom Prop '{0}' incorrect ('{1}' instead of '{2}')" -f $customPropName, $customPropValue, $customPropsToCheck.$customPropName))
					# Mise à jour
					($reconfigTemplate.data.customProperties | Where-Object { $_.data.id -eq $customPropName }).data.value = $customPropsToCheck.$customPropName
				}

			}# FIN BOUCLE de parcours des custom property à contrôler

			# Si on doit faire un reconfigure
			if($null -ne $reconfigTemplate)
			{
				$logHistory.addLineAndDisplay((">> Reconfiguring VM to update custom properties..."))
				try
				{
					$vra.doResourceActionRequest($vm, $reconfigTemplate)
				}
				catch
				{
					# S'il y a déjà une requête en attente
					# NOTE: OUi c'est sale de passer par une exception pour faire ça mais j'ai pas de fonction vRAAPI pour savoir
					# s'il y a déjà une requête donc...
					if($_.Exception.Message -like '*must be completed before we accept new request on resource*')
					{
						$counters.inc('vmWithWaitingRequest')
						$logHistory.addWarningAndDisplay((">> VM already have a waiting request, cannot process it..."))
					}
					else
					{
						Throw
					}
				}
				
				$counters.inc('vmUpdated')
			}
			else # Pas besoin de reconfigure donc tout est OK
			{
				$counters.inc('vmOK')
			}

        }# FIN BOUCLE de parcours des VM du Business Group

    }# FIN BOUCLE de pacours des Business Groups

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

}
catch # Dans le cas d'une erreur dans le script
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