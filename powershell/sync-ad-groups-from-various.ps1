<#
USAGES:
	sync-ad-groups-from-various.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl|research
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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ITServices.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "GroupsAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")
$configGrants = [ConfigReader]::New("config-grants.json")
$configGroups = [ConfigReader]::New("config-groups.json")

# Les types de rôles pour l'application Tableau
enum TableauRoles 
{
	User
	AdminFac
	AdminEPFL
}

# Types de sources pour les Business Group
enum ADGroupCreateSourceType {
	Admin
	User
}

<#
-------------------------------------------------------------------------------------
	BUT : Regarde si un groupe Active Directory existe et si ce n'est pas le cas, il 
		  est créé.

	IN  : $groupName				-> Nom du groupe à créer
	IN  : $groupDesc				-> Description du groupe à créer.
	IN  : $groupMemberGroup			-> Nom du groupe à ajouter dans le groupe $groupName
	IN  : $OU						-> OU Active Directory dans laquelle créer le groupe
	IN  : $simulation				-> $true|$false pour dire si on est en mode simulation ou pas.
	IN  : $updateExistingContent    -> $true|$false pour dire si on doit mettre à jour le contenu
										d'un groupe existant

	RET : $true	-> OK
		  $false -> le groupe ($groupMemberGroup) à ajouter dans le groupe $groupName 
		  			n'existe pas.
