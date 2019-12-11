<#
USAGES:
	sync-ad-groups-from-ldap-or-django.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl
#>
<#
	BUT 		: Crée/met à jour les groupes AD pour l'environnement donné et le tenant EPFL.
				  Pour la gestion du contenu des groupes, il a été fait en sorte d'optimiser le
				  nombre de requêtes faites dans AD

	DATE 		: Mars 2018
	AUTEUR 	: Lucien Chaboudez

	ATTENTION: Ce script doit être exécuté avec un utilisateur qui a les droits de créer des
				  groupes dans Active Directory, dans les OU telles que renvoyées par la fonction
				  "getADGroupsOUDN()" de la classe "NameGenerator"

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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")

<#
-------------------------------------------------------------------------------------
	BUT : Regarde si un groupe Active Directory existe et si ce n'est pas le cas, il 
		  est créé.

	IN  : $groupName		-> Nom du groupe à créer
	IN  : $groupDesc		-> Description du groupe à créer.
	IN  : $groupMemberGroup	-> Nom du groupe à ajouter dans le groupe $groupName
	IN  : $OU				-> OU Active Directory dans laquelle créer le groupe
	IN  : $simulation		-> $true|$false pour dire si on est en mode simulation ou pas.

	RET : $true	-> OK
		  $false -> le groupe ($groupMemberGroup) à ajouter dans le groupe $groupName 
		  			n'existe pas.
#>
function createADGroupWithContent
{
	param([string]$groupName, [string]$groupDesc, [string]$groupMemberGroup, [string]$OU, [bool]$simulation)

	# Si le groupe n'existe pas encore 
	if((ADGroupExists -groupName $groupName) -eq $false)
	{
		# On regarde si le groupe à ajouter dans le nouveau groupe existe
		if((ADGroupExists -groupName $groupMemberGroup) -eq $false)
		{
			return $false
		}

		# Si on arrive ici, c'est que le groupe à mettre dans le nouveau groupe AD existe

		if(-not $simulation)
		{
			$logHistory.addLineAndDisplay(("--> Creating AD group '{0}'..." -f $groupName))
			# Création du groupe
			New-ADGroup -Name $groupName -Description $groupDesc -GroupScope DomainLocal -Path $OU

			$logHistory.addLineAndDisplay(("--> Adding {0} member(s) to AD group..." -f $groupMemberGroup.Count))
			
			Add-ADGroupMember $groupName -Members $groupMemberGroup

			$counters.inc('ADGroupsCreated')
		}
	}
	else # Le groupe existe déjà
	{	
		$logHistory.addLineAndDisplay(("--> AD group '{0}' already exists" -f $groupName))
	}
	return $true
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
			switch($notif)
			{
				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant EPFL
				'missingEPFLADGroups'
				{
					$docUrl = ""
					Write-Warning "Set doc URL"
					$mailSubject = getvRAMailSubject -shortSubject "Error - Active Directory groups missing" -targetEnv $targetEnv -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les groupes Active Directory suivants sont manquants pour l'environnement <b>{0}</b> et le Tenant <b>EPFL</b>. `
<br>Leur absence empêche la création d'autres groupes AD ainsi que des Business Groups qui les utilisent. `
<br>Veuillez les créer à la main comme expliqué dans la procédure:`
<br><ul><li>{1}</li></ul>De la documentation pour faire ceci peut être trouvée <a href='{2}'>ici</a>."  -f $targetEnv, ($uniqueNotifications -join "</li>`n<li>"), $docUrl)
				}

				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant ITS
				'missingITSADGroups'
				{
					$docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=72516653"
					$mailSubject = getvRAMailSubject -shortSubject "Error - Active Directory groups missing" -targetEnv $targetEnv -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les groupes Active Directory suivants sont manquants pour l'environnement <b>{0}</b> et le Tenant <b>ITServices</b>. `
<br>Leur absence empêche la création d'autres groupes AD ainsi que des Business Groups qui les utilisent. `
<br>Veuillez les créer à la main comme expliqué dans la procédure:`
<br><ul><li>{1}</li></ul>De la documentation pour faire ceci peut être trouvée <a href='{2}'>ici</a>."  -f $targetEnv, ($uniqueNotifications -join "</li>`n<li>"), $docUrl)
				}

				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $message

		} # FIN S'il y a des notifications pour la catégorie courante
	}# FIN BOUCLE de parcours des catégories de notifications
}

