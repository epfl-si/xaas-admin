<#
	BUT 		: Crée/met à jour les Business groupes en fonction des groupes AD existant

	DATE 		: Février 2018
	AUTEUR 	: Lucien Chaboudez

	Prérequis:
	1. Module ActiveDirectory pour PowerShell.
		- Windows 10 - Dispo dans RSAT - https://www.microsoft.com/en-us/download/details.aspx?id=45520
		- Windows Server 2003, 2013, 2016:
			+ Solution 1 - Install automatique
			>> Add-WindowsFeature RSAT-AD-PowerShell

			+ Solution 2 - Install manuelle
			1. Start "Server Manager"
			2. Click "Manage > Add Roles and Features"
			3. Click "Next" until you reach "Features".
			4. Enable "Active Directory module for Windows PowerShell" in
				"Remote Server Administration Tools > Role Administration Tools > AD DS and AD LDS Tools".

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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "vROAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))

# Chargement des fichiers de configuration
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config-vra.inc.ps1"))
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config-vro.inc.ps1"))
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config-mail.inc.ps1"))



<#
-------------------------------------------------------------------------------------
	BUT : Affiche comment utiliser le script
#>
function printUsage
{
   	$invoc = (Get-Variable MyInvocation -Scope 1).Value
   	$scriptName = $invoc.MyCommand.Name

	$envStr = $global:TARGET_ENV_LIST -join "|"
	$tenantStr = $global:TARGET_TENANT_LIST -join "|"

   	Write-Host ""
   	Write-Host ("Usage: $scriptName -targetEnv {0} -targetTenant {1}" -f $envStr, $tenantStr)
   	Write-Host ""
}

<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) une approval policy

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $name					-> Le nom de l'approval policy à créer
	IN  : $desc					-> Description de l'approval policy
	IN  : $approverGroupAtDomain-> Nom du groupe AD (FQDN) à mettre en approbateur
	IN  : $approvalPolicyType   -> Type de la policy :
                                    $global:APPROVE_POLICY_TYPE__ITEM_REQ
                                    $global:APPROVE_POLICY_TYPE__ACTION_REQ
	IN  : $approverType			-> Type d'approbation
									$global:APPROVE_POLICY_APPROVERS__SPECIFIC_USR_GRP
									$global:APPROVE_POLICY_APPROVERS__USE_EVENT_SUB


	RET : Objet représentant l'approval policy
#>
function createApprovalPolicyIfNotExists([vRAAPI]$vra, [string]$name, [string]$desc, [string]$approverGroupAtDomain, [string]$approvalPolicyType, [string]$approverType)
{
	$approvePolicy = $vra.getApprovalPolicy($name)

	# Si la policy n'existe pas, 
	if($approvePolicy -eq $null)
	{
		$logHistory.addLineAndDisplay(("-> Creating Approval Policy '{0}'..." -f $name))
		# On créé celle-ci
		$approvePolicy = $vra.addPreApprovalPolicy($name, $desc, $approverGroupAtDomain, $approvalPolicyType, $approverType)
	}
	else 
	{
		$logHistory.addLineAndDisplay(("-> Approval Policy '{0}' already exists!" -f $name))
	}

	return $approvePolicy
}


<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) ou met à jour un Business Group (si existant)

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $existingBGList		-> Liste des BG existants
	IN  : $bgUnitID				-> (optionnel) No d'unité du BG à ajouter/mettre à jour.
										A passer uniquement si tenant EPFL, sinon ""
	IN  : $bgName				-> Nom du BG
	IN  : $bgDesc				-> Description du BG
	IN  : $machinePrefixName	-> Nom du préfixe de machine à utiliser.
								   Peut être "" si le BG doit être créé dans le tenant ITServices.
	IN  : $capacityAlertsEmail	-> Adresse mail où envoyer les mails de "capacity alert"
	IN  : $customProperties		-> Tableau associatif avec les custom properties à mettre pour le BG. Celles-ci seront
								   complétées avec d'autres avant la création.

	RET : Objet représentant la Business Group
#>
function createOrUpdateBG
{
	param([vRAAPI]$vra, [Array]$existingBGList, [string]$bgUnitID, [string]$bgName, [string]$bgDesc, [string]$machinePrefixName, [string]$capacityAlertsEmail,[System.Collections.Hashtable]$customProperties)

	# On transforme à null si "" pour que ça passe correctement plus loin
	if($machinePrefixName -eq "")
	{
		$machinePrefixName = $null
	}

	# Si on doit gérer le tenant contenant toutes les Unités,
	if($bgUnitID -ne "")
	{

		# Si la recherche du BG par son le no de l'unité ne donne rien,
		if(($bg = getUnitBG -unitID $bgUnitID -fromList $existingBGList) -eq $null)
		{
			# Ajout des customs properties en vue de sa création
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE_UNIT
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_STATUS"] = $global:VRA_BG_STATUS_ALIVE
		}

		# Tentative de recherche du préfix de machine
		$machinePrefix = $vra.getMachinePrefix($machinePrefixName)

		# Si on ne trouve pas de préfixe de machine pour le nouveau BG,
		if($machinePrefix -eq $null)
		{
			# Si le BG n'existe pas, 
			if($bg -eq $null)
			{
				Write-Warning("No machine prefix found for {0}, skipping" -f $machinePrefixName)
				# On enregistre le préfixe de machine inexistant
				$notifications['newBGMachinePrefixNotFound'] += $machinePrefixName
				
				$counters.inc('BGNotCreated')
			}
			else # Le BG existe, il s'agit donc d'un renommage 
			{
				Write-Warning ("No machine prefix found for new faculty name ({0})" -f $machinePrefixName)
				# On enregistre le préfixe de machine inexistant
				$notifications['facRenameMachinePrefixNotFound'] += $machinePrefixName
				
				$counters.inc('BGNotRenamed')
			}
			# on sort
			return $null
		}
		$machinePrefixId = $machinePrefix.id
	}
	else # On doit gérer le tenant ITServices
	{

		# On tente de rechercher le BG par son nom et s'il n'existe pas,
		if(($bg = $vra.getBG($bgName)) -eq $null)
		{
			# Création des propriété custom
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE_SERVICE
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_STATUS"] = $global:VRA_BG_STATUS_ALIVE
		}
		# Pas d'ID de machine pour ce Tenant
		$machinePrefixId = $null
	}


	<# Si le BG n'existe pas, ce qui peut arriver dans les cas suivants :
		Tenant EPFL:
		- nouvelle unité (avec éventuellement nouvelle faculté)
		Tenant ITServices
		- nouveau service
	#>
	if($bg -eq $null)
	{

		$logHistory.addLineAndDisplay("-> BG doesn't exists, creating...")
		# Création du BG
		$bg = $vra.addBG($bgName, $bgDesc, $capacityAlertsEmail, $machinePrefixId, $customProperties)

		$counters.inc('BGCreated')
	}
	# Si le BG existe,
	else
	{
		# Si le nom du BG est incorrect, (par exemple si le nom de l'unité ou celle de la faculté a changé)
		# Note: Dans le cas du tenant ITServices, vu qu'on fait une recherche avec le nom, on n'arrivera
		#       jamais à l'intérieur de cette condition IF
		if($bg.name -ne $bgName)
		{
			
			$logHistory.addLineAndDisplay(("-> Renaming BG '{0}' to '{1}'" -f $bg.name, $bgName))

			# Mise à jour des informations
			$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_VRA_BG_STATUS" = $global:VRA_BG_STATUS_ALIVE})

			$counters.inc('BGUpdated')
		}
	}

	return $bg

}

