<#
USAGES:
	clean-ghost-projects.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl|research [-projectName <projectName>]
#>
<#
    BUT 		: Supprime les Projets qui sont en mode "ghost" s'ils sont vides.
                    Tous les éléments liés au BG sont aussi supprimés, dans l'ordre inverse
                    où ils ont été créés.

				
					On peut aussi faire en sorte de spécifier manuellement quel projet on veut effacer.

	DATE 		: Mars 2020
	AUTEUR 	: Lucien Chaboudez
	
	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
param ( [string]$targetEnv, [string]$targetTenant, [string]$projectName)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ResumeOnFail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRA8API.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "GroupsAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NSXAPI.inc.ps1"))




# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra8.json")
$configGlobal = [ConfigReader]::New("config-global.json")
$configGroups = [ConfigReader]::New("config-groups.json")
$configNSX = [ConfigReader]::New("config-nsx.json")



<#
-------------------------------------------------------------------------------------
	BUT : Efface un BG et tous ses composants (s'il ne contient aucun item).
		  
		  Si le BG contient des items, on va simplement le marquer comme "ghost" et changer les droits d'accès

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $groupsApp		-> Objet de la classe GroupsAPI permettant d'accéder à "groups"
	IN  : $nsx				-> Objet de la classe NSXAPI pour faire du ménage dans NSX
	IN  : $project			-> Objet contenant le Projet a effacer. Cet objet aura été renvoyé
					   			par un appel à une méthode de la classe vRA8API
	IN  : $targetTenant		-> Le tenant sur lequel on se trouve
	IN  : $nameGenerator	-> Objet de la classe NameGenerator 

	RET : $true si effacé
		  $false si pas effacé (mis en ghost)
#>
function deleteProjectAndComponentsIfPossible([vRA8API]$vra, [GroupsAPI]$groupsApp, [NSXAPI]$nsx, [PSCustomObject]$project, [string]$targetTenant, [NameGenerator]$nameGenerator)
{
	
	# Recherche des déploiement potentiellement présents dans le Projet
	$projectDeploymentList = $vra.getProjectDeploymentList($project)

	# S'il y a des déploiements,
	if($projectDeploymentList.Count -gt 0)
	{
		
		$logHistory.addLineAndDisplay(("--> Contains {0} deployments, cannot be deleted, skipping..." -f $projectDeploymentList.Count))

		$counters.inc('projectNotEmpty')

		$notifications.projectNotDeleted += $project.name

		$deleted = $false

	}
	else # Il n'y a aucun déploiement dans le projet
	{

		$nameGenerator.initDetailsFromProject($project)


		# --------------
		# Day-2 policies
		ForEach($policyRole in ([System.Enum]::getValues([PolicyRole])))
		{
			$day2PolName, $day2PolDesc = $nameGenerator.getPolicyNameAndDesc([PolicyType]::Action, $policyRole)

			$day2Policy = $vra.getPolicy($day2PolName)

			if($null -ne $day2Policy)
			{
				$logHistory.addLineAndDisplay(("--> Deleting Day-2 Policy '{0}'..." -f $day2PolName))
				$vra.deletePolicy($day2Policy)
			}

		}# FIN BOUCLE de parcours des roles pour les policies


		# --------------
		# Entitlement

		# Listing des entitlements et effacement
		$vra.getProjectEntitlementList($project) | Foreach-Object {

			# Suppression de l'entitlement (on le désactive au préalable)
			$logHistory.addLineAndDisplay(("--> Deleting Entitlement for '{0}' source..." -f $_.definition.name))
			
			$vra.deleteEntitlement($_)
		}
	
# TODO: continue
		# Seulement pour certains tenants et on doit obligatoirement le faire APRES avoir effacé le BG car sinon 
		# y'a une monstre exception sur plein de lignes qui nous insulte et elle ferait presque peur.
		if($targetTenant -eq $global:VRA_TENANT__RESEARCH)
		{

			#FIXME: Voir pour mettre le nécessaire ici en fonction de ce qui sera mis en place pour l'approbation
			# --------------
			# Groupes "groups" des approval policies

			# On va commencer la recherche des groupes d'approbation au niveau 2 seulement, car le 
			# niveau 1, c'est le service manager IaaS
			# $level = 2
			# while($true)
			# {
			# 	# Recherche des infos du groupe "groups" pour les approbation
			# 	$approveGroupGroupsInfos = $nameGenerator.getApproveGroupsGroupName($level, $false)

			# 	# Si vide, c'est qu'on a atteint le niveau max pour les level
			# 	if($null -eq $approveGroupGroupsInfos)
			# 	{
			# 		break
			# 	}

			# 	$logHistory.addLineAndDisplay(("--> Deleting approval groups group '{0}'..." -f $approveGroupGroupsInfos.name))
			# 	try
			# 	{
			# 		# On essaie d'effacer le groupe
			# 		$groupsApp.deleteGroup($approveGroupGroupsInfos.name)
			# 	}
			# 	catch
			# 	{
			# 		# Si exception, c'est qu'on n'a probablement pas les droits d'effacer parce que le owner du groupe n'est pas le bon
			# 		$notifications.groupsGroupsNotDeleted += $approveGroupGroupsInfos.name
			# 		$logHistory.addWarningAndDisplay("--> Cannot delete groups group maybe because not owner by correct person")
			# 	}

			# 	$level += 1

			# } # FIN BOUCLE de parcours des niveaux d'approbation

		}# FIN SI c'est pour ces tenants qu'il faut effacer des éléments

		
		$deleteForTenants = @($global:VRA_TENANT__ITSERVICES, $global:VRA_TENANT__RESEARCH)
		if($deleteForTenants -contains $targetTenant)
		{	
			#FIXME: Voir pour mettre le nécessaire ici en fonction de ce qui sera mis en place pour l'approbation
			# # --------------
			# # Approval policies
			# $approvalPoliciesTypesToDelete = @([ApprovalPolicyType]::NewItem,
			# 								   [ApprovalPolicyType]::Day2Action])
			# ForEach($approvalPolicyType in $approvalPoliciesTypesToDelete)
			# {
			# 	# Recherche du nom
			# 	$approvalPolicyName, $approvalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($approvalPolicyType)

			# 	$approvalPolicy = $vra.getApprovalPolicy($approvalPolicyName)
				
			# 	if($null -ne $approvalPolicy)
			# 	{
			# 		$logHistory.addLineAndDisplay(("--> Deleting Approval Policy '{0}'..." -f $approvalPolicy.name))
			# 		$vra.deleteApprovalPolicy($approvalPolicy)
			# 	}

			# }# FIN BOUCLE de parcours des Approval Policies à effacer

			# # --------------
			# # Groupe "groups" pour les demandes

			# $userGroupNameGroups = $nameGenerator.getRoleGroupsGroupName([UserRole]::User)
			# $logHistory.addLineAndDisplay(("--> Deleting customer groups group '{0}'..." -f $userGroupNameGroups))
			# try
			# {
			# 	$groupsApp.deleteGroup($userGroupNameGroups)
			# }
			# catch
			# {
			# 	# Si exception, c'est qu'on n'a probablement pas les droits d'effacer parce que le owner du groupe n'est pas le bon
			# 	$notifications.groupsGroupsNotDeleted += $userGroupNameGroups
			# 	$logHistory.addWarningAndDisplay("--> Cannot delete groups group maybe because not owner by correct person")
			# }

		}# FIN SI c'est pour ces tenants qu'il faut effacer des éléments


		if($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
		{
			# --------------
			# NSX

			# Section de Firewall
			$nsxFWSectionName, $nsxFWSectionDesc = $nameGenerator.getFirewallSectionNameAndDesc()
			$nsxSection  = $nsx.getFirewallSectionByName($nsxFWSectionName)

			if($null -ne $nsxSection)
			{
				$logHistory.addLineAndDisplay(("--> Deleting NSX Firewall section '{0}'..." -f $nsxFWSectionName))
				$nsx.deleteFirewallSection($nsxSection.id)
			}
			else
			{
				$logHistory.addLineAndDisplay(("--> NSX Firewall section '{0}' already deleted" -f $nsxFWSectionName))
			}

			# Security Group
			$nsxNSGroupName, $nsxNSGroupDesc = $nameGenerator.getSecurityGroupNameAndDesc($bg.name)
			$nsxNSGroup = $nsx.getNSGroupByName($nsxNSGroupName, [NSXAPIEndpoint]::Manager)
			if($null -ne $nsxNSGroup)
			{
				$logHistory.addLineAndDisplay(("--> Deleting NSX NS Group '{0}'..." -f $nsxNSGroupName))
				$nsx.deleteNSGroup($nsxNSGroup, [NSXAPIEndPoint]::Manager)
			}
			else
			{
				$logHistory.addLineAndDisplay(("--> NSX NS Group '{0}' already deleted" -f $nsxNSGroupName))
			}
			
		}

		$notifications.projectDeleted += $project.name

		# --------------
		# Project
		$logHistory.addLineAndDisplay(("--> Deleting Project '{0}'..." -f $project.name))
		$vra.deleteProject($project)

		# Incrémentation du compteur
		$counters.inc('projectDeleted')

		$deleted = $true
		
	}# FIN S'il n'y a aucun déploiement dans le projet

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
		if($notifications.$notif.count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications.$notif | Sort-Object| Get-Unique

			$valToReplace = @{}

			switch($notif)
			{
				# ---------------------------------------
                # BG effacés
                'projectDeleted'
                {
                    $valToReplace.projectList = ($uniqueNotifications -join "</li>`n<li>")
                    $mailSubject = "Info - Project(s) deleted"
                    $templateName = "project-deleted"
                }

				# ---------------------------------------
                # Projets pas effacés (car toujours des éléments)
                'projectNotDeleted'
                {
                    $valToReplace.projectList = ($uniqueNotifications -join "</li>`n<li>")
                    $mailSubject = "Info - Project(s) NOT deleted (because not empty)"
                    $templateName = "project-not-deleted-because-not-empty"
                }
				
				# ---------------------------------------
				# Groupes groups.epfl.ch pas effacés parce que probablement mauvais owner
				'groupsGroupsNotDeleted'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
                    $mailSubject = "Info - groups.epfl.ch Groups NOT deleted (maybe not correct owner)"
                    $templateName = "groups-groups-not-deleted"
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
	$logPath = @('vra', ('clean-ghost-bg-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()))
	$logHistory =[LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$counters = [Counters]::new()
	$counters.add('projectDeleted', '# Business Group deleted')
	$counters.add('projectNotEmpty', '# Business Group not deleted because not empty')

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, 
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

	# Pour s'interfacer avec l'application Groups
	$groupsApp = [GroupsAPI]::new($configGroups.getConfigValue(@($targetEnv, "server")),
								  $configGroups.getConfigValue(@($targetEnv, "appName")),
								   $configGroups.getConfigValue(@($targetEnv, "callerSciper")),
								   $configGroups.getConfigValue(@($targetEnv, "password")))

	<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications=@{projectDeleted = @()
					projectNotDeleted =@()
					groupsGroupsNotDeleted = @()}


	$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))

	
	# Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRA8API]::new($configVra.getConfigValue(@($targetEnv, "infra",  $targetTenant, "server")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

	
	# Création d'une connexion au serveur NSX pour accéder aux API REST de NSX
	$logHistory.addLineAndDisplay("Connecting to NSX-T...")
	$nsx = [NSXAPI]::new($configNSX.getConfigValue(@($targetEnv, "server")), 
						 $configNSX.getConfigValue(@($targetEnv, "user")), 
						 $configNSX.getConfigValue(@($targetEnv, "password")))


	$logHistory.addLineAndDisplay("Cleaning 'old' Business Groups")

	
	$projectList = $vra.getProjectList() | Where-Object { $_.name -eq 'its_excalt'}

	
	# Si on a entré un BG donné à effacer, 
	if($projectName -ne "")
	{
		# On extrait celui-ci de la liste
		$projectList = $projectList | Where-Object { $_.name -eq $projectName }
	}

	$logHistory.addLineAndDisplay(("{0} Project(s) found" -f $projectList.count))
	$projectNo = 1

	# Recherche et parcours de la liste des BG commençant par le bon nom pour le tenant
	$projectList | ForEach-Object {

		$logHistory.addLineAndDisplay(("[{0}/{1}] Checking Project '{2}'..." -f $projectNo, $projectList.count, $_.name))

		# Si c'est un BG d'unité ou de service et s'il est déjà en Ghost
		if((isProjectOfType -project $_ -typeList @([ProjectType]::Service, [ProjectType]::Unit, [ProjectType]::Project)) -and `
			((getProjectCustomPropValue -project $_ -customPropName $global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS) -eq $global:VRA_BG_STATUS__GHOST))
		{
			# TODO: continue
			$logHistory.addLineAndDisplay(("-> Project '{0}' is Ghost, deleting..." -f $_.name))
			$deleted = deleteProjectAndComponentsIfPossible -vra $vra -groupsApp $groupsApp -nsx $nsx -project $_ -targetTenant $targetTenant -nameGenerator $nameGenerator

			# Si le BG a pu être complètement effacé, c'est qu'il n'y avait plus d'items dedans et que donc forcément aucune
			# ISO ne pouvait être montée nulle part.
			if($deleted)
			{	
				# Recherche de l'UNC jusqu'au dossier où se trouvent les ISO pour le BG
				$projectISOFolder = $nameGenerator.getNASPrivateISOPath($_.name)
				
				# Si le dossier des ISO existe bien
				if(Test-Path $projectISOFolder)
				{
					$logHistory.addLineAndDisplay(("--> Deleting Project '{0}' ISO folder '{1}'... " -f $_.name, $projectISOFolder))
					# Suppression du dossier
					Remove-Item -Path $projectISOFolder -Recurse -Force
				}
				else
				{
					$logHistory.addLineAndDisplay(("--> ISO folder '{0}' for Project '{1}' already deleted" -f $projectISOFolder, $_.name))
				}
				
			} # FIN Si le BG a pu être effacé


		} 
		else # Pas encore possible d'effacer le projet
		{
			$logHistory.addLineAndDisplay("-> Not eligible to be deleted now")
		}

		$projectNo++

	}# Fin BOUCLE parcours des business groups


	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$logHistory.addLineAndDisplay("Done")

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

	# Affichage des nombres d'appels aux fonctions des objets REST
	$vra.displayFuncCalls()
	$nsx.displayFuncCalls()

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