#>
function createADGroupWithContent([string]$groupName, [string]$groupDesc, [string]$groupMemberGroup, [string]$OU, [bool]$simulation, [bool]$updateExistingContent)
{
	 
	# Cette petite ligne permet de transformer les tirets style "MS Office" en tirets "normaux". Si on ne fait pas ça, on aura 
	# des problèmes par la suite dans vRA car ça pourrira le JSON...
	$groupDesc = $groupDesc -replace '–', '-'

	# On regarde si le groupe à ajouter dans le nouveau groupe existe
	if($null -eq (getADGroup -groupName $groupMemberGroup))
	{
		$logHistory.addWarningAndDisplay(("Inner group '{0}' has been created but still not available in AD (wait for sync), skipping AD group '{1}' creation for now!" -f $groupMemberGroup, $groupName))
		return $false
	}

	# Recherche du groupe qu'on doit créer
	$adGroup = getADGroup -groupName $groupName

	# Si le groupe n'existe pas encore 
	if($null -eq $adGroup)
	{
		$logHistory.addLineAndDisplay(("--> Creating AD group '{0}'..." -f $groupName))
		if(-not $simulation)
		{
			# Création du groupe
			New-ADGroup -Name $groupName -Description $groupDesc -GroupScope DomainLocal -Path $OU
		}
		$counters.inc('ADGroupsCreated')
	}
	else
	{
		$logHistory.addLineAndDisplay(("--> AD group '{0}' already exists" -f $groupName))
		
		if(-not $SIMULATION_MODE)
		{
			# Mise à jour de la description du groupe dans le cas où ça aurait changé
			if($adGroup.Description -ne $groupDesc)
			{
				$logHistory.addLineAndDisplay(("--> Updating AD group '{0}' description because it changed" -f $groupName))
				Set-ADGroup $groupName -Description $groupDesc -Confirm:$false
				$counters.inc('ADGroupsDescriptionUpdated')
			}
			
		}
	}

	# Si on arrive ici, c'est que le groupe à mettre dans le nouveau groupe AD existe

	
	# Si le groupe vient d'être CREE
	# OU
	# qu'il existe déjà et qu'on a le droit de mettre à jour son contenu,
	if( ($alreadyExists -eq $false) -or ($alreadyExists -and $updateExistingContent))
	{
		$logHistory.addLineAndDisplay(("--> Adding {0} member(s) to AD group..." -f $groupMemberGroup.Count))

		if(-not $simulation)
		{
			# Suppression des membres du groupes pour être sûr d'avoir des groupes à jour
			Get-ADGroupMember $groupName | ForEach-Object {Remove-ADGroupMember $groupName $_ -Confirm:$false}
			# Et on remet les bons membres
			Add-ADGroupMember $groupName -Members $groupMemberGroup
		}
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
function handleNotifications([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$targetTenant)
{

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
				# Groupe active directory manquants pour création des éléments pour Tenant EPFL
				'missingEPFLADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=115605511"

					$mailSubject = "Error - Active Directory groups missing"

					$templateName = "ad-groups-missing-for-groups-creation"
				}

				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant ITS (approve)
				'missingITSADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=72516653"

					$mailSubject = "Error - Active Directory groups missing"

					$templateName = "ad-groups-missing-for-groups-creation"
				}

				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant Research
				'missingRSRCHADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.docUrl = "#"

					$mailSubject = "Error - Active Directory groups missing"

					$templateName = "ad-groups-missing-for-groups-creation"
				}

				# ---------------------------------------
				# Groupe active directory manquants pour création des éléments pour Tenant Research (user, approval) et ITServices (user)
				'missingADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")

					$mailSubject = "Info - Active Directory groups missing (please wait)"

					$templateName = "ad-groups-missing-for-groups-creation-wait"
				}

				# Unité 'Gestion' pas trouvée au niveau 4 pour une unité de niveau 3
				'level3GEUnitNotFound'
				{
					$valToReplace.unitList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=130975579"

					$mailSubject = "Error - Level 4 'GE' unit can't be identified, please proceed manually"

					$templateName = "level-4-ge-unit-not-found"
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
	BUT : Contrôle que les noms des comptes donnés existent bien dans AD. Si ce n'est pas le
			cas, ils sont supprimés de la liste.

	IN  : $accounts	-> tableau avec la liste des comptes à contrôler

	RET : Tableau avec la liste des comptes sans ceux qui n'existent pas dans AD
#>
function removeInexistingADAccounts([Array] $accounts)
{
	$validAccounts = @()

	ForEach($acc in $accounts)
	{
		try 
		{
			Get-ADUser $acc | Out-Null

			# Si on arrive ici, c'est que pas d'erreur donc compte trouvé.
			$validAccounts += $acc
		}
		catch 
		{
			$logHistory.addWarningAndDisplay(("User {0} doesn't have an account in Active directory" -f $acc ))
			$counters.inc('ADMembersNotFound')
		}
	}

	# On met une virgule pour forcer ce con de PowerShell a vraiment retourner un tableau. Si on ne fait pas ça et qu'on
	# a un tableau vide, ça sera transformé en $null ...
	return ,$validAccounts
}


<#
-------------------------------------------------------------------------------------
	BUT : Ajoute le contenu d'un groupe AD dans la table des utilisateurs vRA qui est
			utilisée pour gérer les accès à l'application Tableau.
			Pour le moment, on ne fait ceci que pour le tenant EPFL car c'est le seul
			qui est facturé

	IN  : $sqldb		-> Objet permettant d'accéder à la DB
	IN  : $ADGroup		-> Groupe AD avec les utilisateurs à ajouter
	IN  : $role			-> Role à donner aux utilisateurs du groupe
	IN  : $bgName		-> Nom du Business Group qui est accessible
					   		Peut être de la forme basique epfl_<faculty>_<unit>
					   		Ou alors simplement un seul élément si c'est un nom de faculté
	IN  : $targetTenant	-> Nom du tenant sur lequel on est.
							On gère uniquement les tenants ITServices et EPFL
#>
function updateVRAUsersForBG([SQLDB]$sqldb, [Array]$userList, [TableauRoles]$role, [string]$bgName, [string]$targetTenant)
{

	switch($role)
	{
		User
		{
			if($targetTenant -eq $global:VRA_TENANT__EPFL)
			{
				# Gère les noms  de BG au format epfl_<fac>_<unit>
				$regex = '^([a-z]+)_([a-z]+)_(\w+)'
			}
			elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
			{
				# Gère les noms  de BG au format its_<serviceShortName>
				$regex = '^([a-z]+)_([a-z0-9]+)'
			}
			else
			{
				Throw ("Tenant '{0}' not handled" -f $targetTenant)
			}
			
			# Extraction des infos ($dummy va contenir le nom comple du BG, dont on n'a pas besoin)
			$dummy, $criteriaList = [regex]::Match($bgName, $regex).Groups | Select-Object -ExpandProperty value
		}

		AdminFac
		{
			if($targetTenant -eq $global:VRA_TENANT__EPFL)
			{
				# Gère les noms  de BG au format epfl_<fac>
				$regex = '^([a-z]+)_([a-z]+)'
			}
			else
			{
				Throw ("Tenant '{0}' not handled" -f $targetTenant)
			}
			# Extraction des infos ($dummy va contenir le nom complte du BG, dont on n'a pas besoin)
			$dummy, $criteriaList = [regex]::Match($bgName, $regex).Groups | Select-Object -ExpandProperty value
		}

		AdminEPFL
		{
			# Pas besoin d'extraire les infos, car dans ce cas-là, $bgName contiendra juste "all"
			$criteriaList = @($bgName)
		}
	}
	

	# Ajout de critères vides pour avoir les 3 critères demandés
	While($criteriaList.Count -lt 3)
	{
		$criteriaList += ""
	}

	$criteriaConditions = @()
	For($i=0 ; $i -lt 3 ; $i++)
	{
		$criteriaConditions += "crit{0} = '{1}'" -f ($i+1), $criteriaList[$i]
	}

	# On commence par supprimer tous les utilisateurs du role donné pour le BG
	$request = "DELETE FROM vraUsers WHERE role='{0}' AND {1}" -f $role, ($criteriaConditions -join " AND ")
	$sqldb.execute($request) | Out-Null

	$baseRequest = "INSERT INTO vraUsers VALUES"
	$rows = @()

	# Suppression des "itadmin-" au début des noms d'utilisateur et on ne prend que les "unique" pour éviter d'éventuelles collisions
	$uniqueUserList = $userList | Foreach-Object { $_ -replace "^itadmin-", "" } | Sort-Object | Get-Unique

	# Boucle sur les utilisateurs à ajouter
	ForEach($user in $uniqueUserList)
	{
		# Le 1 qu'on ajoute à la fin, c'est pour la colonne 'link'. Cette valeur est constante et elle doit être ajoutée
		# pour le bon fonctionnement de Tableau et son interfaçage avec les utilisateurs de vRA
		$rows += "('{0}', '{1}', '{2}', '1' )" -f $user, $role.ToString(), ($criteriaList -join "', '")
		$counters.inc('membersAddedTovRAUsers')

		# Si on arrive à un groupe de 10 éléments
		if($rows.Count -eq 20)
		{
			# On créé la requête et on l'exécute
			$request = "{0}{1}" -f $baseRequest, ($rows -join ",")
			$sqldb.execute($request) | Out-Null
			$rows = @()
		}
		
	}

	# S'il reste des éléments à ajouter
	if($rows.Count -gt 0)
	{
		$request = "{0}{1}" -f $baseRequest, ($rows -join ",")
		$sqldb.execute($request) | Out-Null
	}

	

}


<#
-------------------------------------------------------------------------------------
	BUT : Créé un groupe dans Groups (s'il n'existe pas)

	IN  : $groupsApp			-> Objet permettant d'accéder à l'API des groups
	IN  : $name					-> Nom du groupe
	IN  : $desc					-> Description du groupe
	IN  : $memberSciperList		-> Tableau avec la liste des scipers des membres du groupe
	IN  : $adminSciperList		-> Tableau avec la liste des scipers des admins du groupe

	RET : Le groupe
#>
function createGroupsGroupWithContent([GroupsAPI]$groupsApp, [string]$name, [string]$desc, [Array]$memberSciperList, [Array]$adminSciperList)
{
	# Recherche du groupe pour voir s'il existe
	$group = $groupsApp.getGroupByName($name, $true)

	# Si le groupe n'existe pas, 
	if($null -eq $group)
	{
		
		$counters.inc('groupsGroupsCreated')

		# Ajout du groupe
		$logHistory.addLineAndDisplay(("--> Creating groups group '{0}'..." -f $name))
		$options = @{
			maillist = '0'
		}
		$group = $groupsApp.addGroup($name, $desc, "", $options)

		# Ajout des membres
		if($memberSciperList.count -gt 0)
		{
			$logHistory.addLineAndDisplay(("--> Adding {0} members..." -f $memberSciperList.count))
			$groupsApp.addMembers($group.id, $memberSciperList)
		}
		
		# Ajout des admins
		if($adminSciperList.count -gt 0)
		{
			$logHistory.addLineAndDisplay(("--> Adding {0} admins..." -f $adminSciperList.count))
			$groupsApp.addAdmins($group.id, $adminSciperList)
		}
		
		# Suppression du membre ajouté par défaut (celui du "caller", ajouté automatiquement à la création)
		$groupsApp.removeMember($group.id, $groupsApp.getCallerSciper())

		# Récupération du groupe
		$group = $groupsApp.getGroupById($group.id)
	}
	else # le groupe exists
	{
		$logHistory.addLineAndDisplay(("--> Groups group '{0}' already exists" -f $name))
	}

	return $group
}


<#
-------------------------------------------------------------------------------------
	BUT : Détermine quel est le centre financier à utiliser pour une unité. Ceci
			peut être un numéro de centre financier existant ou alors une adresse
			mail à laquelle les informations vont être envoyées.
			Si on n'a pas pu déterminer le centre financier avec les directives
			définies dans le fichier JSON ($billToMailList), on essaie de trouver 
			l'unité de niveau 4 (car on est probablement sur une unité de niveau 3)
			afin de récupérer le centre financier de celle-ci.

	IN  : $unit					-> Objet représentant l'unité que l'on est en train de 
									traiter
	IN  : $unitList				-> Liste des unités, afin de pouvoir potentiellement chercher
									une unité de niveau 4 pour un centre (niveau 3) afin 
									de pouvoir faire de la facturation
	IN  : $billToMailList		-> Tableau avec les informations sur les directives
									de facturation définies dans un fichier JSON.
	IN  : $sourceType			-> Type de source pour les unités (User ou admin)
	IN  : $geUnitMappingList	-> Objet avec les informations sur le mapping d'unité de gestion.
									Le contenu provient du fichier 'data/billing/ge-unit-mapping.json'

	RET : Le centre financier à utiliser pour l'unité
#>
function determineUnitFinanceCenter([PSCustomObject]$unit, [Array]$unitList, [Array]$billToMailList, [ADGroupCreateSourceType]$sourceType, [PSCustomObject]$geUnitMappingList)
{
	# Si on est dans la source d'unités "admin" 
	if($sourceType -eq [ADGroupCreateSourceType]::Admin)
	{
		# On retourne l'adresse mail entrée pour la facturation
		return $unit.billingMail
	}
	

	# 1. Si on doit utiliser une adresse mail pour la facturation au lieu du centre financier
	$financeCenter = $null
	ForEach($billToMail in $billToMailList)
	{
		# Parcours des OU de l'entrées courante
		ForEach($LDAPOU in $billToMail.ldapOuList)
		{
			# Si l'unité courante se trouve sous l'arbo pour laquelle il faut utiliser une adresse mail pour la facturation
			if($unit.path -match ("{0}$" -f $LDAPOU))
			{
				# Si on a une adresse mail hardcodée de donnée,
				if($null -ne $billToMail.billingMail)
				{
					$financeCenter = $billToMail.billingMail
				}
				# On doit utiliser une fonction pour récupérer l'adresse mail.
				elseif($null -ne $billToMail.billingMailFunc)
				{
					Invoke-Expression ('$financeCenter = {0} -unitInfos $unit' -f $billToMail.billingMailFunc)
					
				}
				else # Valeurs dans le fichiers JSON incorrectes
				{
					Throw ("Incorrect value combination in 'billing to mail' JSON file for OU '{0}'" -f $LDAPOU)
				}

				$logHistory.addLineAndDisplay(("--> Using email ({0}) for finance center..." -f $financeCenter))
				
				break
			}
		}
		# SI on a trouvé une adresse mail pour la facturation
		if($null -ne $financeCenter)
		{
			# On peut sortir de la boucle
			break
		}
	}# FIN BOUCLE de parcours des possibilité de facturation par mail


	# Si on n'a pas encore de centre financier de défini (donc pas d'adresse mail )
	if($null -eq $financeCenter)
	{
		# Si c'est une unité de niveau 3 (centre), on doit chercher l'unité de niveau 4 qui fait office de "gestion"
		if($unit.level -eq 3)
		{
			$logHistory.addLineAndDisplay("--> Level 3 unit (Center), looking for level 4 'GE' unit for finance center..." )

			# Noms d'unité à rechercher. On cherche de plusieurs manières parce qu'ils ont été incapables de nommer ça d'une façon cohérente...
			$geUnitNameList = @( ("{0}-GE" -f $unit.name)
								("{0}-GE" -f [Regex]::match($unit.name, '[A-Za-z]+-(.*)').groups[1].value) )

			# Ajout d'un potentiel mapping hard-codé dans le fichier JSON
			$geUnitNameList += ($geUnitMappingList | Where-Object { $_.level3Center -eq $unit.name }).level4GeUnit

			# Suppression des valeurs vides (oui, il peut y en avoir on dirait... )
			$geUnitNameList = $geUnitNameList | Where-Object { $_ -ne "" -and $null -ne $_ }
			$financeCenter = $null

			# Parcours des noms d'unité de "Gestion" pour voir si on trouve quelque chose
			ForEach($geUnitName in $geUnitNameList)
			{
				$logHistory.addLineAndDisplay(("---> Looking for '{0}' unit..." -f $geUnitName))
				$geUnit = $unitList | Where-Object { $_.name -eq $geUnitName }

				if($null -ne $geUnit)
				{
					$logHistory.addLineAndDisplay("---> Unit found, getting finance center")
					$financeCenter = $geUnit.accountingnumber
					break
				}
			}

			# Si on n'a rien trouvé... 
			if($null -eq $financeCenter)
			{
				$logHistory.addLineAndDisplay("--> 'GE' unit not found... using 'normal' finance center")
				$financeCenter = $unit.accountingnumber
				$counters.inc('level3GEUnitNotFound')
				# Ajout du nom de l'unité niveau 3 pour notifier par mail que pas trouvée
				$notifications.level3GEUnitNotFound += $unit.name
			}
		}
		else # Ce n'est pas une unité de niveau 3 (centre)
		{
			$financeCenter = $unit.accountingnumber
		}

	}# FIN SI on n'a pas encore de centre financier

	return $financeCenter

}

<#
-------------------------------------------------------------------------------------
	BUT : Renvoie l'adresse mail à utiliser pour la facturation d'une unité dont 
			les infos sont passées en paramètre

	IN  : $unitInfos	-> Objet avec les informations de l'unité (vient de LDAP,
							renvoyé par la fonction getFacultyUnitList() )

	RET : L'adresse mail