<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistants) ou met à jour les roles d'un Business Group (si existants)

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg					-> Objet contenant le BG à mettre à jour
	IN  : $manageGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
								   managers. Si pas passé ou $null, on ne change rien dans la liste spécifiée
	IN  : $supportGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
								   personnes du support. Si pas passé ou $null, on ne change rien dans la liste spécifiée
	IN  : $sharedGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
									"Share users". Si pas passé ou $null, on ne change rien dans la liste spécifiée
	IN  : $userGrpList			-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
									users. Si pas passé ou $null, on ne change rien dans la liste spécifiée
	RET : Rien
#>
function createOrUpdateBGRoles
{
	param([vRAAPI]$vra, [PSCustomObject]$bg, [Array]$managerGrpList, [Array]$supportGrpList, [Array]$sharedGrpList, [Array]$userGrpList)

	$logHistory.addLineAndDisplay(("-> Updating roles for BG {0}..." -f $bg.name))

	# S'il faut faire des modifs
	if($managerGrpList.count -gt 0)
	{
		$logHistory.addLineAndDisplay("--> Updating 'Group manager role'...")
		$vra.deleteBGRoleContent($bg.id, "CSP_SUBTENANT_MANAGER")
		$managerGrpList | ForEach-Object { $vra.addRoleToBG($bg.id, "CSP_SUBTENANT_MANAGER", $_) }
	}

	# S'il faut faire des modifs
	if($supportGrpList.Count -gt 0)
	{
		$logHistory.addLineAndDisplay("--> Updating 'Support role'...")
		$vra.deleteBGRoleContent($bg.id, "CSP_SUPPORT")
		$supportGrpList | ForEach-Object { $vra.addRoleToBG($bg.id, "CSP_SUPPORT", $_) }
	}

	# S'il faut faire des modifs
	if($sharedGrpList.Count -gt 0)
	{
		$logHistory.addLineAndDisplay("--> Updating 'Shared access role'...")
		$vra.deleteBGRoleContent($bg.id, "CSP_CONSUMER_WITH_SHARED_ACCESS")
		$sharedGrpList | ForEach-Object { $vra.addRoleToBG($bg.id, "CSP_CONSUMER_WITH_SHARED_ACCESS", $_) }
	}

	# S'il faut faire des modifs
	if($userGrpList.Count -gt 0)
	{
		$logHistory.addLineAndDisplay("--> Updating 'User role'...")
		$vra.deleteBGRoleContent($bg.id, "CSP_CONSUMER")
		$userGrpList | ForEach-Object { $vra.addRoleToBG($bg.id, "CSP_CONSUMER", $_) }
	}

}


<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) ou met à jour un Entitlement de Business Group (si existant)

	IN  : $vra 			-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg			-> Objet BG auquel l'entitlement est attaché
	IN  : $entName		-> Nom de l'entitlement
	IN  : $entDesc		-> Description de l'entitlement.

	RET : Objet contenant l'Entitlement
#>
function createOrUpdateBGEnt
{
	param([vRAAPI]$vra, [PSCustomObject]$bg, [string]$entName, [string]$entDesc)

	# Si l'entitlement n'existe pas,
	if(($ent = $vra.getBGEnt($bg.id)) -eq $null)
	{
		$logHistory.addLineAndDisplay(("-> Creating Entitlement {0}..." -f $entName))
		$ent = $vra.addEnt($entName, $entDesc, $bg.id, $bg.name)

		$counters.inc('EntCreated')
	}
	else # L'entitlement existe
	{
		# Si le nom a changé (car le nom du BG a changé)
		if($ent.name -ne $entName)
		{
			$logHistory.addLineAndDisplay(("-> Updating Entitlement {0}..." -f $ent.name))
			# Mise à jour du nom/description de l'entitlement courant et on force la réactivation
			$ent = $vra.updateEnt($ent, $entName, $entDesc, $true)

			$counters.inc('EntUpdated')
		}
	}
	return $ent
}

