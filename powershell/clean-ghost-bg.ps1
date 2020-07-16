<#
USAGES:
	clean-ghost-bg.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl|research
#>
<#
    BUT 		: Supprime les Business Groups qui sont en mode "ghost" s'ils sont vides.
                    Tous les éléments liés au BG sont aussi supprimés, dans l'ordre inverse
                    où ils ont été créés.
                    1. Reservations
					2. Entitlement
					3. Business Group

	DATE 		: Mars 2020
	AUTEUR 	: Lucien Chaboudez

	PARAMETRES : 
		$targetEnv		-> nom de l'environnement cible. Ceci est défini par les valeurs $global:TARGET_ENV__* 
						dans le fichier "define.inc.ps1"
		$targetTenant 	-> nom du tenant cible. Défini par les valeurs $global:VRA_TENANT__* dans le fichier
						"define.inc.ps1"
	
	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, [string]$targetTenant)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "JSONUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NewItems.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ResumeOnFail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))




# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")



<#
-------------------------------------------------------------------------------------
	BUT : Efface un BG et tous ses composants (s'il ne contient aucun item).
		  
		  Si le BG contient des items, on va simplement le marquer comme "ghost" et changer les droits d'accès

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg				-> Objet contenant le BG a effacer. Cet objet aura été renvoyé
					   			par un appel à une méthode de la classe vRAAPI
	IN  : $targetTenant		-> Le tenant sur lequel on se trouve
	IN  : $nameGenerator	-> Objet de la classe NameGenerator 

	RET : $true si effacé
		  $false si pas effacé (mis en ghost)
#>
function deleteBGAndComponentsIfPossible([vRAAPI]$vra, [PSObject]$bg, [string]$targetTenant, [NameGenerator]$nameGenerator)
{

	# Recherche des items potentiellement présents dans le BG
	$bgItemList = $vra.getBGItemList($bg)

	# S'il y a des items,
	if($bgItemList.Count -gt 0)
	{

		$logHistory.addLineAndDisplay(("--> Contains {0} items, cannot be deleted, skipping..." -f $bgItemList.Count))

		$counters.inc('BGNotEmpty')

		$notifications['bgNotDeleted'] += $bg.name

		$deleted = $false

	}
	else # Il n'y a aucun item dans le BG
	{
		# Récupération des informations nécessaires pour les éléments à supprimer (afin de les filtrer)
		$resNameBase = $nameGenerator.getBGResName($bg.name, "")

		# --------------
		# Reservations
		# Parcours des Reservations trouvées et suppression
		$vra.getResListMatch($resNameBase, $false) | ForEach-Object {

			$logHistory.addLineAndDisplay(("--> Deleting Reservation '{0}'..." -f $_.Name))
			$vra.deleteRes($_.id)
		}


		# --------------
		# Entitlement
		# Si le BG a un entitlement,
		$bgEnt = $vra.getBGEnt($bg.id)
		if($null -ne $bgEnt)
		{

			# Suppression de l'entitlement (on le désactive au préalable)
			$logHistory.addLineAndDisplay(("--> Deleting Entitlement '{0}'..." -f $bgEnt.name))
			# Désactivation
			$dummy = $vra.updateEnt($bgEnt, $false)
			$vra.deleteEnt($bgEnt.id)
		}

		
		$notifications['bgDeleted'] += $bg.name

		# --------------
		# Business Group
		$logHistory.addLineAndDisplay(("--> Deleting Business Group '{0}'..." -f $bg.name))
		$vra.deleteBG($bg.id)


		# --------------
		# Préfixe de VM
		# Seulement pour certains tenants et on doit obligatoirement le faire APRES avoir effacé le BG car sinon 
		# y'a une monstre exception sur plein de lignes qui nous insulte et elle ferait presque peur.
		$deleteForTenants = @($global:VRA_TENANT__RESEARCH)
		if($deleteForTenants -contains $targetTenant)
		{
			# On initialise les détails depuis le nom du BG, cela nous permettra de récupérer
			# le nom du préfix de machine.
			$nameGenerator.initDetailsFromBGName($bg.name)

			$machinePrefixName = $nameGenerator.getVMMachinePrefix()

			$machinePrefix = $vra.getMachinePrefix($machinePrefixName)

			# Si on a trouvé un ID de machine
			if($null -ne $machinePrefix)
			{
				$logHistory.addLineAndDisplay(("--> Deleting Machine Prefix '{0}'..." -f $machinePrefix.name))
				$vra.deleteMachinePrefix($machinePrefix)
			}

		}# FIN S'il faut effacer le préfix de VM

		# --------------
		# Approval policies
		$deleteForTenants = @($global:VRA_TENANT__ITSERVICES, $global:VRA_TENANT__RESEARCH)
		if($deleteForTenants -contains $targetTenant)
		{	
			$approvalPoliciesTypesToDelete = @($global:APPROVE_POLICY_TYPE__ITEM_REQ,
											   $global:APPROVE_POLICY_TYPE__ACTION_REQ)
			ForEach($approvalPolicyType in $approvalPoliciesTypesToDelete)
			{
				# Recherche du nom
				$approvalPolicyName, $approvalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($approvalPolicyType)

				$approvalPolicy = $vra.getApprovalPolicy($approvalPolicyName)
				
				if($null -ne $approvalPolicy)
				{
					$logHistory.addLineAndDisplay(("--> Deleting Approval Policy '{0}'..." -f $approvalPolicy.name))
					$vra.deleteApprovalPolicy($approvalPolicy)
				}

			}# FIN BOUCLE de parcours des Approval Policies à effacer

		}# FIN S'il faut effacer les approval policies

		# Incrémentation du compteur
		$counters.inc('BGDeleted')

		$deleted = $true
	}

	return $deleted
}



<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

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
		if($notifications[$notif].count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications[$notif] | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{
				# ---------------------------------------
                # BG effacés
                'bgDeleted'
                {
                    $valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
                    $mailSubject = "Info - Business Group deleted"
                    $templateName = "bg-deleted"
                }

				# ---------------------------------------
                # BG pas effacés (car toujours des éléments)
                'bgNotDeleted'
                {
                    $valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
                    $mailSubject = "Info - Business Group NOT deleted (because not empty)"
                    $templateName = "bg-not-deleted-because-not-empty"
                }
				

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
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
									Programme principal
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
#>

try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logName = 'vra-clean-ghost-bg-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()
	$logHistory =[LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$counters = [Counters]::new()
	$counters.add('BGDeleted', '# Business Group deleted')
	$counters.add('BGNotEmpty', '# Business Group not deleted because not empty')

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Objet pour pouvoir envoyer des mails de notification
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)

	<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications=@{bgDeleted = @()
					bgNotDeleted =@()}


	$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))


	
	# Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "infra", "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "user"), 
						 $configVra.getConfigValue($targetEnv, "infra", $targetTenant, "password"))




	$logHistory.addLineAndDisplay("Cleaning 'old' Business Groups")

	# Recherche et parcours de la liste des BG commençant par le bon nom pour le tenant
	$vra.getBGList() | ForEach-Object {

		$logHistory.addLineAndDisplay(("Checking Business Group '{0}'..." -f $_.name))

		# Si c'est un BG d'unité ou de service et s'il est déjà en Ghost
		if((isBGOfType -bg $_ -typeList @($global:VRA_BG_TYPE__SERVICE, $global:VRA_BG_TYPE__UNIT, $global:VRA_BG_TYPE__PROJECT)) -and `
			((getBGCustomPropValue -bg $_ -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_STATUS) -eq $global:VRA_BG_STATUS__GHOST))
		{
			$logHistory.addLineAndDisplay(("-> Business Group '{0}' is Ghost, deleting..." -f $_.name))
			$deleted = deleteBGAndComponentsIfPossible -vra $vra -bg $_ -targetTenant $targetTenant -nameGenerator $nameGenerator

			# Si le BG a pu être complètement effacé, c'est qu'il n'y avait plus d'items dedans et que donc forcément aucune
			# ISO ne pouvait être montée nulle part.
			if($deleted)
			{	
				$logHistory.addLineAndDisplay(("--> Deleting Business Group '{0}' ISO folder '{1}'... " -f $_.name, $bgISOFolder))
				# Recherche de l'UNC jusqu'au dossier où se trouvent les ISO pour le BG
				$bgISOFolder = $nameGenerator.getNASPrivateISOPath($_.name)
				
				# Suppression du dossier
				Remove-Item -Path $bgISOFolder -Recurse -Force
			}

		}

	}

	$vra.disconnect()

	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$logHistory.addLineAndDisplay("Done")

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

	# Affichage des nombres d'appels aux fonctions des objets REST
	$vra.displayFuncCalls()

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