#>
function getSIUnitBillingMail([PSObject]$unitInfos)
{
	return "personnel.{0}@epfl.ch" -f $unitInfos.name.toLower()
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
$RESEARCH_TEST_NB_PROJECTS_MAX = 5


# CONFIGURATION
# ******************************************


try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logName = 'vra-sync-AD-from-LDAP-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()
	$logHistory = [LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups" ainsi que d'autre choses...
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
		targetTenant = $targetTenant
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

	# Pour s'interfacer avec l'application Groups
	$groupsApp = [GroupsAPI]::new($configGroups.getConfigValue(@($targetEnv, "server")),
								  $configGroups.getConfigValue(@($targetEnv, "appName")),
								   $configGroups.getConfigValue(@($targetEnv, "callerSciper")),
								   $configGroups.getConfigValue(@($targetEnv, "password")))
	
	# Pour accéder à la base de données
	$sqldb = [SQLDB]::new([DBType]::MSSQL, 
							$configVra.getConfigValue(@($targetEnv, "db", "host")),
							$configVra.getConfigValue(@($targetEnv, "db", "dbName")),
							$configVra.getConfigValue(@($targetEnv, "db", "user")), 
							$configVra.getConfigValue(@($targetEnv, "db", "password")),
							$configVra.getConfigValue(@($targetEnv, "db", "port")))

	Import-Module ActiveDirectory

	if($SIMULATION_MODE)
	{
		$logHistory.addWarningAndDisplay("***************************************")
		$logHistory.addWarningAndDisplay("** Script running in simulation mode **")
		$logHistory.addWarningAndDisplay("***************************************")
	}
	if($TEST_MODE)
	{
		$logHistory.addWarningAndDisplay("*********************************")
		$logHistory.addWarningAndDisplay("** Script running in TEST mode **")
		$logHistory.addWarningAndDisplay("*********************************")
	}

	# Liste des groupes AD traités par le script
	$doneADGroupList = @()
	
	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
	$counters.add('ADGroupsCreated', '# AD Groups created')
	$counters.add('ADGroupsDescriptionUpdated', '# AD Group descriptions updated')
	$counters.add('ADGroupsExists', '# AD Groups already existing')
	$counters.add('ADGroupsRemoved', '# AD Groups removed')
	$counters.add('ADGroupsContentUpdated', '# AD Groups updated')
	$counters.add('ADGroupsContentOK', '# AD Groups OK')
	$counters.add('ADMembersNotFound', '# AD members not found')
	$counters.add('groupsGroupsCreated', '# Groups groups created')
	$counters.add('membersAddedTovRAUsers', '# Users added to vraUsers table (Tableau)')
	$counters.add('level3GEUnitNotFound', '# level 3 GE unit not found')

	<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
	$notifications = @{}
	$notifications.level3GEUnitNotFound = @()
	$notifications.missingADGroups = @()

	# Chargement des informations sur les unités qu'il faut ajouter manuellement à une faculté donnée
	$adminBGFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "admin-bg.json"))
	$adminBGList = loadFromCommentedJSON -jsonFile $adminBGFile

	switch($targetTenant)
	{
		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# --------------------------------------------------------- TENANT EPFL ---------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		$global:VRA_TENANT__EPFL 
		{
			$logHistory.addLineAndDisplay("Processing data for EPFL Tenant")

			# Ajout des compteurs propres au tenant
			$counters.add('epfl.facProcessed', '# Faculty processed')
			$counters.add('epfl.facSkipped', '# Faculty skipped')
			$counters.add('epfl.facIgnored', '# Faculty ignored (because of filter)')
			$counters.add('epfl.LDAPUnitsProcessed', '# LDAP Units processed')
			$counters.add('epfl.ManualUnitsProcessed', '# Manual Units processed')
			$counters.add('epfl.LDAPUnitsEmpty', '# LDAP Units empty')

			# Ajout du nécessaire pour gérer les notifications pour ce Tenant
			$notifications.missingEPFLADGroups = @()

			# Pour faire les recherches dans LDAP
			$ldap = [EPFLLDAP]::new()

			# Recherche de toutes les facultés
			$facultyList = $ldap.getLDAPFacultyList() #  | Where-Object { $_['name'] -eq "ASSOCIATIONS" } # Décommenter et modifier pour limiter à une faculté donnée

			$exitFacLoop = $false

			# Chargement des informations sur le mapping des facultés
			# FIXME: Voir si c'est toujours pertinent après avoir mergé la PR https://github.com/epfl-si/xaas-admin/pull/109
			$geUnitMappingFile = ([IO.Path]::Combine($global:DATA_FOLDER, "billing", "ge-unit-mapping.json"))
			$geUnitMappingList = loadFromCommentedJSON -jsonFile $geUnitMappingFile

			# Chargement des informations sur les unités qui doivent être facturées sur une adresse mail
			$billToMailFile = ([IO.Path]::Combine($global:DATA_FOLDER, "billing", "bill-to-mail.json"))
			$billToMailList = loadFromCommentedJSON -jsonFile $billToMailFile
			
			# Chargement des informations sur les unités qui ont potentiellement des services vRA "non autorisés"
			$deniedVRASvcListFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "epfl-deny-vra-services.json"))
			$deniedVRASvcList = loadFromCommentedJSON -jsonFile $deniedVRASvcListFile
			

			# Parcours des facultés trouvées
			ForEach($faculty in $facultyList)
			{
				$counters.inc('epfl.facProcessed')
				$logHistory.addLineAndDisplay(("[{0}/{1}] Faculty {2}..." -f $counters.get('epfl.facProcessed'), $facultyList.Count, $faculty['name']))
				
				# ----------------------------------------------------------------------------------
				# --------------------------------- FACULTE
				# ----------------------------------------------------------------------------------

				# Initialisation des détails pour le générateur de noms 
				# NOTE: On ne connait pas encore toutes les informations donc on initialise 
				# avec juste celles qui sont nécessaires pour la suite. Le reste, on met une
				# chaîne vide.
				$nameGenerator.initDetails(@{facultyName = $faculty['name']
											facultyID = $faculty['uniqueidentifier']
											unitName = ''
											unitID = ''})
				
				# --------------------------------- APPROVE

				$allGroupsOK = $true
				# Génération des noms des X groupes dont on va avoir besoin pour approuver les NOUVELLES demandes pour la faculté 
				$level = 0
				while($true)
				{
					$level += 1
					$approveGroupInfos = $nameGenerator.getApproveADGroupName($level, $false)

					# S'il n'y a plus de groupe pour le level courant, on sort
					if($null -eq $approveGroupInfos)
					{
						break
					}
					
					$approveGroupDescAD = $nameGenerator.getApproveADGroupDesc($level)
					$approveGroupNameGroups = $nameGenerator.getApproveGroupsADGroupName($level, $false)

					# Création des groupes + gestion des groupes prérequis 
					if((createADGroupWithContent -groupName $approveGroupInfos.name -groupDesc $approveGroupDescAD -groupMemberGroup $approveGroupNameGroups `
						-OU $nameGenerator.getADGroupsOUDN($approveGroupInfos.onlyForTenant, [ADSubOUType]::Approval) -simulation $SIMULATION_MODE -updateExistingContent $true) -eq $false)
					{
						if($notifications.missingEPFLADGroups -notcontains $approveGroupNameGroups)
						{
							# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
							$notifications.missingEPFLADGroups += $approveGroupNameGroups
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
				$adminGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_SUBTENANT_MANAGER", $false)
				$adminGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_SUBTENANT_MANAGER")
				$adminGroupNameGroups = $nameGenerator.getRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER")

				$supportGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_SUPPORT", $false)
				$supportGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_SUPPORT")
				$supportGroupNameGroups = $nameGenerator.getRoleGroupsADGroupName("CSP_SUPPORT")

				# Création des groupes + gestion des groupes prérequis 
				if((createADGroupWithContent -groupName $adminGroupNameAD -groupDesc $adminGroupDescAD -groupMemberGroup $adminGroupNameGroups `
					-OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE -updateExistingContent $false) -eq $false)
				{
					# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
					$notifications.missingEPFLADGroups += $adminGroupNameGroups
					break
				}
				# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
				$doneADGroupList += $adminGroupNameAD


				if((createADGroupWithContent -groupName $supportGroupNameAD -groupDesc $supportGroupDescAD -groupMemberGroup $supportGroupNameGroups `
					-OU $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::Support) -simulation $SIMULATION_MODE -updateExistingContent $false) -eq $false)
				{
					# Enregistrement du nom du groupe qui pose problème et passage à la faculté suivante car on ne peut pas créer celle-ci
					$notifications.missingEPFLADGroups += $supportGroupNameGroups
					break
				}
				# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
				$doneADGroupList += $supportGroupNameAD



				# ----------------------------------------------------------------------------------
				# --------------------------------- UNITÉS
				# ----------------------------------------------------------------------------------
				# Recherche des unités pour la facultés
				$unitList = @{}
				$unitList.add([ADGroupCreateSourceType]::User, $ldap.getFacultyUnitList($faculty.name, $EPFL_FAC_UNIT_NB_LEVEL)) # | Where-Object { $_['name'] -eq 'OSUL'} # Décommenter et adapter pour limiter à une unité donnée
					
				# On regarde si on a des unités à ajouter en tant que BG "admin" à la faculté courante. 
				$manualUnitsFacInfos = $adminBGList.$targetTenant | Where-Object { $_.faculty -eq $faculty.name }
				if(($null -ne $manualUnitsFacInfos) -and ($manualUnitsFacInfos.manualUnits.count -gt 0))
				{
					$logHistory.addLineAndDisplay(("Adding {0} 'admin units' to faculty {1} unit list" -f $manualUnitsFacInfos.manualUnits.count, $faculty.name))
					$unitList.add([ADGroupCreateSourceType]::Admin, @($manualUnitsFacInfos.manualUnits))
				}

				

				# Parcours des types de sources
				Foreach($sourceType in $unitList.keys)
				{
					$logHistory.addLineAndDisplay(("Processing '{0}' units ({1} units found)..." -f $sourceType.toString(), $unitList.$sourceType.count))
				
					$unitNo = 1

					# Parcours des unités de la faculté
					ForEach($unit in $unitList.$sourceType)
					{
						$logHistory.addLineAndDisplay(("-> [{0}/{1}] Unit {2} => {3}..." -f $unitNo, $unitList.$sourceType.Count, $faculty.name, $unit.name))

						# Recherche du centre financier à utiliser
						$financeCenter = determineUnitFinanceCenter -unit $unit -unitList $unitList.$sourceType -billToMailList $billToMailList `
										-sourceType $sourceType -geUnitMappingList $geUnitMappingList

						$vRAServicesToDeny = @()
						# On ne gère les "deny" de service/items de catalogue uniquement si on est dans une source pour les utilisateurs
						if($sourceType -eq [ADGroupCreateSourceType]::User)
						{
							$hasApproval = $true
							# Parcours des OU pour lequelles on veut empêcher l'accès à certains services vRA
							ForEach($denyInfos in $deniedVRASvcList)
							{
								# Si l'unité courante est dans l'arborescence où il faut empêcher l'accès à certains services
								if($unit.path -match ("{0}$" -f $denyInfos.ldapOU))
								{
									# Mise à jour de la liste des services "non" autorisés et on sort
									$vRAServicesToDeny = $denyInfos.deniedVRAServiceList
									break
								}
							}

							$logHistory.addLineAndDisplay(("--> Normal unit, taking users from LDAP"))
							# Recherche des membres de l'unité
							$ldapMemberList = $ldap.getUnitMembers($unit.uniqueidentifier)

							# On commence par filtrer les comptes pour savoir s'ils existent tous
							$ldapMemberList = removeInexistingADAccounts -accounts $ldapMemberList

						}
						else # C'est une unité "admin"
						{
							# Les membres à mettre dans le groupe sont définis par le contenu du groupe AD donné dans le JSON
							$logHistory.addLineAndDisplay(("--> Manual unit, taking users from group defined in JSON file ({0})" -f $unit.contentGroup))
							$ldapMemberList = Get-ADGroupMember $unit.contentGroup -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique 

							# Pas d'approbation pour les unités "Admin"
							$hasApproval = $false
						}
						

						# Initialisation des détails pour le générateur de noms
						$nameGenerator.initDetails(@{facultyName = $faculty.name
												facultyID = $faculty.uniqueidentifier
												unitName = $unit.name
												unitID = $unit.uniqueidentifier})

						# Création du nom du groupe AD et de la description
						$adGroupName = $nameGenerator.getRoleADGroupName("CSP_CONSUMER", $false)
						$additionalDetails = @{
							deniedVRASvc = $vRAServicesToDeny
							financeCenter = $financeCenter
							hasApproval = $hasApproval
						}
						$adGroupDesc = $nameGenerator.getRoleADGroupDesc("CSP_CONSUMER", $additionalDetails)

						try
						{
							# On tente de récupérer le groupe (on met dans une variable juste pour que ça ne s'affiche pas à l'écran)
							Get-ADGroup -Identity $adGroupName | Out-Null

							$adGroupExists = $true
							$counters.inc('ADGroupsExists')
							$logHistory.addLineAndDisplay(("--> Group exists ({0}) " -f $adGroupName))

							if(-not $SIMULATION_MODE)
							{
								# Mise à jour de la description du groupe dans le cas où ça aurait changé
								Set-ADGroup $adGroupName -Description $adGroupDesc -Confirm:$false
							}

							# Listing des usernames des utilisateurs présents dans le groupe
							$adMemberList = @(Get-ADGroupMember $adGroupName | ForEach-Object {$_.SamAccountName})

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
									New-ADGroup -Name $adGroupName -Description $adGroupDesc -GroupScope DomainLocal -Path $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::User)
								}

								$counters.inc('ADGroupsCreated')

								$adGroupExists = $true
								# le groupe est vide.
								$adMemberList = @()
							}
							else # Pas de membres donc on ne créé pas le groupe
							{
								$logHistory.addLineAndDisplay(("--> No members in unit '{0}', skipping group creation " -f $unit.name))
								$counters.inc('epfl.LDAPUnitsEmpty')
								$adGroupExists = $false
							}

						}# FIN CATCH le groupe n'existe pas

						# Si le groupe AD existe
						if($adGroupExists)
						{
							# On compare les 2 listes et on récupère les informations de différence
							$comparisonResult = (Compare-Object -ReferenceObject $ldapMemberList -DifferenceObject $adMemberList)

							# Si les membres présents dans le groupe AD ne sont pas les mêmes que ceux qui devraient y être
							if($null -ne $comparisonResult)
							{
								$toRemove = @($comparisonResult | Where-Object { $_.SideIndicator -eq "=>" } | Select-Object -ExpandProperty InputObject)
								# On commence par supprimer les membres qui ne doivent pas être dans le groupe, s'il y en a
								if($toRemove.count -gt 0)
								{
									$logHistory.addLineAndDisplay(("--> Removing {0} member(s) in group '{1}'..." -f $toRemove.count, $adGroupName))
									if(-not $SIMULATION_MODE)
									{
										Remove-ADGroupMember $adGroupName -Members $toRemove -confirm:$false
									}
								}
								
								$toAdd = @($comparisonResult | Where-Object { $_.SideIndicator -eq "<=" } | Select-Object -ExpandProperty InputObject)
								# Ajout des membres qui manquent
								if($toAdd.count -gt 0)
								{
									$logHistory.addLineAndDisplay(("--> Adding {0} member(s) in group '{1}'..." -f $toAdd.count, $adGroupName))
									if(-not $SIMULATION_MODE)
									{
										Add-ADGroupMember $adGroupName -Members $toAdd
									}

									$counters.inc('ADGroupsContentUpdated')
								}

								# Si le groupe ne doit contenir aucun membre, et donc que l'unité est vide
								if($ldapMemberList.count -eq 0)
								{
									$logHistory.addLineAndDisplay(("--> AD group '{0}' is empty, removing it..." -f $adGroupName))
									if(-not $SIMULATION_MODE)
									{
										# Comme on a vidé le groupe juste avant s'il contenait des membres et que là on n'a rien à ajouter dedans,
										# on peut supprimer le groupe
										Remove-ADGroup $adGroupName -Confirm:$false
									}

									$counters.inc('ADGroupsRemoved')
								}
								
							}
							else # Le contenu du groupe AD est à jour
							{
								$logHistory.addLineAndDisplay(("--> AD Group '{0}' is up-to-date" -f $adGroupName))
								$counters.inc('ADGroupsContentOK')
							}

							# On enregistre le nom du groupe AD traité
							$doneADGroupList += $adGroupName

						} # FIN SI le groupe AD existe

						###### Roles pour Tableau --> Utilisateurs dans les Business Groups
						# Si l'unité courante a des membres
						if($ldapMemberList.Count -gt 0)
						{
							$logHistory.addLineAndDisplay(("--> Adding {0} members with '{1}' role to vraUsers table " -f $ldapMemberList.Count, [TableauRoles]::User.ToString()))
							updateVRAUsersForBG -sqldb $sqldb -userList $ldapMemberList -role User -bgName $nameGenerator.getBGName() -targetTenant $targetTenant
						}

						# Mise à jour des compteurs
						if($sourceType -eq [ADGroupCreateSourceType]::User)
						{
							$counters.inc('epfl.LDAPUnitsProcessed')
						}
						else
						{
							$counters.inc('epfl.ManualUnitsProcessed')
						}
						
						$unitNo += 1

						# Pour faire des tests
						if($TEST_MODE -and ($counters.get('epfl.LDAPUnitsProcessed') -ge $EPFL_TEST_NB_UNITS_MAX))
						{
							$exitFacLoop = $true
							break
						}

					}# FIN BOUCLE de parcours des unités de la faculté

				} # FIN BOUCLE de parcours des types unités (automatiques ou manuelles)

				###### Roles pour Tableau --> Admin de faculté
				# Recherche du nom du groupe AD d'approbation pour la faculté
				$facApprovalGroup = $nameGenerator.getApproveADGroupName(2, $false).name

				# Recherche de la liste des membres
				$facApprovalMembers = Get-ADGroupMember $facApprovalGroup -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique 

				if($facApprovalMembers.Count -gt 0)
				{
					$logHistory.addLineAndDisplay(("--> Adding {0} members with '{1}' role to vraUsers table " -f $facApprovalMembers.Count, [TableauRoles]::AdminFac.ToString() ))
					if(-not $SIMULATION_MODE)
					{
						updateVRAUsersForBG -sqldb $sqldb -userList $facApprovalMembers -role AdminFac -bgName ("epfl_{0}" -f $faculty.name.toLower()) -targetTenant $targetTenant
					}
				}

				if($exitFacLoop)
				{
					Write-Warning "Breaking faculty loop for test purpose"
					break
				}

			}# FIN BOUCLE de parcours des facultés

			###### Roles pour Tableau --> Admin du service
			# Recherche du nom du groupe AD d'approbation pour la faculté
			$adminGroup = $nameGenerator.getRoleADGroupName("CSP_SUBTENANT_MANAGER", $false)

			# Recherche de la liste des membres
			$adminMembers = Get-ADGroupMember $adminGroup -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique 

			# Ajout des membres du groupe https://groups.epfl.ch contenant les admins de Tableau
			$adminMembers += Get-ADGroupMember $nameGenerator.getTableauAdminEPFLADGroup() -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique 

			# Suppression des doublons
			$adminMembers = $adminMembers | Sort-Object | Get-Unique
			
			if($adminMembers.Count -gt 0)
			{
				$logHistory.addLineAndDisplay(("--> Adding {0} members with '{1}' role to vraUsers table " -f $adminMembers.Count, [TableauRoles]::AdminEPFL.ToString() ))
				if(-not $SIMULATION_MODE)
				{
					updateVRAUsersForBG -sqldb $sqldb -userList $adminMembers -role AdminEPFL -bgName "all" -targetTenant $targetTenant
				}
			}
			
		}# FIN SI Tenant EPFL

		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# ------------------------------------------------------ TENANT ITSERVICES ------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		$global:VRA_TENANT__ITSERVICES 

		{
			$logHistory.addLineAndDisplay("Processing data for ITServices Tenant")
	
			# Ajout des compteurs propres au tenant
			$counters.add('its.serviceProcessed', '# Service processed')
			$counters.add('its.serviceSkipped', '# Service skipped')
	
			# Objet pour lire les informations sur le services IT
			$itServices = [ITServices]::new()

			$notifications.missingITSADGroups = @()
			
			$servicesList = @{}

			# On prend la liste correspondant à l'environnement sur lequel on se trouve
			$servicesList.add([ADGroupCreateSourceType]::User, $itServices.getServiceList($targetEnv))
			
			# Ajout des services à ajouter en tant que "Admin"
			$logHistory.addLineAndDisplay(("Adding {0} 'admin services'" -f $adminBGList.$targetTenant.count))
			$servicesList.add([ADGroupCreateSourceType]::Admin, @($adminBGList.$targetTenant))
			

			# Parcours des types de sources
			Foreach($sourceType in $servicesList.keys)
			{

				$logHistory.addLineAndDisplay(("Processing '{0}' services ({1} found)..." -f $sourceType.toString(), $servicesList.$sourceType.count))
				$serviceNo = 1 
				# Parcours des services 
				ForEach($service in $servicesList.$sourceType)
				{
		
					$logHistory.addLineAndDisplay(("-> [{0}/{1}] Service {2}..." -f $serviceNo, $servicesList.$sourceType.Count, $service.shortName))
		
					$counters.inc('its.serviceProcessed')
		
					$groupsContentAndAdmin = @()

					if($service.serviceManagerSciper -ne "")
					{
						$groupsContentAndAdmin = @($service.serviceManagerSciper)
					}

					# Service de type "User"
					if($sourceType -eq [ADGroupCreateSourceType]::User)
					{
						$deniedVRAServiceList = $service.deniedVRAServiceList
						$hasApproval = $true
					}
					else # Service de type "Admin"
					{
						# Aucun service restreint
						$deniedVRAServiceList = @()
						$hasApproval = $false
					}

					# Initialisation des détails pour le générateur de noms
					$nameGenerator.initDetails(@{serviceShortName = $service.shortName
												serviceName = $service.longName
												snowServiceId = $service.snowId})
		
					$serviceNo += 1

					# --------------------------------- APPROVE
					$allGroupsOK = $true
					# Génération des noms des X groupes dont on va avoir besoin pour approuver les NOUVELLES demandes pour le service. 
					$level = 0
					while($true)
					{
						$level += 1
						# Recherche des informations pour le level courant.
						$approveGroupInfos = $nameGenerator.getApproveADGroupName($level, $false)
		
						# Si vide, c'est qu'on a atteint le niveau max pour les level
						if($null -eq $approveGroupInfos)
						{
							break
						}
		
						$approveGroupDescAD = $nameGenerator.getApproveADGroupDesc($level)
						$approveGroupNameGroups = $nameGenerator.getApproveGroupsADGroupName($level, $false)

						# Création des groupes + gestion des groupes prérequis 
						if((createADGroupWithContent -groupName $approveGroupInfos.name -groupDesc $approveGroupDescAD -groupMemberGroup $approveGroupNameGroups `
							-OU $nameGenerator.getADGroupsOUDN($approveGroupInfos.onlyForTenant, [ADSubOUType]::Approval) -simulation $SIMULATION_MODE -updateExistingContent $true) -eq $false)
						{
							# Enregistrement du nom du groupe qui pose problème et on note de passer au service suivant car on ne peut pas créer celui-ci
							if($notifications.missingITSADGroups -notcontains $approveGroupNameGroups)
							{
								$notifications.missingITSADGroups += $approveGroupNameGroups
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
					$admSupGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_SUBTENANT_MANAGER", $false)
					$admSupGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_SUBTENANT_MANAGER")
					$admSupGroupNameGroups = $nameGenerator.getRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER")
		
					# Création des groupes + gestion des groupes prérequis 
					if((createADGroupWithContent -groupName $admSupGroupNameAD -groupDesc $admSupGroupDescAD -groupMemberGroup $admSupGroupNameGroups `
						-OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE -updateExistingContent $false) -eq $false)
					{
						# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
						$notifications.missingITSADGroups += $admSupGroupNameGroups
						continue
					}
					# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
					$doneADGroupList += $admSupGroupNameAD
		
					# Génération de nom du groupe dont on va avoir besoin pour les rôles "User" et "Shared" (même groupe).
					# Vu que c'est le même groupe pour les 2 rôles, on peut passer CSP_CONSUMER_WITH_SHARED_ACCESS ou CSP_CONSUMER aux fonctions, le résultat
					# sera le même
					$userSharedGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_CONSUMER", $false)
					$additionalDetails = @{
						deniedVRASvc = $deniedVRAServiceList
						hasApproval = $hasApproval
					}
					$userSharedGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_CONSUMER", $additionalDetails)
					$userSharedGroupNameGroupsAD = $nameGenerator.getRoleGroupsADGroupName("CSP_CONSUMER")
		
					# Récupération des infos du groupe dans Groups
					$userSharedGroupNameGroups = $nameGenerator.getRoleGroupsGroupName("CSP_CONSUMER")
					$userSharedGroupDescGroups = $nameGenerator.getRoleGroupsGroupDesc("CSP_CONSUMER")
					

					# Création du groupe dans Groups s'il n'existe pas
					$requestGroupGroups = createGroupsGroupWithContent -groupsApp $groupsApp -name $userSharedGroupNameGroups -desc $userSharedGroupDescGroups `
																		-memberSciperList $groupsContentAndAdmin -adminSciperList $groupsContentAndAdmin

					# Création des groupes + gestion des groupes prérequis 
					if((createADGroupWithContent -groupName $userSharedGroupNameAD -groupDesc $userSharedGroupDescAD -groupMemberGroup $userSharedGroupNameGroupsAD `
						-OU $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::User) -simulation $SIMULATION_MODE -updateExistingContent $true) -eq $false)
					{
						# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
						if($notifications.missingADGroups -notcontains $userSharedGroupNameGroupsAD)
						{
							$notifications.missingADGroups += $userSharedGroupNameGroupsAD
						}
					}
					else
					{
						# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
						$doneADGroupList += $userSharedGroupNameAD
					}

					# ###### Roles pour Tableau --> Utilisateurs dans les Business Groups
					# if(($groupsUsernameList = Get-ADGroupMember $userSharedGroupNameAD -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique).count -gt 0)
					# {
					# 	$logHistory.addLineAndDisplay(("--> Adding {0} members with '{1}' role to vraUsers table " -f $groupsUsernameList.Count, [TableauRoles]::User.ToString() ))
					# 	updateVRAUsersForBG -sqldb $sqldb -userList $groupsUsernameList -role User -bgName $nameGenerator.getBGName() -targetTenant $targetTenant
					# }
					
					# # ###### Roles pour Tableau --> Admin du service
					# # Recherche de la liste des membres
					# if(($adminMembers = Get-ADGroupMember $admSupGroupNameAD -Recursive | ForEach-Object {$_.SamAccountName} | Get-Unique).Count -gt 0)
					# {
					# 	$logHistory.addLineAndDisplay(("--> Adding {0} members with '{1}' role to vraUsers table " -f $adminMembers.Count, [TableauRoles]::AdminEPFL.ToString() ))
					# 	updateVRAUsersForBG -sqldb $sqldb -userList $adminMembers -role AdminEPFL -bgName "all" -targetTenant $targetTenant
					# }
					
		
				}# FIN BOUCLE de parcours des services renvoyés

			}# FIN BOUCLE de parcours des types d sources pour la création des services
	
		}# FIN SI Tenant ITServices

		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# ------------------------------------------------------- TENANT RESEARCH -------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		# -------------------------------------------------------------------------------------------------------------------------------------
		$global:VRA_TENANT__RESEARCH
		{
			$logHistory.addLineAndDisplay("Retrieving projects list...")
	
			# Ajout du nécessaire pour gérer les notifications pour ce Tenant
			$notifications.missingRSRCHADGroups = @()
	
			# Ajout des compteurs propres au tenant
			$counters.add('rsrch.projectProcessed', '# Projects processed')
			$counters.add('rsrch.projectSkipped', '# Projects skipped')

			# Pour accéder à la base de données
			$mysqlGrants = [SQLDB]::new([DBType]::MySQL, 
										$configGrants.getConfigValue(@($targetEnv, "host")),
										$configGrants.getConfigValue(@($targetEnv, "dbName")),
										$configGrants.getConfigValue(@($targetEnv, "user")),
										$configGrants.getConfigValue(@($targetEnv, "password")),
										$configGrants.getConfigValue(@($targetEnv, "port")))

			$projectList = $mysqlGrants.execute("SELECT * FROM v_gdb_iaas WHERE subsides_start_date <= DATE(NOW()) AND subsides_end_date > DATE(NOW())")
			# Décommenter la ligne suivante et éditer l'ID pour simuler la disparition d'un projet
			#$projectList = $projectList | Where-Object { $_.id -ne "4387"}
			
			$projectNo = 1 
			# Parcours des services renvoyés par Django
			ForEach($project in $projectList)
			{
	
				$logHistory.addLineAndDisplay(("-> [{0}/{1}] Project {2}..." -f $projectNo, $projectList.Count, $project.id))
	
				$counters.inc('rsrch.projectProcessed')
	
				# Initialisation des détails pour le générateur de noms
				$nameGenerator.initDetails(@{projectId = $project.id
											projectAcronym = $project.acronym})
	
				$projectNo += 1
	
				# On détermine le sciper de l'admin du projet
				if($project.pi_sciper -ne [DBNull]::Value)
				{
					$projectAdminSciper = $project.pi_sciper
				}
				else
				{
					$projectAdminSciper = $project.pi_epfl_sciper
				}

				# --------------------------------- APPROVE
				$allApproveGroupsOK = $true
				# Génération des noms des X groupes dont on va avoir besoin pour approuver les NOUVELLES demandes pour le service. 
				$level = 0
				while($true)
				{
					$level += 1
					# Recherche des informations pour le level courant.
					$approveGroupInfos = $nameGenerator.getApproveADGroupName($level, $false)
	
					# Si vide, c'est qu'on a atteint le niveau max pour les level
					if($null -eq $approveGroupInfos)
					{
						break
					}
	
					$approveGroupDescAD = $nameGenerator.getApproveADGroupDesc($level)
					$approveGroupNameGroupsAD = $nameGenerator.getApproveGroupsADGroupName($level, $false)

					# Si on est au moins au 2e niveau d'approbation
					if($level -gt 1)
					{
						# Récupération des infos du groupe dans Groups
						$approveGroupNameGroups = $nameGenerator.getApproveGroupsGroupName($level, $false).name
						$approveGroupDescGroups = $nameGenerator.getApproveGroupsGroupDesc($level)

						# Création du groupe dans Groups s'il n'existe pas
						$approveGroupGroups = createGroupsGroupWithContent -groupsApp $groupsApp -name $approveGroupNameGroups -desc $approveGroupDescGroups `
																			-memberSciperList @($projectAdminSciper) -adminSciperList @($projectAdminSciper)
					}
					
					# Création des groupes + gestion des groupes prérequis 
					if((createADGroupWithContent -groupName $approveGroupInfos.name -groupDesc $approveGroupDescAD -groupMemberGroup $approveGroupNameGroupsAD `
						-OU $nameGenerator.getADGroupsOUDN($approveGroupInfos.onlyForTenant, [ADSubOUType]::Approval) -simulation $SIMULATION_MODE -updateExistingContent $true) -eq $false)
					{
						# Enregistrement du nom du groupe qui pose problème et on note de passer au service suivant car on ne peut pas créer celui-ci
						if($notifications.missingADGroups -notcontains $approveGroupNameGroupsAD)
						{
							$notifications.missingADGroups += $approveGroupNameGroupsAD
						}
							
						$allApproveGroupsOK = $false
					}
					else
					{
						# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
						$doneADGroupList += $approveGroupInfos.name
					}
	
				} # FIN BOUCLE de création des groupes pour les différents level d'approbation 
				
				
	
				# # --------------------------------- ROLES
	
				# Génération de nom du groupe dont on va avoir besoin pour les rôles "Admin" et "Support" (même groupe). 
				# Vu que c'est le même groupe pour les 2 rôles, on peut passer CSP_SUBTENANT_MANAGER ou CSP_SUPPORT aux fonctions, le résultat
				# sera le même
				$admSupGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_SUBTENANT_MANAGER", $false)
				$admSupGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_SUBTENANT_MANAGER")
				$admSupGroupNameGroups = $nameGenerator.getRoleGroupsADGroupName("CSP_SUBTENANT_MANAGER")
	
				$roleAdmSupGroupOK = $true
				# Création des groupes + gestion des groupes prérequis 
				if((createADGroupWithContent -groupName $admSupGroupNameAD -groupDesc $admSupGroupDescAD -groupMemberGroup $admSupGroupNameGroups `
					 -OU $nameGenerator.getADGroupsOUDN($true) -simulation $SIMULATION_MODE -updateExistingContent $false) -eq $false)
				{
					# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
					$notifications.missingRSRCHADGroups += $admSupGroupNameGroups
					$roleAdmSupGroupOK = $false
				}
				else
				{
					# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
					$doneADGroupList += $admSupGroupNameAD
				}
	
	
				# Génération de nom du groupe dont on va avoir besoin pour les rôles "User" et "Shared" (même groupe).
				# Vu que c'est le même groupe pour les 2 rôles, on peut passer CSP_CONSUMER_WITH_SHARED_ACCESS ou CSP_CONSUMER aux fonctions, le résultat
				# sera le même
				$userSharedGroupNameAD = $nameGenerator.getRoleADGroupName("CSP_CONSUMER", $false)
				$additionalDetails = @{
					financeCenter = $project.labo_no
					hasApproval = $true
				}
				$userSharedGroupDescAD = $nameGenerator.getRoleADGroupDesc("CSP_CONSUMER", $additionalDetails)
				$userSharedGroupNameGroupsAD = $nameGenerator.getRoleGroupsADGroupName("CSP_CONSUMER")
	
				# Récupération des infos du groupe dans Groups
				$userSharedGroupNameGroups = $nameGenerator.getRoleGroupsGroupName("CSP_CONSUMER")
				$userSharedGroupDescGroups = $nameGenerator.getRoleGroupsGroupDesc("CSP_CONSUMER")
				
				# Création du groupe dans Groups s'il n'existe pas
				$requestGroupGroups = createGroupsGroupWithContent -groupsApp $groupsApp -name $userSharedGroupNameGroups -desc $userSharedGroupDescGroups `
																	 -memberSciperList @($projectAdminSciper) -adminSciperList @($projectAdminSciper)

				$roleSharedGroupOk = $true
				# Création des groupes + gestion des groupes prérequis 
				if((createADGroupWithContent -groupName $userSharedGroupNameAD -groupDesc $userSharedGroupDescAD -groupMemberGroup $userSharedGroupNameGroupsAD `
					 -OU $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::User) -simulation $SIMULATION_MODE -updateExistingContent $true) -eq $false)
				{
					# Enregistrement du nom du groupe qui pose problème et passage au service suivant car on ne peut pas créer celui-ci
					if($notifications.missingADGroups -notcontains $userSharedGroupNameGroupsAD)
					{
						$notifications.missingADGroups += $userSharedGroupNameGroupsAD
					}
					$roleSharedGroupOk = $false
				}
				else
				{
					# Enregistrement du groupe créé pour ne pas le supprimer à la fin du script...
					$doneADGroupList += $userSharedGroupNameAD
				}


				# Si on n'a pas pu créer tous les groupes, on passe au service suivant 
				if(($allApproveGroupsOK -eq $false) -or ($roleAdmSupGroupOK -eq $false) -or ($roleSharedGroupOk -eq $false))
				{
					$counters.inc('rsrch.projectSkipped')
				}

				
				# Pour faire des tests
				if($TEST_MODE -and ($counters.get('rsrch.projectProcessed') -ge $RESEARCH_TEST_NB_PROJECTS_MAX))
				{
					Write-Warning "Breaking loop for test purpose"
					break
				}
	
			}# FIN BOUCLE de parcours des services renvoyés

		}# FIN SI c'est le tenant Research

	}# FIN EN fonction du tenant	

	# ----------------------------------------------------------------------------------------------------------------------

	# Parcours des groupes AD qui sont dans l'OU de l'environnement donné. On ne prend que les groupes qui sont utilisés pour 
	# donner des droits d'accès aux unités.
	Get-ADGroup  -Filter ("Name -like '*'") -SearchBase $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::User) -Properties Description | 
	ForEach-Object {

		# Si le groupe n'est pas dans ceux créés à partir de la source de données, c'est que l'élément n'existe plus. On supprime donc le groupe AD pour que 
		# le Business Group associé soit marqué comme "ghost" puis supprimé également par la suite via l'exécution du script "clean-ghost-bg.ps1".
		if($doneADGroupList -notcontains $_.name)
		{
			# Définition du type d'élément auquel on a à faire
			$element = switch($targetTenant)
			{
				$global:VRA_TENANT__EPFL { "Unit" }
				$global:VRA_TENANT__ITSERVICES  { "Service"}
				$global:VRA_TENANT__RESEARCH { "Project"}
			}

			$logHistory.addLineAndDisplay(("--> {0} doesn't exists anymore, removing AD user group {1} " -f $element, $_.name))
			if(-not $SIMULATION_MODE)
			{
				# On supprime le groupe AD
				Remove-ADGroup $_.name -Confirm:$false
			}

			$counters.inc('ADGroupsRemoved')

			# Si on est dans le Tenant "Research",
			if($targetTenant -eq $global:VRA_TENANT__RESEARCH)
			{
				$approveADGroupName = $nameGenerator.getApproveADGroupNameFromUserADGroups($_.name)

				# On supprime aussi le groupe AD pour l'approbation (niveau 2)
				$logHistory.addLineAndDisplay(("--> {0} doesn't exists anymore, removing AD approval group {1} " -f $element, $approveADGroupName))
				if(-not $SIMULATION_MODE)
				{	
					Remove-ADGroup $approveADGroupName -Confirm:$false	
				}

			}

			if($targetTenant -eq $global:VRA_TENANT__EPFL)
			{
				$logHistory.addLineAndDisplay(("--> Removing rights for '{0}' role in vraUsers table for AD group {1}" -f [TableauRoles]::User.ToString(), $_.name))

				# Extraction des informations
				$descInfos = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

				# Initialisation des détails pour le générateur de noms
				$nameGenerator.initDetails(@{facultyName = $descInfos.faculty
											facultyID = ''
											unitName = $descInfos.unit
											unitID = ''
											financeCenter = ''})
				if(-not $SIMULATION_MODE)
				{
					# Suppression des accès pour le business group correspondant au groupe AD courant.
					updateVRAUsersForBG -sqldb $sqldb -userList @() -role User -bgName $nameGenerator.getBGName() -targetTenant $targetTenant
				}
			}
			
		}

	}# FIN BOUCLE de parcours des groupes AD qui sont dans l'OU de l'environnement donné
	

	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant


	if($SIMULATION_MODE)
	{
		$logHistory.addWarningAndDisplay("***************************************")
		$logHistory.addWarningAndDisplay("** Script running in simulation mode **")
		$logHistory.addWarningAndDisplay("***************************************")
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
			$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
								 $targetTenant, 
								 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")),
								 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))
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
		$logHistory.addWarningAndDisplay("*********************************")
		$logHistory.addWarningAndDisplay("** Script running in TEST mode **")
		$logHistory.addWarningAndDisplay("*********************************")
	}

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

	# Fermeture de la connexion à la base de données
	$sqldb.disconnect()

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