<#
-------------------------------------------------------------------------------------
	BUT : Initialise les actions pour l'Entiltlement passé en paramètre.
			La liste des actions à ajouter se trouve dans le dossier $global:DAY2_ACTIONS_FOLDER
			Ce sont des fichiers portant le nom de l'élément (descriptif) tel que défini
			dans vRA et contenant la liste des actions. Cette liste d'actions est
			composée des textes décrivant celles-ci dans vRA (ex: Destroy, Create Snapshot,...)
			Pour le moment, on ne fait que préparer l'objet pour ensuite réellement le
			mettre à jour via vRAAPI::updateEnt(). On fait la mise à jour (update) en une
			seule fois car faire en plusieurs fois, une par élément à mettre à jour (action,
			service, ...) lève souvent une exception de "lock" sur l'objet Entitlement du
			côté de vRA.

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $ent				-> Objet Entitlement auquel lier les services
	IN  : $approvalPolicy	-> Object Approval Policy qui devra approuver les demandes 
								pour les 2nd day actions

	RET : Objet Entitlement mis à jour
#>
function prepareSetEntActions
{
	param([vRAAPI]$vra, [PSCustomObject]$ent, [PSCustomObject]$approvalPolicy)

	# Pour contenir la liste des actions
	$actionList = @()

	# Parcours des fichiers se trouvant dans le dossier contenant la liste des actions
	# par type d'élément
	Get-ChildItem $global:DAY2_ACTIONS_FOLDER | ForEach-Object {

		# Si le fichier commence par un _, c'est qu'il contient des actions customs définies au sein de l'EPFL
		# Dans ce cas-là, le nom de l'action devrait être UNIQUE
		if($_.Name[0] -eq "_")
		{
			# On met donc une chaine vide pour signifier que cette valeur ne devra pas être prise durant la recherche.
			$appliesTo = ""
		}
		else # Ce n'est pas une action custom EPFL
		{
			$appliesTo = $_.Name
		}
		Get-Content $_.FullName | ForEach-Object {
			$action = $_.Trim()
			# Si ce n'est pas une ligne vide ou une ligne de commentaire
			if(($action -ne "") -and ($action[0] -ne "#"))
			{
				# On défini si on a besoin d'un approval pour cette action et on supprime le @
				# devant le nom s'il existe afin d'avoir le "vrai" nom de l'action
				$needsApproval = ($action[0] -eq "@")
				$action = $action -replace "^@", ""

				# Enregistrement de l'action courante
				$actionList += @{action = $action
								 appliesTo = $appliesTo
								 needsApproval = $needsApproval}
			}
		}
	}

	$logHistory.addLineAndDisplay("-> (prepare) Adding 2nd day Actions to Entitlement...")
	# Ajout des actions
	$vra.prepareEntActions($ent, $actionList, $approvalPolicy)

}

<#
-------------------------------------------------------------------------------------
	BUT : Ajoute les Services "Public" à un Entitlement de Business Group s'il n'y
			sont pas déjà.
			Pour le moment, on ne fait que préparer l'objet pour ensuite réellement le
			mettre à jour via vRAAPI::updateEnt(). On fait la mise à jour (update) en une
			seule fois car faire en plusieurs fois, une par élément à mettre à jour (action,
			service, ...) lève souvent une exception de "lock" sur l'objet Entitlement du
			côté de vRA.

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $ent				-> Objet Entitlement auquel lier les services
	IN  : $approvalPolicy	-> Object Approval Policy qui devra approuver les demandes 
								pour les nouveaux éléments
	
	RET : Objet Entitlement mis à jour
#>
function prepareAddMissingBGEntPublicServices
{
	param([vRAAPI]$vra, [PSCustomObject]$ent, [PSCustomObject]$approvalPolicy)


	$logHistory.addLineAndDisplay("-> Getting existing public Services...")
	$publicServices = $vra.getServiceListMatch($global:VRA_SERVICE_SUFFIX_PUBLIC)

	# Parcours des services à ajouter à l'entitlement créé
	ForEach($publicService in $publicServices)
	{

		# Parcours des Services déjà liés à l'entitlement pour chercher le courant
		$serviceExists = $false
		ForEach($entService in $ent.entitledServices)
		{
			# Si on trouve le service
			if($entService.serviceRef.id -eq $publicService.id)
			{
				$logHistory.addLineAndDisplay(("--> Service '{0}' already in Entitlement" -f $publicService.name))
				$serviceExists = $true

				$counters.inc('EntServices')
				break;
			}
		}

		# Si le service public n'est pas dans l'entitlement,
		if(-not $serviceExists)
		{
			$logHistory.addLineAndDisplay(("--> (prepare) Adding service '{0}' to Entitlement" -f $publicService.name))
			$ent = $vra.prepareAddEntService($ent, $publicService.id, $publicService.name, $approvalPolicy)

			$counters.inc('EntServicesAdded')
		}
	}# FIN BOUCLE de parcours des services à ajouter à l'entitlement

	return $ent
}

<#
-------------------------------------------------------------------------------------
	BUT : Envoie un mail aux admins pour leur dire qu'aucun Template de Reservation n'a 
			été trouvé dans vRA et qu'il faudrait en créer...
	
	REMARQUE:
	La variable $targetEnv est utilisée de manière globale.

	RET : Rien