<#
-------------------------------------------------------------------------------------
	BUT : Contrôle que les noms des comptes donnés existent bien dans AD. Si ce n'est pas le
			cas, ils sont supprimés de la liste.

	IN  : $accounts	-> tableau avec la liste des comptes à contrôler

	RET : Tableau avec la liste des comptes sans ceux qui n'existent pas dans AD
#>
function removeInexistingADAccounts
{
	param([Array] $accounts)

	$validAccounts = @()

	ForEach($acc in $accounts)
	{
		try 
		{
			$m = Get-ADUser $acc

			# Si on arrive ici, c'est que pas d'erreur donc compte trouvé.
			$validAccounts += $acc
		}
		catch 
		{
			$logHistory.addWarningAndDisplay(("User {0} doesn't have an account in Active directory" -f $acc ))
			$counters.inc('ADMembersNotFound')
		}
	}

	return $validAccounts
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------


# ******************************************
# CONFIGURATION
# Nombre de niveaux dans lequel rechercher les unités.
$EPFL_FAC_UNIT_NB_LEVEL = 3

# Pour dire si on est en mode Simulation ou pas. Si c'est le cas, uniquement les lectures dans AD sont effectuée mais
# aucune écriture. 
# Pour passer en mode simulation, il suffit de créer un fichier "SIMULATION_MODE" au même niveau que
# le script courant
$SIMULATION_MODE = (Test-Path -Path ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__SIMULATION_MODE)))

# Pour dire si on est en mode test. Si c'est le cas, on ne traitera qu'un nombre limité d'unités, nombre qui est
# spécifié par $EPFL_TEST_NB_UNITS_MAX ci-dessous (si Tenant EPFL).
# Pour passer en mode simulation, il suffit de créer un fichier "TEST_MODE" au même niveau que
# le script courant
$TEST_MODE = (Test-Path -Path ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__TEST_MODE)))
$EPFL_TEST_NB_UNITS_MAX = 10


# CONFIGURATION
# ******************************************