#>
function sendErrorMailNoResTemplateFound
{
	$docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=72516585"
	$mailSubject = getvRAMailSubject -shortSubject "Error - No Reservation Template found for tenant!" -targetEnv $targetEnv -targetTenant $targetTenant
	$message = getvRAMailContent -content ("Il n'existe aucun Template de Reservation pour la création des Business Groups sur l'environnement <b>{0}</b>.<br><br>Veuillez créer au moins un `
	Template à partir de la <a href='{1}'>documentation suivante</a>." -f $targetEnv, $docUrl)	


	sendMailTo -mailAddress $global:ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $message
}

<#
-------------------------------------------------------------------------------------
	BUT : Ajoute les Reservations nécessaires à un Business Group si elles n'existent
			pas encore. Ces réservations sont ajoutées selont les Templates qui existent.
			Si les Reservations existent, on les mets à jour si besoin.

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg				-> Objet BG auquel ajouter les réservations
	IN  : $resTemplatePrefix-> Préfix des templates de réservation pour rechercher celles-ci.

	RET : Rien
#>
function createOrUpdateBGReservations
{
	param([vRAAPI]$vra, [PSCustomObject]$bg, [string]$resTemplatePrefix)

	$logHistory.addLineAndDisplay("-> Getting Reservation template list...")
	$resTemplateList = $vra.getResListMatch($resTemplatePrefix)

	if($resTemplateList.Count -eq 0)
	{
		$logHistory.addErrorAndDisplay("No Reservation template found !! An email has been send to administrators to inform them.")
		sendErrorMailNoResTemplateFound
		exit
	}

	# Recherche de la liste des Reservations déjà attachée au BG
	$bgResList = $vra.getBGResList($bg.id)

	# Pour enregistrer la liste des Reservations qui ont été traitées
	$doneResList = @()

	# Parcours des templates trouvés
	ForEach($resTemplate in $resTemplateList)
	{
		# Récupération du nom du cluster mentionné dans le Template
		$templateClusterName = getResClusterName -reservation $resTemplate

		# Création du nom que la Reservation devrait avoir
		$resName = $nameGenerator.getBGResName($bg.name, $templateClusterName)

		$doneResList += $resName

		# Parcours des Reservations déjà existantes pour le BG afin de voir s'il faut ajouter
		# depuis $resTemplate ou pas. Pour ce faire, on se base sur le nom du Cluster auquel
		# la réservation est liée
		$matchingRes = $null
		ForEach($bgRes in $bgResList)
		{
			# Si la Reservation courante du BG est pour le Cluster de la template
			if( (getResClusterName -reservation $bgRes) -eq $templateClusterName)
			{
				$matchingRes = $bgRes
				break
			}
		}

		# Si la Reservation pour le cluster n'existe pas,
		if($matchingRes -eq $null)
		{
			$logHistory.addLineAndDisplay(("--> Adding Reservation '{0}' from template '{1}'..." -f $resName, $resTemplate.name))
			$newRes = $vra.addResFromTemplate($resTemplate, $resName, $bg.tenant, $bg.id)

			$counters.inc('ResCreated')
		}
		else # La Reservation existe
		{
			# Si le nom de la Reservation ne correspond pas (dans le cas où le nom du BG aurait changé)
			if($matchingRes.name -ne $resName)
			{
				$logHistory.addLineAndDisplay(("--> Renaming Reservation '{0}' to '{1}'..." -f $matchingRes.name, $resName))
				$matchingRes = $vra.updateRes($matchingRes, $resName)

				$counters.inc('ResUpdated')
			}
		}
	}

	# Parcours des Reservations existantes pour le BG
	Foreach($bgRes in $bgResList)
	{
		if($doneResList -notcontains $bgRes.Name)
		{
			$logHistory.addLineAndDisplay(("--> Deleting Reservation '{0}'..." -f $bgRes.Name))

			$vra.deleteRes($bgRes.id)

			$counters.inc('ResDeleted')
		}
	}

}


<#
-------------------------------------------------------------------------------------
	BUT : Efface un BG et tous ses composants (s'il ne contient aucun item).
		  Il faut effacer les composants dans l'ordre inverse dans lequel ils ont été créés, ce qui donne donc :
		  1. Reservations
		  2. Entitlement
		  3. Business Group

		  Si le BG contient des items, on va simplement le marquer comme "ghost" et changer les droits d'accès

	IN  : $vra 		-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg		-> Objet contenant le BG a effacer. Cet objet aura été renvoyé
					   par un appel à une méthode de la classe vRAAPI
#>
function deleteBGAndComponentsIfPossible
{
	param([vRAAPI]$vra, [PSObject]$bg)

	# Recherche des items potentiellement présents dans le BG
	$bgItemList = $vra.getBGItemList($bg)

	# S'il y a des items,
	if($bgItemList.Count -gt 0)
	{

		$logHistory.addLineAndDisplay(("--> Contains {0} items..." -f $bgItemList.Count))

		# Si le BG est toujours actif
		if(isBGAlive -bg $bg)
		{
			$logHistory.addLineAndDisplay("--> Setting as 'ghost'...")

			$notifications['bgSetAsGhost'] += $bg.name

			# On marque le BG comme "Ghost"
			$vra.updateBG($bg, $null, $null, $null, @{"$global:VRA_CUSTOM_PROP_VRA_BG_STATUS" = $global:VRA_BG_STATUS_GHOST})

			$counters.inc('BGGhost')

			# Si Tenant EPFL
			if($bg.tenant -eq $global:VRA_TENANT_EPFL)
			{
				# Récupération du contenu du rôle des admins de faculté pour le BG
				$facAdmins = $vra.getBGRoleContent($bg.id, "CSP_SUBTENANT_MANAGER") 
				
				# Ajout des admins de la faculté de l'unité du BG afin qu'ils puissent gérer les élments du BG.
				createOrUpdateBGRoles -vra $vra -bg $bg -sharedGrpList $facAdmins
			}
			# Si Tenant ITServices
			elseif($bg.tenant -eq $global:VRA_TENANT_ITSERVICES)
			{
				$tenantAdmins = $vra.getTenantAdminGroupList($bg.tenant)
				# Ajout des admins LOCAUX du tenant comme pouvant gérer les éléments du BG
				createOrUpdateBGRoles -vra $vra -bg $bg -sharedGrpList $tenantAdmins
			}
			else # Tenant non géré
			{
				$logHistory.addErrorAndDisplay(("!!! Tenant '{0}' not supported in this script" -f $bg.tenant))
				exit
			}

		} # FIN si le BG est toujours actif

	}
	else # Il n'y a aucun item dans le BG
	{
		# Récupération des informations nécessaires pour les éléments à supprimer (afin de les filtrer)
		$resNameBase = $nameGenerator.getBGResName($bg.name, "")

		# --------------
		# Reservations
		# Parcours des Reservations trouvées et suppression
		$vra.getResListMatch($resNameBase) | ForEach-Object {

			$logHistory.addLineAndDisplay(("--> Deleting Reservation '{0}'..." -f $_.Name))
			$vra.deleteRes($_.id)
		}


		# --------------
		# Entitlement
		# Si le BG a un entitlement,
		if(($bgEnt = $vra.getBGEnt($bg.id)) -ne $null)
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



		# Incrémentation du compteur
		$counters.inc('BGDeleted')
	}

}


<#
-------------------------------------------------------------------------------------
	BUT : Permet de savoir si le Business Group passé est du type donné

	IN  : $bg		-> Business Group dont on veut savoir s'il est du type donné
	IN  : $type		-> Type duquel le BG doit être

	RET : $true|$false
#>
function isBGOfType
{
	param([PSCustomObject]$bg, [string] $type)

	# Recherche de la custom property enregistrant l'information recherchée
	$entry = $bg.extensionData.entries | Where-Object { $_.key -eq $global:VRA_CUSTOM_PROP_VRA_BG_TYPE}

	# Si custom property PAS trouvée,
	if($entry -eq $null)
	{
		$notifications['bgWithoutCustomPropType'] += $bg.name
		return $false
	}
	else # Custom property trouvée
	{
		# On regarde si la valeur correspond.
		return ($entry.value.values.entries | Where-Object {$_.key -eq "value"}).value.value -eq $type
	}


}

<#
-------------------------------------------------------------------------------------
	BUT : Permet de savoir si le Business Group passé est vivant ou voué à disparaitre

	IN  : $bg		-> Business Group dont on veut savoir s'il est vivant

	RET : Nom du groupe de sécurité à ajouter
#>
function isBGAlive
{
	param([PSCustomObject]$bg)

	$customProp = $bg.extensionData.entries | Where-Object { $_.key -eq $global:VRA_CUSTOM_PROP_VRA_BG_STATUS}

	# Si la "Custom property" a été trouvée,
	if($customProp -ne $null)
	{
		return ($customProp.value.values.entries | Where-Object {$_.key -eq "value"}).value.value -eq $global:VRA_BG_STATUS_ALIVE
	}

	<# Si on arrive ici, c'est qu'on n'a pas défini de clef (pour une raison inconnue) pour enregistrer le statut
	   On enregistre donc la chose et on dit que le BG est "vivant"
	#>
	$notifications['bgWithoutCustomPropStatus'] += $bg.name
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
				# Préfixes de machine non trouvés
				'newBGMachinePrefixNotFound'
				{
					$docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=70976775"
					$mailSubject = getvRAMailSubject -shortSubject "Error - Machine prefixes not found" -targetEnv $targetEnv -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les préfixes de machines suivants n'ont pas été trouvés `
dans vRA pour l'environnement <b>{0}</b> et le tenant <b>{1}</b>.<br>Veuillez les créer à la main:`
<br><ul><li>{2}</li></ul>De la documentation pour faire ceci peut être trouvée <a href='{3}'>ici</a>."  -f $targetEnv, $targetTenant, ($uniqueNotifications -join "</li>`n<li>"), $docUrl)
				}

				# ---------------------------------------
				# BG sans "custom property" permettant de définir le statut
				'bgWithoutCustomPropStatus'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Warning - Business Group without '$global:VRA_CUSTOM_PROP_VRA_BG_STATUS' custom property" `
													 -targetEnv $targetEnv -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les Business Groups suivants ne contiennent pas la 'Custom Property' `
<b>{0}</b>.<br>Veuillez faire le nécessaire:`
<br><ul><li>{1}</li></ul>"  -f $global:VRA_CUSTOM_PROP_VRA_BG_STATUS, ($uniqueNotifications -join "</li>`n<li>"))
				}

				# ---------------------------------------
				# BG sans "custom property" permettant de définir le type
				'bgWithoutCustomPropType'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Warning - Business Group without '$global:VRA_CUSTOM_PROP_VRA_BG_TYPE' custom property" `
													 -targetEnv $targetEnv -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les Business Groups suivants ne contiennent pas la 'Custom Property' `
<b>{0}</b>.<br>Veuillez faire le nécessaire:`
<br><ul><li>{1}</li></ul>"  -f $global:VRA_CUSTOM_PROP_VRA_BG_TYPE, ($uniqueNotifications -join "</li>`n<li>"))
				}

				# ---------------------------------------
				# BG marqué comme étant des 'ghost'
				'bgSetAsGhost'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Info - Business Group marked as 'ghost'" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les Business Groups suivants ont leur statut qui est passé à 'ghost' `
car les unités associées ont disparu mais il y a toujours des items contenus dans les Business Groups.<br>Les droits ont été donnés `
aux administrateurs de la faculté afin qu'ils puissent gérer la chose.
<br><ul><li>{0}</li></ul>"  -f  ($uniqueNotifications -join "</li>`n<li>"))
				}

				# ---------------------------------------
				# BG effacés
				'bgDeleted'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Info - Business Group deleted" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les Business Groups suivants ont été effacés car les unités associées `
ont disparu et il n'y avait plus aucun item contenu dans les Business Groups.`
<br><ul><li>{0}</li></ul>"  -f  ($uniqueNotifications -join "</li>`n<li>"))
				}

				# ---------------------------------------
				# Préfix de machine non trouvé pour un renommage de faculté
				'facRenameMachinePrefixNotFound'
				{
					$docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=70976775"
					$mailSubject = getvRAMailSubject -shortSubject "Error - Machine prefixes not found for new faculty name" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les préfixes de machines suivants n'ont pas été trouvés `
dans vRA pour l'environnement <b>{0}</b>.<br>Ceci signifie que les Business Groups de la faculté renommée n'ont pas pu être renommés.`
<br>Veuillez créer les préfixes de machine à la main:`
<br><ul><li>{1}</li></ul>De la documentation pour faire ceci peut être trouvée <a href='{2}'>ici</a>."  -f $targetEnv, ($uniqueNotifications -join "</li>`n<li>"), $docUrl)
				}

				# ---------------------------------------
				# Groupes AD soudainement devenus vides...
				'emptyADGroups'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Info - AD groups empty for Business Group" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les groupes Active Directory suivants (avec nom du Business Group) `
ne contiennent plus aucun utilisateur. Il s'agit peut-être d'une erreur dans la synchro depuis MIIS ou autre, à surveiller:`
<br><ul><li>{0}</li></ul>"  -f  ($uniqueNotifications -join "</li>`n<li>"))
				}

				# ---------------------------------------
				# Groupes AD pour les rôles...
				'adGroupsNotFound'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Error - AD groups not found fo Business Group" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les groupes Active Directory suivants n'ont pas été trouvés.`
Il s'agit peut-être d'une erreur dans l'exécution du script 'sync-ad-groups-from-ldap.ps1' qui créé ceux-ci:`
<br><ul><li>{0}</li></ul>"  -f  ($uniqueNotifications -join "</li>`n<li>"))
				}
				

				default
				{
					# Passage à l'itération suivante de la boucle
					Write-Warning ("Notification '{0}' not handled in code !" -f $notif)
					continue
				}

			}

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			sendMailTo -mailAddress $global:ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $message

		} # FIN S'il y a des notifications pour la catégorie courante
	}# FIN BOUCLE de parcours des catégories de notifications
}


<#
-------------------------------------------------------------------------------------
	BUT : Contrôle si les groupes passés en paramètre existent tous dans AD (dans le
		  cas où ce sont des groupes AD).
		  Si un groupe n'est pas trouvé, il est ajouté à la liste dans les notifications

	IN  : $groupList	-> Liste des groupes à contrôler

	RET : $true	-> Tous les groupes existent
		  $false -> au moins un groupe n'existe pas.
#>
function checkIfADGroupsExists
{
	param([System.Collections.ArrayList]$groupList)


	$allOK = $true
	Foreach($groupName in $groupList)
	{
		# Si le groupe ressemble à 'xyz@intranet.epfl.ch'
		if($groupName.endswith([NameGenerator]::AD_DOMAIN_NAME))
		{
			# On explose pour avoir :
			# $groupShort = 'xyz' 
			# $domain = 'intranet.epfl.ch'
			$groupShort, $domain = $groupName.Split('@')
			if((ADGroupExists -groupName $groupShort) -eq $false)
			{
				# Enregistrement du nom du groupe
				$notifications['adGroupsNotFound'] += $groupName
				$allOK = $false
			}
		}
	}

	return $allOK
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

Import-Module ActiveDirectory

# Test des paramètres
if(($targetEnv -eq "") -or (-not(targetEnvOK -targetEnv $targetEnv)))
{
   printUsage
   exit
}

# Contrôle de la validité du nom du tenant
if(($targetTenant -eq "") -or (-not (targetTenantOK -targetTenant $targetTenant)))
{
	printUsage
	exit
}

# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

$doneBGList = @()

try {
	# Création d'une connexion au serveur vRA pour accéder à ses API REST
	$vra = [vRAAPI]::new($nameGenerator.getvRAServerName(), $targetTenant, $global:VRA_USER_LIST[$targetTenant], $global:VRA_PASSWORD_LIST[$targetEnv][$targetTenant])
}
catch {
	Write-Error "Error connecting to vRA API !"
	Write-Error $_.ErrorDetails.Message
	exit
}

try {
	# Création d'une connexion au serveur vRA pour accéder aux API REST de vRO
	$vro = [vROAPI]::new($nameGenerator.getvRAServerName(), $global:VRO_CAFE_CLIENT_ID[$targetEnv], $global:VRA_PASSWORD_LIST[$targetEnv][$global:VRA_TENANT_DEFAULT])
}
catch {
	Write-Error "Error connecting to vRO API !"
	Write-Error $_.ErrorDetails.Message
	exit
}


# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$counters = [Counters]::new()
$counters.add('ADGroups', '# AD group processed')
$counters.add('BGCreated', '# Business Group created')
$counters.add('BGUpdated', '# Business Group updated')
$counters.add('BGNotCreated', '# Business Group not created')
$counters.add('BGNotRenamed', '# Business Group not renamed')
$counters.add('BGDeleted', '# Business Group deleted')
$counters.add('BGGhost',	'# Business Group set as "ghost"')
# Entitlements
$counters.add('EntCreated', '# Entitlements created')
$counters.add('EntUpdated', '# Entitlements updated')
# Services
$counters.add('EntServices', '# Existing Entitlements Services')
$counters.add('EntServicesAdded', '# Entitlements Services added')
# Reservations
$counters.add('ResCreated', '# Reservations created')
$counters.add('ResUpdated', '# Reservations updated')
$counters.add('ResDeleted', '# Reservations deleted')
# Machine prefixes
$counters.add('MachinePrefNotFound', '# machines prefixes not found')


<# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
aux administrateurs du service
!! Attention !!
A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
fonction 'handleNotifications()'

(cette liste sera accédée en variable globale même si c'est pas propre XD)
#>
$notifications=@{newBGMachinePrefixNotFound = @()
				facRenameMachinePrefixNotFound = @()
				bgWithoutCustomPropStatus = @()
				bgWithoutCustomPropType = @()
				bgSetAsGhost = @()
				bgDeleted = @()
				emptyADGroups = @()
				adGroupsNotFound = @()}

# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logHistory =[LogHistory]::new('2.sync-BG-from-AD', (Join-Path $PSScriptRoot "logs"), 30)

$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))

try
{
	# Recherche de BG existants
	$existingBGList = $vra.getBGList()
	
	<# Recherche des groupes pour lesquels il faudra créer des OUs
	 On prend tous les groupes de l'OU et on fait ensuite un filtre avec une expression régulière sur le nom. Au début, on prenait le début du nom du
	 groupe pour filtrer mais d'autres groupes avec des noms débutant de la même manière ont été ajoutés donc le filtre par expression régulière
	 a été nécessaire.
	#>
	if($targetTenant -eq $global:VRA_TENANT_EPFL)
	{
		$adGroupNameRegex = $nameGenerator.getEPFLADGroupNameRegEx("CSP_CONSUMER")
	}
	else 
	{
		$adGroupNameRegex = $nameGenerator.getITSADGroupNameRegEx("CSP_CONSUMER")
	}
	$adGroupList = Get-ADGroup -Filter ("Name -like '*'") -Server ad2.epfl.ch -SearchBase $nameGenerator.getADGroupsOUDN() -Properties Description | 
	Where-Object {$_.Name -match $adGroupNameRegex} 

	# Parcours des groupes AD pour l'environnement/tenant donné
	$adGroupList | ForEach-Object {

		$counters.inc('ADGroups')

		# Génération du nom du groupe avec le domaine
		$ADFullGroupName = $nameGenerator.getADGroupFQDN($_.Name)
		$logHistory.addLineAndDisplay(("-> Current AD group         : $($_.Name)"))

		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group

		# Ajout de l'adresse par défaut à laquelle envoyer les mails. 
		$capacityAlertMails = @($global:CAPACITY_ALERT_DEFAULT_MAIL)

		# Recherche des Workflows vRO à utiliser
		$workflowNewItem = $vro.getWorkflow($global:VRO_WORKFLOW_NEW_ITEM)
		

		# Si Tenant EPFL
		if($targetTenant -eq $global:VRA_TENANT_EPFL)
		{
			# Eclatement de la description et du nom pour récupérer le informations
			$facultyID, $unitID = $nameGenerator.extractInfosFromADGroupName($_.Name)
			$faculty, $unit = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

			Write-Debug "-> Current AD group Faculty : $($faculty) ($($facultyID))"
			Write-Debug "-> Current AD group Unit    : $($unit) ($($unitID)) "

			# Création du nom/description du business group
			$bgName = $nameGenerator.getBGName($faculty, $unit)
			$bgDesc = $nameGenerator.getEPFLBGDescription($faculty, $unit)

			# Génération du nom et de la description de l'entitlement
			$entName, $entDesc = $nameGenerator.getEPFLBGEntNameAndDesc($faculty, $unit)

			# Nom du préfix de machine
			$machinePrefixName = $nameGenerator.getVMMachinePrefix($faculty)

			# Custom properties du Buisness Group
			$bgCustomProperties = @{"$global:VRA_CUSTOM_PROP_EPFL_UNIT_ID" = $unitID}

			# Groupes de sécurités AD pour les différents rôles du BG
			$managerGrpList = @($nameGenerator.getEPFLRoleADGroupName("CSP_SUBTENANT_MANAGER", $faculty, $true))
			$supportGrpList = @($nameGenerator.getEPFLRoleADGroupName("CSP_SUPPORT", $faculty, $true))
			# Pas besoin de "générer" le nom du groupe ici car on le connaît déjà vu qu'on est en train de parcourir les groupes AD
			# créés par le script "sync-ad-groups-from-ldap.ps1"
			$sharedGrpList  = @($ADFullGroupName)
			$userGrpList    = @($ADFullGroupName)
			
			# Ajout de l'adresse mail à laquelle envoyer les "capacity alerts" pour le BG
			$capacityAlertMails += $nameGenerator.getEPFLApproveGroupsEmail($faculty)

			# Nom et description de la policy d'approbation + nom du groupe AD qui devra approuver
			$itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getEPFLApprovalPolicyNameAndDesc($faculty, $global:APPROVE_POLICY_TYPE__ITEM_REQ)
			$actionReqApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getEPFLApprovalPolicyNameAndDesc($faculty, $global:APPROVE_POLICY_TYPE__ACTION_REQ)
			$approveGroupName = $nameGenerator.getEPFLApproveADGroupName($faculty, $true)

			# Vu qu'il y aura des quotas pour les demandes sur le tenant EPFL, on utilise une policy du type "Event Subscription", ceci afin d'appeler un Workflow défini
			# qui se chargera de contrôler le quota.
			$approverType = $global:APPROVE_POLICY_APPROVERS__USE_EVENT_SUB

		}
		# Si Tenant ITServices
		elseif($targetTenant -eq $global:VRA_TENANT_ITSERVICES)
		{
			# Pour signifier à la fonction createOrUpdateBG qu'on n'est pas dans le tenant EPFL.
			$unitID = ""

			# Eclatement de la description et du nom pour récupérer le informations 
			# Vu qu'on reçoit un tableau à un élément, on prend le premier (vu que les autres... n'existent pas)
			$serviceShortName = $nameGenerator.extractInfosFromADGroupName($_.Name)[0]
			$snowServiceId, $serviceLongName  = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

			# Création du nom/description du business group
			$bgName = $nameGenerator.getBGName($serviceShortName)
			$bgDesc = $serviceLongName
			
			# Génération du nom et de la description de l'entitlement
			$entName, $entDesc = $nameGenerator.getITSBGEntNameAndDesc($serviceShortName, $serviceLongName)

			# Nom du préfix de machine
			# NOTE ! Il n'y a pas de préfix de machine pour les Business Group du tenant ITServices.
			$machinePrefixName = ""
			
			# Custom properties du Buisness Group
			$bgCustomProperties = @{"$global:VRA_CUSTOM_PROP_EPFL_SNOW_SVC_ID" = $snowServiceId}

			# Groupes de sécurités AD pour les différents rôles du BG
			$managerGrpList = @($nameGenerator.getITSRoleADGroupName("CSP_SUBTENANT_MANAGER", $serviceShortName, $true))
			$supportGrpList = @($nameGenerator.getITSRoleADGroupName("CSP_SUPPORT", $serviceShortName, $true))
			# Pas besoin de "générer" le nom du groupe ici car on le connaît déjà vu qu'on est en train de parcourir les groupes AD
			# créés par le script "sync-ad-groups-from-ldap.ps1"
			$sharedGrpList  = @($ADFullGroupName)
			$userGrpList    = @($ADFullGroupName)

			# Ajout de l'adresse mail à laquelle envoyer les "capacity alerts" pour le BG
			$capacityAlertMails += $nameGenerator.getITSApproveGroupsEmail($serviceShortName)

			# Nom de la policy d'approbation ainsi que du groupe d'approbateurs
			$itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getITSApprovalPolicyNameAndDesc($serviceShortName, $serviceLongName, $global:APPROVE_POLICY_TYPE__ITEM_REQ)
			$actionReqApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getITSApprovalPolicyNameAndDesc($serviceShortName, $serviceLongName, $global:APPROVE_POLICY_TYPE__ACTION_REQ)
			$approveGroupName = $nameGenerator.getITSApproveADGroupName($serviceShortName, $true)
			
			# Pas de quota pour le tenant ITServices donc on peut se permettre de simplement utiliser une approbation via un groupe de sécurité
			$approverType = $global:APPROVE_POLICY_APPROVERS__SPECIFIC_USR_GRP
		}

		# Contrôle de l'existance des groupes. Si l'un d'eux n'existe pas dans AD, une exception est levée.
		if( ((checkIfADGroupsExists -groupList $managerGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $supportGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $sharedGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $userGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList @($approveGroupName)) -eq $false))
		{
			$logHistory.addWarningAndDisplay(("Security groups for Business Group ({0}) roles not found in Active Directory, skipping it !" -f $bgName))

			# On enregistre quand même le nom du Business Group, même si on n'a pas pu continuer son traitement. Si on ne fait pas ça et qu'il existe déjà,
			# il sera supprimé à la fin du script, chose qu'on ne désire pas.
			$doneBGList += $bgName

			# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			return
		}


		# Si le groupe est vide,
		if((Get-ADGroupMember -server ad2.epfl.ch $_.Name).Count -eq 0)
		{
			# On enregistre l'info pour notification
			$notifications['emptyADGroups'] += ("{0} ({1})" -f $_.Name, $bgName)
		}

		# Création des Approval policies pour les demandes de nouveaux éléments et les reconfigurations si celles-ci n'existent pas encore
		$itemReqApprovalPolicy = createApprovalPolicyIfNotExists -vra $vra -name $itemReqApprovalPolicyName -desc $itemReqApprovalPolicyDesc `
																 -approverGroupAtDomain $approveGroupName -approvalPolicyType $global:APPROVE_POLICY_TYPE__ITEM_REQ `
																 -approverType $approverType
		$actionReqApprovalPolicy = createApprovalPolicyIfNotExists -vra $vra -name $actionReqApprovalPolicyName -desc $actionReqApprovalPolicyDesc `
																  -approverGroupAtDomain $approveGroupName -approvalPolicyType $global:APPROVE_POLICY_TYPE__ACTION_REQ `
																  -approverType $approverType



		# Création ou mise à jour du Business Group
		$bg = createOrUpdateBG -vra $vra -existingBGList $existingBGList -bgUnitID $unitID -bgName $bgName -bgDesc $bgDesc `
									-machinePrefixName $machinePrefixName -capacityAlertsEmail ($capacityAlertMails -join ",") -customProperties $bgCustomProperties

		# Si BG pas créé, on passe au suivant (la fonction de création a déjà enregistré les infos sur ce qui ne s'est pas bien passé)
		if($bg -eq $null)
		{
			# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			return
		}

		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Roles
		createOrUpdateBGRoles -vra $vra -bg $bg -managerGrpList $managerGrpList -supportGrpList $supportGrpList `
									-sharedGrpList $sharedGrpList -userGrpList $userGrpList


		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement
		$ent = createOrUpdateBGEnt -vra $vra -bg $bg -entName $entName -entDesc $entDesc


		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement - Actions
		$ent = prepareSetEntActions -vra $vra -ent $ent -approvalPolicy $actionReqApprovalPolicy


		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement - Services
		$ent = prepareAddMissingBGEntPublicServices -vra $vra -ent $ent -approvalPolicy $itemReqApprovalPolicy

		# Mise à jour de l'entitlement avec les modifications apportées ci-dessus
		$logHistory.addLineAndDisplay("-> Updating Entitlement...")
		$ent = $vra.updateEnt($ent, $true)



		# ----------------------------------------------------------------------------------
		# --------------------------------- Reservations

		createOrUpdateBGReservations -vra $vra -bg $bg -resTemplatePrefix $nameGenerator.getReservationTemplatePrefix()

		$doneBGList += $bg.name


	}# Fin boucle de parcours des groupes AD pour l'environnement/tenant donnés

	$logHistory.addLineAndDisplay("Business Groups created from AD!")

	$logHistory.addLineAndDisplay("Cleaning 'old' Business Groups")
	# ----------------------------------------------------------------------------------------------------------------------
	# ----------------------------------------------------------------------------------------------------------------------

	# Recherche et parcours de la liste des BG commençant par le bon nom pour le tenant
	$vra.getBGList() | ForEach-Object {

		# Si c'est un BG d'unité ou de service et s'il faut l'effacer
		if(((isBGOfType -bg $_ -type $global:VRA_BG_TYPE_SERVICE) -or (isBGOfType -bg $_ -type $global:VRA_BG_TYPE_UNIT)) -and `
			($doneBGList -notcontains $_.name))
		{
			$logHistory.addLineAndDisplay(("-> Deleting Business Group '{0}'..." -f $_.name))
			deleteBGAndComponentsIfPossible -vra $vra -bg $_
		}
	}

	$vra.disconnect()

	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$logHistory.addLineAndDisplay("Done")

	# Une dernière mise à jour
	$counters.set('MachinePrefNotFound', $notifications['newBGMachinePrefixNotFound'].count + `
										$notifications['facRenameMachinePrefixNotFound'].count)

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))
}
catch # Dans le cas d'une erreur dans le script
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant $targetTenant
	$mailMessage = getvRAMailContent -content ("<b>Script:</b> {0}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Web.HttpUtility]::HtmlEncode($errorTrace))

	sendMailTo -mailAddress $global:ADMIN_MAIL_ADDRESS -mailSubject $mailSubject -mailMessage $mailMessage
	
}