try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logName = 'vra-sync-AD-from-LDAP-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()
	$logHistory = [LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups" ainsi que d'autre choses...
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)
	
	Import-Module ActiveDirectory

	if($SIMULATION_MODE)
	{
		$logHistory.addLineAndDisplay("***************************************")
		$logHistory.addLineAndDisplay("** Script running in simulation mode **")
		$logHistory.addLineAndDisplay("***************************************")
	}
	if($TEST_MODE)
	{
		$logHistory.addLineAndDisplay("*********************************")
		$logHistory.addLineAndDisplay("** Script running in TEST mode **")
		$logHistory.addLineAndDisplay("*********************************")
	}

	# Liste des groupes AD traités par le script
	$doneADGroupList = @()
	
	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
	$counters.add('ADGroupsCreated', '# AD Groups created')
	$counters.add('ADGroupsRemoved', '# AD Groups removed')
	$counters.add('ADGroupsContentModified', '# AD Groups modified')
	$counters.add('ADGroupsMembersAdded', '# AD Group members added')
	$counters.add('ADGroupsMembersRemoved', '# AD Group members removed')
	$counters.add('ADMembersNotFound', '# AD members not found')

	<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications = @{}



	# -------------------------------------------------------------------------------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	# --------------------------------------------------------- TENANT EPFL ---------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	if($targetTenant -eq $global:VRA_TENANT__EPFL)
	{
		$logHistory.addLineAndDisplay("Processing data for EPFL Tenant")

		# Ajout des compteurs propres au tenant
		$counters.add('epfl.facProcessed', '# Faculty processed')
		$counters.add('epfl.facSkipped', '# Faculty skipped')
		$counters.add('epfl.facIgnored', '# Faculty ignored (because of filter)')
		$counters.add('epfl.LDAPUnitsProcessed', '# LDAP Units processed')
		$counters.add('epfl.LDAPUnitsEmpty', '# LDAP Units empty')

		# Ajout du nécessaire pour gérer les notifications pour ce Tenant
		$notifications.missingEPFLADGroups = @()

		# Pour faire les recherches dans LDAP
		$ldap = [EPFLLDAP]::new()

		# Recherche de toutes les facultés
		$facultyList = $ldap.getLDAPFacultyList()

		$exitFacLoop = $false

		# Parcours des facultés trouvées
		ForEach($faculty in $facultyList)
		{
			$counters.inc('epfl.facProcessed')
			$logHistory.addLineAndDisplay(("[{0}/{1}] Faculty {2}..." -f $counters.get('epfl.facProcessed'), $facultyList.Count, $faculty['name']))
			
			# ----------------------------------------------------------------------------------
			# --------------------------------- FACULTE
			# ----------------------------------------------------------------------------------

			
			# --------------------------------- APPROVE

			$allGroupsOK = $true
			# Génération des noms des X groupes dont on va avoir besoin pour approuver les NOUVELLES demandes pour la faculté 
			$level = 0
			while($true)
			{
				$level += 1
				$approveGroupInfos = $nameGenerator.getEPFLApproveADGroupName($faculty['name'], $level)

				# S'il n'y a plus de groupe pour le level courant, on sort
				if($null -eq $approveGroupInfos)
				{
					break
				}
				
				$approveGroupDescAD = $nameGenerator.getEPFLApproveADGroupDesc($faculty['name'], $level)
				$approveGroupNameGroups = $nameGenerator.getEPFLApproveGroupsADGroupName($faculty['name'], $level)

				# Création des groupes + gestion des groupes prérequis 
				if((createADGroupWithContent -groupName $approveGroupInfos.name -groupDesc $approveGroupDescAD -groupMemberGroup $approveGroupNameGroups `
					-OU $nameGenerator.getADGroupsOUDN($approveGroupInfos.onlyForTenant) -simulation $SIMULATION_MODE) -eq $false)
				{
					if($notifications['missingEPFLADGroups'] -notcontains $approveGroupNameGroups)
					{
						# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
						$notifications['missingEPFLADGroups'] += $approveGroupNameGroups
					}
					$allGroupsOK = $false
				}
			}# FIn boucle de création des groupes pour les différents Levels 

			# Si on n'a pas pu créer tous les groupes pour la faculté courante, 
			if($allGroupsOK -eq $false)
			{
				$counters.inc('epfl.facSkipped')
				# On passe à la faculté suivante
				continue
			}

			
			# --------------------------------- ROLES
			
			# Il faut créer les groupes pour les Roles CSP_SUBTENANT_MANAGER et CSP_SUPPORT s'ils n'existent pas

			# Génération des noms des groupes dont on va avoir besoin.
			$adminGroupNameAD = $nameGenerator.getEPFLRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])
			$adminGroupDescAD = $nameGenerator.getEPFLRoleADGroupDesc("CSP_SUBTENANT_MANAGER", $faculty['name'])
			$adminGroupNameGroups = $nameGenerator.getEPFLRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER", $faculty['name'])

			$supportGroupNameAD = $nameGenerator.getEPFLRoleADGroupName("CSP_SUPPORT", $faculty['name'])
			$supportGroupDescAD = $nameGenerator.getEPFLRoleADGroupDesc("CSP_SUPPORT", $faculty['name'])
			$supportGroupNameGroups = $nameGenerator.getEPFLRoleGroupsADGroupName("CSP_SUPPORT", $faculty['name'])

			# Création des groupes + gestion des groupes prérequis 
			if((createADGroupWithContent -groupName $adminGroupNameAD -groupDesc $adminGroupDescAD -groupMemberGroup $adminGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
				$notifications['missingEPFLADGroups'] += $adminGroupNameGroups
				break
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $adminGroupNameAD


			if((createADGroupWithContent -groupName $supportGroupNameAD -groupDesc $supportGroupDescAD -groupMemberGroup $supportGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
				$notifications['missingEPFLADGroups'] += $supportGroupNameGroups
				break
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $supportGroupNameAD



			# ----------------------------------------------------------------------------------
			# --------------------------------- UNITÉS
			# ----------------------------------------------------------------------------------

			# Recherche des unités pour la facultés
			$unitList = $ldap.getFacultyUnitList($faculty['name'], $EPFL_FAC_UNIT_NB_LEVEL)

			$unitNo = 1
			# Parcours des unités de la faculté
			ForEach($unit in $unitList)
			{
				$logHistory.addLineAndDisplay(("-> [{0}/{1}] Unit {2} => {3}..." -f $unitNo, $unitList.Count, $faculty['name'], $unit['name']))

				# Recherche des membres de l'unité
				$ldapMemberList = $ldap.getUnitMembers($unit['uniqueidentifier'])

				# Création du nom du groupe AD et de la description
				$adGroupName = $nameGenerator.getEPFLRoleADGroupName("CSP_CONSUMER", [int]$faculty['uniqueidentifier'], [int]$unit['uniqueidentifier'])
				$adGroupDesc = $nameGenerator.getEPFLRoleADGroupDesc("CSP_CONSUMER", $faculty['name'], $unit['name'])

				# Pour définir si un groupe AD a été créé lors de l'itération courante
				$newADGroupCreated = $false

				try
				{
					# On tente de récupérer le groupe (on met dans une variable juste pour que ça ne s'affiche pas à l'écran)
					$adGroup = Get-ADGroup -Identity $adGroupName

					$adGroupExists = $true
					$logHistory.addLineAndDisplay(("--> Group exists ({0}) " -f $adGroupName))

					if(-not $SIMULATION_MODE)
					{
						# Mise à jour de la description du groupe dans le cas où ça aurait changé
						Set-ADGroup $adGroupName -Description $adGroupDesc -Confirm:$false
					}

					# Listing des usernames des utilisateurs présents dans le groupe
					$adMemberList = Get-ADGroupMember $adGroupName | ForEach-Object {$_.SamAccountName}

				}
				catch # Le groupe n'existe pas.
				{
					Write-Debug ("--> Group doesn't exists ({0}) " -f $adGroupName)
					# Si l'unité courante a des membres
					if($ldapMemberList.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Creating group ({0}) " -f $adGroupName))

						if(-not $SIMULATION_MODE)
						{
							# Création du groupe
							New-ADGroup -Name $adGroupName -Description $adGroupDesc -GroupScope DomainLocal -Path $nameGenerator.getADGroupsOUDN($true)
						}
						
						$newADGroupCreated = $true;

						$counters.inc('ADGroupsCreated')

						$adGroupExists = $true
						# le groupe est vide.
						$adMemberList = @()
					}
					else # Pas de membres donc on ne créé pas le groupe
					{
						$logHistory.addLineAndDisplay(("--> No members in unit '{0}', skipping group creation " -f $unit['name']))
						$counters.inc('epfl.LDAPUnitsEmpty')
						$adGroupExists = $false
					}
				}

				# Si le groupe AD existe
				if($adGroupExists)
				{
					# S'il n'y a aucun membre dans le groupe AD,
					if($null -eq $adMemberList)
					{
						$toAdd = $ldapMemberList
						$toRemove = @()
					}
					else # Il y a des membres dans le groupe AD
					{
						# Définition des membres à ajouter/supprimer du groupe AD
						$toAdd = Compare-Object -ReferenceObject $ldapMemberList -DifferenceObject $adMemberList  | Where-Object {$_.SideIndicator -eq '<=' } | ForEach-Object {$_.InputObject}
						$toRemove = Compare-Object -ReferenceObject $ldapMemberList -DifferenceObject $adMemberList  | Where-Object {$_.SideIndicator -eq '=>' }  | ForEach-Object {$_.InputObject}
					}

					# On commence par filtrer les comptes AD à ajouter pour savoir s'ils existent tous
					$toAdd = removeInexistingADAccounts -accounts $toAdd

					# Ajout des nouveaux membres s'il y en a
					if($toAdd.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Adding {0} members in group {1} " -f $toAdd.Count, $adGroupName))
						if(-not $SIMULATION_MODE)
						{
							Add-ADGroupMember $adGroupName -Members $toAdd
						}

						$counters.inc('ADGroupsMembersAdded')
					}
					else # Il n'y a aucun membre à ajouter dans le groupe 
					{
						# Si on vient de créer le groupe AD
						if($newADGroupCreated)
						{
							if(-not $SIMULATION_MODE)
							{
								# On peut le supprimer car il est de toute façon vide... Et ça ne sert à rien qu'un BG soit créé pour celui-ci du coup
								Remove-ADGroup $adGroupName -Confirm:$false
							}
						
							$counters.dec('ADGroupsCreated')
						}

					}
					# Suppression des "vieux" membres s'il y en a
					if($toRemove.Count -gt 0)
					{
						$logHistory.addLineAndDisplay(("--> Removing {0} members from group {1} " -f $toRemove.Count, $adGroupName))
						if(-not $SIMULATION_MODE)
						{
							Remove-ADGroupMember $adGroupName -Members $toRemove -Confirm:$false
						}

						$counters.inc('ADGroupsMembersRemoved')
					}

					if(($toRemove.Count -gt 0) -or ($toAdd.Count -gt 0))
					{
						$counters.inc('ADGroupsContentModified')
					}

					# On enregistre le nom du groupe AD traité
					$doneADGroupList += $adGroupName

				} # FIN SI le groupe AD existe



				$counters.inc('epfl.LDAPUnitsProcessed')
				$unitNo += 1

				# Pour faire des tests
				if($TEST_MODE -and ($counters.get('epfl.LDAPUnitsProcessed') -ge $EPFL_TEST_NB_UNITS_MAX))
				{
					$exitFacLoop = $true
					break
				}

			}# FIN BOUCLE de parcours des unités de la faculté

			if($exitFacLoop)
			{
				break
			}

		}# FIN BOUCLE de parcours des facultés

		# ----------------------------------------------------------------------------------------------------------------------

		# Parcours des groupes AD qui sont dans l'OU de l'environnement donné. On ne prend que les groupes qui sont utilisés pour 
		# donner des droits d'accès aux unités. Afin de faire ceci, on fait un filtre avec une expression régulière
		Get-ADGroup  -Filter ("Name -like '*'") -SearchBase $nameGenerator.getADGroupsOUDN($true) -Properties Description | 
		Where-Object {$_.Name -match $nameGenerator.getEPFLADGroupNameRegEx("CSP_CONSUMER")} | 
		ForEach-Object {

			# Si le groupe n'est pas dans ceux créés à partir de LDAP, c'est que l'unité n'existe plus. On supprime donc le groupe AD pour que 
			# le Business Group associé soit supprimé également.
			if($doneADGroupList -notcontains $_.name)
			{
				$logHistory.addLineAndDisplay(("--> Unit doesn't exists anymore, removing group {0} " -f $_.name))
				if(-not $SIMULATION_MODE)
				{
					# On supprime le groupe AD
					Remove-ADGroup $_.name -Confirm:$false
				}

				$counters.inc('ADGroupsRemoved')
			}
		}# FIN BOUCLE de parcours des groupes AD qui sont dans l'OU de l'environnement donné
	}


	# -------------------------------------------------------------------------------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	# ------------------------------------------------------ TENANT ITSERVICES ------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	# -------------------------------------------------------------------------------------------------------------------------------------
	elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
	{
		$logHistory.addLineAndDisplay("Processing data for ITServices Tenant")

		# Ajout du nécessaire pour gérer les notifications pour ce Tenant
		$notifications.missingITSADGroups = @()

		# Ajout des compteurs propres au tenant
		$counters.add('its.serviceProcessed', '# Service processed')
		$counters.add('its.serviceSkipped', '# Service skipped')

		# Check de l'existence du fichier JSON contenant la liste des services
		$itServiceJSONFile = ([IO.Path]::Combine($global:DATA_FOLDER, "itservices.json"))
		if(!(Test-Path $itServiceJSONFile ))
		{
			Throw ("JSON file with ITServices not found ! ({0})" -f $itServiceJSONFile)
		}

		# Chargement des données depuis le fichier 
		$servicesList = ((Get-Content -Path $itServiceJSONFile) -join "`n") | ConvertFrom-Json
		
		# Si on rencontre une erreur, 
		if(($servicesList -eq $false) -or ($null -eq $servicesList))
		{
			Throw ("Error getting Services list for '{0}' tenant" -f $targetTenant)
		}

		# On prend la liste correspondant à l'environnement sur lequel on se trouve
		$servicesList = $servicesList.$targetEnv


		$serviceNo = 1 
		# Parcours des services renvoyés par Django
		ForEach($service in $servicesList)
		{

			$logHistory.addLineAndDisplay(("-> [{0}/{1}] Service {2}..." -f $serviceNo, $servicesList.Count, $service.shortName))

			$counters.inc('its.serviceProcessed')

			$serviceNo += 1

			# --------------------------------- APPROVE
			$allGroupsOK = $true
			# Génération des noms des X groupes dont on va avoir besoin pour approuver les NOUVELLES demandes pour le service. 
			$level = 0
			while($true)
			{
				$level += 1
				# Recherche des informations pour le level courant.
				$approveGroupInfos = $nameGenerator.getITSApproveADGroupName($service.shortName, $level)

				# Si vide, c'est qu'on a atteint le niveau max pour les level
				if($null -eq $approveGroupInfos)
				{
					break
				}

				$approveGroupDescAD = $nameGenerator.getITSApproveADGroupDesc($service.longName, $level)
				$approveGroupNameGroups = $nameGenerator.getITSApproveGroupsADGroupName($service.shortName, $level)

				# Création des groupes + gestion des groupes prérequis 
				if((createADGroupWithContent -groupName $approveGroupInfos.name -groupDesc $approveGroupDescAD -groupMemberGroup $approveGroupNameGroups `
					-OU $nameGenerator.getADGroupsOUDN($approveGroupInfos.onlyForTenant) -simulation $SIMULATION_MODE) -eq $false)
				{
					# Enregistrement du nom du groupe qui pose problème et on note de passer au service suivant car on ne peut pas créer celui-ci
					if($notifications['missingITSADGroups'] -notcontains $approveGroupNameGroups)
					{
						$notifications['missingITSADGroups'] += $approveGroupNameGroups
					}
						
					$allGroupsOK = $false
				}

			} # FIN BOUCLE de création des groupes pour les différents level d'approbation 
			
			# Si on n'a pas pu créer tous les groupes, on passe au service suivant 
			if($allGroupsOK -eq $false)
			{
				$counters.inc('its.serviceSkipped')
				continue
			}

			# --------------------------------- ROLES

			# Génération de nom du groupe dont on va avoir besoin pour les rôles "Admin" et "Support" (même groupe). 
			# Vu que c'est le même groupe pour les 2 rôles, on peut passer CSP_SUBTENANT_MANAGER ou CSP_SUPPORT aux fonctions, le résultat
			# sera le même
			$admSupGroupNameAD = $nameGenerator.getITSRoleADGroupName("CSP_SUBTENANT_MANAGER", $service.shortName)
			$admSupGroupDescAD = $nameGenerator.getITSRoleADGroupDesc("CSP_SUBTENANT_MANAGER", $service.longName, $service.snowId)
			$admSupGroupNameGroups = $nameGenerator.getITSRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER", $service.shortName)

			# Création des groupes + gestion des groupes prérequis 
			if((createADGroupWithContent -groupName $admSupGroupNameAD -groupDesc $admSupGroupDescAD -groupMemberGroup $admSupGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
				$notifications['missingITSADGroups'] += $admSupGroupNameGroups
				continue
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $admSupGroupNameAD



			# Génération de nom du groupe dont on va avoir besoin pour les rôles "User" et "Shared" (même groupe).
			# Vu que c'est le même groupe pour les 2 rôles, on peut passer CSP_CONSUMER_WITH_SHARED_ACCESS ou CSP_CONSUMER aux fonctions, le résultat
			# sera le même
			$userSharedGroupNameAD = $nameGenerator.getITSRoleADGroupName("CSP_CONSUMER", $service.shortName)
			$userSharedGroupDescAD = $nameGenerator.getITSRoleADGroupDesc("CSP_CONSUMER", $service.longName, $service.snowId)
			$userSharedGroupNameGroups = $nameGenerator.getITSRoleGroupsADGroupName("CSP_CONSUMER", $service.shortName)

			# Création des groupes + gestion des groupes prérequis 
			if((createADGroupWithContent -groupName $userSharedGroupNameAD -groupDesc $userSharedGroupDescAD -groupMemberGroup $userSharedGroupNameGroups `
				 -OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE) -eq $false)
			{
				# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
				$notifications['missingITSADGroups'] += $userSharedGroupNameGroups
				continue
			}
			# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
			$doneADGroupList += $userSharedGroupNameAD
			

		}# FIN BOUCLE de parcours des services renvoyés

	}# FIN SI on doit traiter le Tenant ITServices 

	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$notifications
	

	if($SIMULATION_MODE)
	{
		$logHistory.addLineAndDisplay("***************************************")
		$logHistory.addLineAndDisplay("** Script running in simulation mode **")
		$logHistory.addLineAndDisplay("***************************************")
	}
	else # Si on n'est pas en mode "Simulation", c'est qu'on a créé des éléments dans AD
	{
		# On lance donc une synchro mais après quelques secondes d'attente histoire que les groupes créés soient répliqués sur les autres DC. Si on va trop vite,
		# les groupes créés ne seront potentiellement pas synchronisés avec vRA... et ne pourront donc pas être utilisés pour les rôles des BG.
		$sleepDurationSec = 315
		$logHistory.addLineAndDisplay( ("Sleeping for {0} seconds to let Active Directory DC synchro working..." -f $sleepDurationSec))
		Start-Sleep -Seconds $sleepDurationSec
		try {
			# Création d'une connexion au serveur
			$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "server"), 
								 $targetTenant, 
								 $configVra.getConfigValue($targetEnv, $targetTenant, "user"), 
								 $configVra.getConfigValue($targetEnv, $targetTenant, "password"))
		}
		catch {
			Write-Error "Error connecting to vRA API !"
			Write-Error $_.ErrorDetails.Message
			exit
		}

		$logHistory.addLineAndDisplay("Syncing directory...")
		$vra.syncDirectory($nameGenerator.getDirectoryName())

		$vra.disconnect()
	}

	if($TEST_MODE)
	{
		$logHistory.addLineAndDisplay("*********************************")
		$logHistory.addLineAndDisplay("** Script running in TEST mode **")
		$logHistory.addLineAndDisplay("*********************************")
	}

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
	
	# Envoi d'un message d'erreur aux admins
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant $targetTenant
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters ))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
	
}	