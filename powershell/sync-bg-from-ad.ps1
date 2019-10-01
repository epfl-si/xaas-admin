<#
USAGES:
	sync-bg-from-ad.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl
#>
<#
	BUT 		: Crée/met à jour les Business groupes en fonction des groupes AD existant

	DATE 		: Février 2018
	AUTEUR 	: Lucien Chaboudez

	PARAMETRES : 
		$targetEnv	-> nom de l'environnement cible. Ceci est défini par les valeurs $global:TARGET_ENV__* 
						dans le fichier "define.inc.ps1"
		$targetTenant -> nom du tenant cible. Défini par les valeurs $global:VRA_TENANT__* dans le fichier
						"define.inc.ps1"

	Documentation:
		- Fichiers JSON utilisés: https://sico.epfl.ch:8443/display/SIAC/Ressources+-+PRJ0011976

	ALTERATION DU FONCTIONNEMENT:
	Les fichiers ci-dessous peuvent être créés (vides) au même niveau que le présent script afin de modifier
	le comportement de celui-ci
	- RECREATE_APPROVAL_POLICIES -> forcer la recréation des approval policies qui existent déjà. Ceci est à 
									utiliser uniquement s'il faut faire une mise à jour dans celles-ci car
									on perd quelques références avec les objets déjà créés...
									Le fichier est automatiquement effacé à la fin du script s'il existe, ceci
									afin d'éviter de recréer inutilement les approval policies


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

<# On enregistrer l'endroit où le script courant se trouve pour pouvoir effectuer l'import des autres fichiers.
On fait ceci au lieu d'utiliser $PSScriptRoot car la valeur de ce dernier peut changer si on importe un module (Import-Module) dans
un des fichiers inclus via ". <pathToFile>" #>
$SCRIPT_PATH = $PSScriptRoot

. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "JSONUtils.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "NewItems.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ConfigReader.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "vROAPI.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "REST", "NSXAPI.inc.ps1"))



# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")
$configNSX = [ConfigReader]::New("config-nsx.json")



<#
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
										Fonctions
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
#>


<#
-------------------------------------------------------------------------------------
	BUT : Renvoie le nom complet d'un élément en fonction du template JSON de création
			de celui-ci. Ceci est utilisé quand on met un préfixe ou suffixe dans le champ "name"
			d'un élément à créer dans vRA à partir d'un fichier template JSON. La classe 
			NameGenerator nous donne le nom de base (utilisé pour remplacer une chaine {{nomElement}}
			dans le fichier JSON) mais il faut que l'on récupère le "vrai" nom complet pour ensuite
			pouvoir faire une recherche dans vRA basée sur le nom afin de savoir si l'élément existe
			déjà ou pas.
	
	IN  : $baseName			-> Nom de base de l'élément, qui va être utilisé pour remplacer la chaine {{nomElement}}
								définie par le paramètre $replaceString
	IN  : $JSONFile			-> Nom du fichier JSON contenant le template
	IN  : $replaceString	-> Chaine de caractère à rechercher et remplacer par $baseName dans le fichier JSON
	IN  : $fieldName		-> Nom de l'élément pour lequel il faut renvoyer la valeur, une fois le JSON transformé
								en objet.
								
	RET : Le nom "final" de l'élément.	
#>
function getFullElementNameFromJSON([string]$baseName, [string]$JSONFile, [string]$replaceString, [string]$fieldName)
{
	# Chemin complet jusqu'au fichier à charger
	$filepath = (Join-Path $global:JSON_TEMPLATE_FOLDER $JSONFile)

	# Si le fichier n'existe pas
	if(-not( Test-Path $filepath))
	{
		Throw ("JSON file not found ({0})" -f $filepath)
	}

	# Chargement du code JSON
	$json = (Get-Content -Path $filepath) -join "`n"
	# Remplacement de la chaîne de caractères 
	$json = $json -replace "{{$($replaceString)}}", $baseName
	# Transformation en objet
	$jsonObject = $json | ConvertFrom-Json
	# Retour du champ demandé
	return $jsonObject.$fieldName
}


<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) une approval policy

	IN  : $vra 							-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $name							-> Le nom de l'approval policy à créer
	IN  : $desc							-> Description de l'approval policy
	IN  : $approvalLevelJSON			-> Le nom court du fichier JSON (template) à utiliser pour créer les
											les Approval Level de l'approval policy
	IN  : $approverGroupAtDomainList	-> Tableau avec la liste ordrée des FQDN du groupe (<group>@<domain>) qui devront approuver.
											Chaque entrée du tableau correspond à un "level" d'approbation
	IN  : $approvalPolicyJSON			-> Le nom court du fichier JSON (template) à utiliser pour 
											créer l'approval policy dans vRA
	IN  : $additionnalReplace			-> Tableau associatif permettant d'étendre la liste des éléments
											à remplacer (chaînes de caractères) au sein du fichier JSON
											chargé. Le paramètre doit avoir en clef la valeur à chercher
											et en valeur celle avec laquelle remplacer.	Ceci est 
											typiquement utilisé pour les approval policies définies pour
											les 2nd day actions.
	IN  : $processedApprovalPoliciesIDs	-> REF sur la liste des ID de policies déjà traités. On passe par référence pour que le
											paramètre puisse être modifié. Il devra donc être accédé via $processedApprovalPoliciesIDs.value 
											au sein de la fonction.
											Les autres paramètres n'ont pas besoin d'être passés par référence car ce sont des objets et 
											il semblerait que sur PowerShell, les objets soient par défaut passés en IN/OUT 								

	RET : Objet représentant l'approval policy
#>
function createApprovalPolicyIfNotExists([vRAAPI]$vra, [string]$name, [string]$desc, [string]$approvalLevelJSON, [Array]$approverGroupAtDomainList, [string]$approvalPolicyJSON, [psobject]$additionnalReplace, [ref]$processedApprovalPoliciesIDs)
{
	# Recherche du nom complet de la policy depuis le fichier JSON
	$fullName = getFullElementNameFromJSON -baseName $name -JSONFile $approvalPolicyJSON -replaceString "preApprovalName" -fieldName "name"

	# Rechercher de l'approval policy avec le nom "final"
	$approvePolicy = $vra.getApprovalPolicy($fullName)

	# Si l'approval policy existe, qu'elle n'a pas encore été traitée et qu'il est demandé de les recréer 
	if(($null -ne $approvePolicy) -and `
		($processedApprovalPoliciesIDs.value -notcontains $approvePolicy.id) -and `
		(Test-Path -Path ([IO.Path]::Combine("$SCRIPT_PATH", $global:SCRIPT_ACTION_FILE__RECREATE_APPROVAL_POLICIES))))
	{
		$logHistory.addLineAndDisplay(("-> Approval Policy '{0}' already exists but recreation asked. Deleting it..." -f $fullName))

		# On commence par désactiver l'approval policy 
		$approvePolicy = $vra.setApprovalPolicyState($approvePolicy, $false)
		# Et on l'efface ... 
		$vra.deleteApprovalPolicy($approvePolicy)

		# Pour que la policy soit recréée juste après
		$approvePolicy = $null
	}

	# Si la policy n'existe pas, 
	if($null -eq $approvePolicy)
	{
		$logHistory.addLineAndDisplay(("-> Creating Approval Policy '{0}'..." -f $fullName))
		
		# On créé celle-ci (on reprend le nom de base $name)
		$approvePolicy = $vra.addPreApprovalPolicy($name, $desc, $approvalLevelJSON, $approverGroupAtDomainList, $approvalPolicyJSON, $additionnalReplace)

		$counters.inc('AppPolCreated')
	}
	else # Si la policy existe, 
	{
		$logHistory.addLineAndDisplay(("-> Approval Policy '{0}' already exists!" -f $fullName))

		# On active la policy pour être sûr que tout se passera bien
		$approvePolicy = $vra.setApprovalPolicyState($approvePolicy, $true)

		# Incrément du compteur mais avec gestion des doublons en passant le nom de l'Approval Policy en 2e paramètre
		$counters.inc('AppPolExisting', $fullName)
	}

	# Mise à jour de la liste si besoin 
	if($processedApprovalPoliciesIDs.value -notcontains $approvePolicy.id)
	{
		$processedApprovalPoliciesIDs.value += $approvePolicy.id 
	}

	return $approvePolicy
}

<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistantes) toutes les Approval Policies qui sont listées dans le fichier décrivant
			les 2nd day actions

	IN  : $vra 							-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $secondDayActions				-> Objet de la classe SecondDayActions contenant la liste des actions
											2nd day à ajouter.
	IN  : $baseName						-> Le nom de base de l'approval policy à créer (vu qu'il peut y 
											avoir un suffixe dans le fichier template JSON)
	IN  : $desc							-> Description de l'approval policy
	IN  : $approverGroupAtDomainList	-> Tableau avec la liste ordrée des FQDN du groupe (<group>@<domain>) qui devront approuver.
											Chaque entrée du tableau correspond à un "level" d'approbation
	IN  : $processedApprovalPoliciesIDs	-> REF sur la liste des ID de policies déjà traités. On passe par référence pour que le
											paramètre puisse être modifié. Il devra donc être accédé via $processedApprovalPoliciesIDs.value 
											au sein de la fonction
											Les autres paramètres n'ont pas besoin d'être passés par référence car ce sont des objets et 
											il semblerait que sur PowerShell, les objets soient par défaut passés en IN/OUT 
	
#>
function create2ndDayActionApprovalPolicies([vRAAPI]$vra, [SecondDayActions]$secondDayActions, [string]$baseName, [string]$desc, [Array]$approverGroupAtDomainList, [ref] $processedApprovalPoliciesIDs)
{
	# Récupération de la liste des fichiers JSON à utiliser pour créer les approval policies utilisées dans les 2nd day actions.
	$approvalPolicyList = $secondDayActions.getJSONApprovalPoliciesFilesInfos($targetTenant)

	# Parcours des fichiers JSON identifiés et création des approval policies si elles n'existent pas encore
	Foreach($approvalPolicyInfos in $approvalPolicyList)
	{
		
		# Création de l'approval policy 
		# On regarde combien il y a de level d'approbation à mettre en on ne prend potentiellement qu'une partie des adresses mails
		# d'approbation. Si on laisse le tout, on va créer un approval level par élément se trouvant dans $approverGroupAtDomainList
		$actionReqApprovalPolicy = createApprovalPolicyIfNotExists -vra $vra -name $baseName -desc $desc `
								-approverGroupAtDomainList $approverGroupAtDomainList[0..($approvalPolicyInfos.approvalLevels-1)] `
								-approvalLevelJSON $approvalPolicyInfos.approvalLevelJSON -approvalPolicyJSON $approvalPolicyInfos.approvalPolicyJSON `
								-additionnalReplace $approvalPolicyInfos.JSONReplacements -processedApprovalPoliciesIDs $processedApprovalPoliciesIDs

		# On utilise le hash renvoyé par getJSONApprovalPoliciesFilesInfos() afin de dire quel est l'ID de l'approval policy associée
		# cette information sera utilisée plus tard pour affecter l'approval policy à l'action au sein de vRA, dans l'entitlement.
		$secondDayActions.setActionApprovalPolicyId($approvalPolicyInfos.actionHash, $actionReqApprovalPolicy.id)

	}

}

<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) ou met à jour un Business Group (si existant)

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $existingBGList		-> Liste des BG existants
	IN  : $bgUnitID				-> (optionnel) No d'unité du BG à ajouter/mettre à jour.
									A passer uniquement si tenant EPFL, sinon ""
	IN  : $bgSnowSvcID			-> (optionnel) No de service dans Snow pour le BG à ajouter/mettre à jour.
									A passer uniquement si tenant ITServices, sinon ""
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
	param([vRAAPI]$vra, [Array]$existingBGList, [string]$bgUnitID, [string]$bgSnowSvcID, [string]$bgName, [string]$bgDesc, [string]$machinePrefixName, [string]$capacityAlertsEmail,[System.Collections.Hashtable]$customProperties)

	# On transforme à null si "" pour que ça passe correctement plus loin
	if($machinePrefixName -eq "")
	{
		$machinePrefixName = $null
	}

	# Si on doit gérer le tenant contenant toutes les Unités,
	if(($bgUnitID -ne "") -and ($bgSnowSvcID -eq ""))
	{
		# Recherche du BG par son no d'unité.
		$bg = getBGWithCustomProp -fromList $existingBGList -customPropName $global:VRA_CUSTOM_PROP_EPFL_UNIT_ID -customPropValue $bgUnitID

		# Si la recherche du BG par son no de l'unité ne donne rien,
		if($null -eq $bg)
		{
			# Ajout des customs properties en vue de sa création
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE__UNIT
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_STATUS"] = $global:VRA_BG_STATUS__ALIVE
		}

		# Tentative de recherche du préfix de machine
		$machinePrefix = $vra.getMachinePrefix($machinePrefixName)

		# Si on ne trouve pas de préfixe de machine pour le nouveau BG,
		if($null -eq $machinePrefix)
		{
			# Si le BG n'existe pas, 
			if($null -eq $bg)
			{
				$logHistory.addWarningAndDisplay(("No machine prefix found for {0}, skipping" -f $machinePrefixName))
				# On enregistre le préfixe de machine inexistant
				$notifications['newBGMachinePrefixNotFound'] += $machinePrefixName

				$counters.inc('BGNotCreated')
			}
			else # Le BG existe, il s'agit donc d'un renommage 
			{
				$logHistory.addWarningAndDisplay(("No machine prefix found for new faculty name ({0})" -f $machinePrefixName))
				# On enregistre le préfixe de machine inexistant
				$notifications['facRenameMachinePrefixNotFound'] += $machinePrefixName

				$counters.inc('BGNotRenamed')
			}
			# on sort
			return $null
		}
		$machinePrefixId = $machinePrefix.id
	}
	# On doit gérer le tenant ITServices
	elseif(($bgUnitID -eq "") -and ($bgSnowSvcID -ne "")) 
	{
		# Recherche du BG par son ID de service dans ServiceNow
		$bg = getBGWithCustomProp -fromList $existingBGList -customPropName $global:VRA_CUSTOM_PROP_EPFL_SNOW_SVC_ID -customPropValue $bgSnowSvcID

		# On tente de rechercher le BG par son nom et s'il n'existe pas,
		if($null -eq $bg)
		{
			# Création des propriété custom
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE__SERVICE
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_STATUS"] = $global:VRA_BG_STATUS__ALIVE
		}
		# Pas d'ID de machine pour ce Tenant
		$machinePrefixId = $null
	}
	else 
	{
		Throw "Incorrect values given for params 'bgUnitID' ({0}) and 'bgSnowSvcID' ({1})" -f $bgUnitID, $bgSnowSvcID
	}

	<# Si le BG n'existe pas, ce qui peut arriver dans les cas suivants :
		Tenant EPFL:
		- nouvelle unité (avec éventuellement nouvelle faculté)
		Tenant ITServices
		- nouveau service
	#>
	if($null -eq $bg)
	{

		$logHistory.addLineAndDisplay("-> BG doesn't exists, creating...")
		# Création du BG
		$bg = $vra.addBG($bgName, $bgDesc, $capacityAlertsEmail, $machinePrefixId, $customProperties)

		$counters.inc('BGCreated')
	}
	# Si le BG existe,
	else
	{

		# Si le BG n'a pas la custom property $global:getBGCustomPropValue, on l'ajoute
		# FIXME: Cette partie de code pourra être enlevée au bout d'un moment car elle est juste prévue pour mettre à jours
		# les BG existants avec la nouvelle "Custom Property"
		if($null -eq (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE))
		{
			# Ajout de la custom Property avec la valeur par défaut 
			$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE" = $global:VRA_BG_RES_MANAGE__AUTO})
		}

		# Si le nom du BG est incorrect, (par exemple si le nom de l'unité ou celle de la faculté a changé)
		# Note: Dans le cas du tenant ITServices, vu qu'on fait une recherche avec le nom, ce test ne retournera
		# 		jamais $true
		# OU
		# Si le BG est désactivé
		if(($bg.name -ne $bgName) -or ($bg.description -ne $bgDesc) -or (!(isBGAlive -bg $bg)))
		{

			# S'il y a eu changement de nom,
			if($bg.name -ne $bgName)
			{
				# Recherche du nom actuel du dossier où se trouvent les ISO du BG
				$bgISOFolderCurrent = $nameGenerator.getNASPrivateISOPath($bg.name)
				# Recherche du nouveau nom du dossier où devront se trouver les ISO
				$bgISOFolderNew = $nameGenerator.getNASPrivateISOPath($bgName)

				$logHistory.addLineAndDisplay(("-> Renaming ISO folder for BG: '{0}' to '{1}'" -f $bgISOFolderCurrent, $bgISOFolderNew))
				
				try 
				{
					<# Renommage du dossier en mode "force". Aucune idée de savoir quel est le comportement dans le cas où une ISO est montée...
					Mais la probabilité qu'une unité soit renommée est déjà très faible, et je pense que c'est encore plus improbable qu'en 
					même temps une ISO soit montée dans une VM. 
					On met "-ErrorAction 'Stop'" pour s'assurer qu'en cas d'erreur on passe bien dans le "catch". Si on ne le fait pas, 
					ça va passer tout droit et simplement afficher l'erreur à la console. On n'aura pas de possibilité d'effectuer des 
					actions suite à l'erreur. #>
					Rename-Item -Path $bgISOFolderCurrent -NewName $bgISOFolderNew -Force -ErrorAction 'Stop'
				}
				catch 
				{
					<# Erreur de renommage, probablement car ISO montée. Dans ce cas-là, on fait en sorte de notifier les admins.
					Le dossier portant l'ancien nom va donc rester et un nouveau dossier sera créé automatiquement avec le nouveau nom à
					la fin du script du fait qu'il n'existe pas. #> 
					$logHistory.addErrorAndDisplay(("-> Error renaming folder. Error is : {0}" -f $_.Error.Message))
				
					# Ajout d'information dans les notifications pour faire en sorte que les admins soient informés par mail.
					$notifications['ISOFolderNotRenamed'] += ("{0} -> {1}" -f $bgISOFolderCurrent, $bgISOFolderNew)

					# On continue ensuite l'exécution normalement 
				}
				
			}

			$logHistory.addLineAndDisplay(("-> Updating and/or Reactivating BG '{0}' to '{1}'" -f $bg.name, $bgName))

			# Mise à jour des informations
			$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_VRA_BG_STATUS" = $global:VRA_BG_STATUS__ALIVE})

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

	# On recherche l'entitlement 
	$ent = $vra.getBGEnt($bg.id)

	if($null -eq $ent)
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
	$publicServices = $vra.getServiceListMatch($global:VRA_SERVICE_SUFFIX__PUBLIC)

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

				# On met à jour l'ID de l'approval policy dans le cas où elle aurait changé (peut arriver si on a forcé la recréation de celles-ci)
				$entService.approvalPolicyId = $approvalPolicy.id
				
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
	BUT : Envoie un mail aux admins pour leur dire qu'il y a eu un problème avec le
		fichier JSON contenant les "2nd day actions" 
	
	REMARQUE:
	La variable $targetEnv est utilisée de manière globale.

	IN  : $errorMsg		-> Message d'erreur

	RET : Rien
#>
function sendErrorMail2ndDayActionFile
{
	(param [string] $errorMsg)

	$docUrl = "https://sico.epfl.ch:8443/pages/viewpage.action?pageId=74055755"
	$mailSubject = getvRAMailSubject -shortSubject "Error - 2nd day action JSON file error!" -targetEnv $targetEnv -targetTenant $targetTenant
	$message = getvRAMailContent -content ("Une erreur est survenue durant le chargement du fichier contenant la liste des '2nd day actions':<br>`
	{0}<br><br>Veuillez faire le nécessaire à partir de la <a href='{1}'>documentation suivante</a>." -f $errorMsg, $docUrl)	

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $message
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


	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $message
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

	# Si les réservations sont gérées de manière manuelle pour le BG
	if((getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE) -eq $global:VRA_BG_RES_MANAGE__MAN)
	{
		$logHistory.addLineAndDisplay("-> Reservation are manually managed for BG, skipping this part...")	
		return
	}
	

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
		if($null -eq $matchingRes)
		{
			$logHistory.addLineAndDisplay(("--> Adding Reservation '{0}' from template '{1}'..." -f $resName, $resTemplate.name))
			$dummy = $vra.addResFromTemplate($resTemplate, $resName, $bg.tenant, $bg.id)

			$counters.inc('ResCreated')
		}
		else # La Reservation existe
		{
			# On appelle la fonction de mise à jour mais c'est cette dernière qui va déterminer si une mise à jour est
			# effectivement nécessaire (car il y a eu des changements) ou pas...
			$logHistory.addLineAndDisplay(("--> Updating Reservation if needed '{0}' to '{1}'..." -f $matchingRes.name, $resName))
			$updateResult = $vra.updateRes($matchingRes, $resTemplate, $resName)

			# Si la Reservation a effectivement été mise à jour 
			if($updateResult[1])
			{
				$counters.inc('ResUpdated')
			}
		}
	}# FIN BOUCLE parcours de templates trouvés 


	# Parcours des Reservations existantes pour le BG
	Foreach($bgRes in $bgResList)
	{
		# Si la réservation courante est "de trop", on l'efface 
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

	RET : $true si effacé
		  $false si pas effacé (mis en ghost)
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
			$vra.updateBG($bg, $null, $null, $null, @{"$global:VRA_CUSTOM_PROP_VRA_BG_STATUS" = $global:VRA_BG_STATUS__GHOST})

			$counters.inc('BGGhost')

			# Si Tenant EPFL
			if($bg.tenant -eq $global:VRA_TENANT__EPFL)
			{
				# Récupération du contenu du rôle des admins de faculté pour le BG
				$facAdmins = $vra.getBGRoleContent($bg.id, "CSP_SUBTENANT_MANAGER") 
				
				# Ajout des admins de la faculté de l'unité du BG afin qu'ils puissent gérer les élments du BG.
				createOrUpdateBGRoles -vra $vra -bg $bg -sharedGrpList $facAdmins
			}
			# Si Tenant ITServices
			elseif($bg.tenant -eq $global:VRA_TENANT__ITSERVICES)
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

		$deleted = $false

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



		# Incrémentation du compteur
		$counters.inc('BGDeleted')

		$deleted = $true
	}

	return $deleted
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
	if($null -eq $entry)
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
	if($null -ne $customProp)
	{
		return ($customProp.value.values.entries | Where-Object {$_.key -eq "value"}).value.value -eq $global:VRA_BG_STATUS__ALIVE
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
ne contiennent plus aucun utilisateur. Cela signifie donc que les Business Groups associés existent toujours mais ne sont plus utilisables par qui que ce soit....<br> `
Il s'agit peut-être d'une erreur dans la synchro depuis MIIS ou autre, à surveiller:`
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

				# ---------------------------------------
				# Renommage de dossier d'ISO privées échoué
				'ISOFolderNotRenamed'
				{
					$mailSubject = getvRAMailSubject -shortSubject "Error - Private ISO folder renaming failed" -targetEnv $targetEnv  -targetTenant $targetTenant
					$message = getvRAMailContent -content ("Les dossiers suivants n'ont pas pu être renommés suite au changement du nom du Business Group auxquels ils sont associés.`
Du coup, un nouveau dossier vide a été créé avec le bon nom et il faudra manuellement faire du ménage pour l'ancien dossier.`
<br><ul><li>{0}</li></ul>"  -f  ($uniqueNotifications -join "</li>`n<li>"))
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


<#
-------------------------------------------------------------------------------------
	BUT : Ajoute un NSGroup à NSX

	IN  : $nsx					-> Objet permettant d'accéder à l'API NSX
	IN  : $nsxNSGroupName		-> Nom du groupe
	IN  : $nsxNSGroupDesc		-> Description du groupe
	IN  : $nsxSecurityTag		-> Le tag de sécurité 

	RET : Objet représentant le NSGroup
#>
function createNSGroupIfNotExists 
{
	param([NSXAPI]$nsx, [string]$nsxNSGroupName, [string]$nsxNSGroupDesc, [string]$nsxSecurityTag)

	$nsGroup = $nsx.getNSGroupByName($nsxNSGroupName)

	# Si le NSGroup n'existe pas,
	if($null -eq $nsGroup)
	{
		$logHistory.addLineAndDisplay(("-> Creating NSX NS Group '{0}'... " -f $nsxNSGroupName))

		# Création de celui-ci
		$nsGroup = $nsx.addNSGroup($nsxNSGroupName, $nsxNSGroupDesc, $nsxSecurityTag)

		$counters.inc('NSXNSGroupCreated')
	}
	else  # Le NS Group existe
	{
		$logHistory.addLineAndDisplay(("-> NSX NS Group '{0}' already exists!" -f $nsxNSGroupName))

		# Incrément du compteur et gestion des doublons 
		$counters.inc('NSXNSGroupExisting', $nsxNSGroupName)
	}

	return $nsGroup
}


<#
-------------------------------------------------------------------------------------
	BUT : Ajoute une section de firewall vide à NSX

	IN  : $nsx				-> Objet permettant d'accéder à l'API NSX
	IN  : $nsxFWSectionName	-> Nom du groupe
	IN  : $nsxFWSectionDesc	-> Description du groupe
	
	RET : Objet représentant la section de firewall
#>
function createFirewallSectionIfNotExists
{
	param([NSXAPI]$nsx, [string]$nsxFWSectionName, [string]$nsxFWSectionDesc)

	$fwSection = $nsx.getFirewallSectionByName($nsxFWSectionName)

	# Si la section n'existe pas, 
	if($null -eq $fwSection)
	{
		# Recherche de la section qui doit se trouver après la section que l'on va créer.
		$insertBeforeSection = $nsx.getFirewallSectionByName($global:NSX_CREATE_FIREWALL_EMPTY_SECTION_BEFORE_NAME)

		# Si la section n'existe pas, il y a une erreur 
		if($null -eq $insertBeforeSection)
		{
			Throw ("NSX Firewall section not found: {0}" -f $global:NSX_CREATE_FIREWALL_EMPTY_SECTION_BEFORE_NAME)
		}

		$logHistory.addLineAndDisplay(("-> Creating NSX Firewall section '{0}'... " -f $nsxFWSectionName))

		# Création de la section
		$fwSection = $nsx.addFirewallSection($nsxFWSectionName, $nsxFWSectionDesc, $insertBeforeSection.id)

		$counters.inc('NSXFWSectionCreated')

	}
	else # La section existe 
	{
		$logHistory.addLineAndDisplay(("-> NSX Firewall section '{0}' already exists!" -f $nsxFWSectionName))

		# Incrément du compteur avec gestion des doublons
		$counters.inc('NSXFWSectionExisting', $nsxFWSectionName)
	}

	return $fwSection
}


<#
-------------------------------------------------------------------------------------
	BUT : Ajoute les règles de firewall dans une section de firewall

	IN  : $nsx				-> Objet permettant d'accéder à l'API NSX
	IN  : $nsxNSGroup		-> Objet représantant le NS Group
	IN  : $nsxFWSection		-> Objet représantant la section de Firewall à laquelle ajouter les règles
	IN  : $nsxFWRuleNames	-> Tableau avec les noms des règles

#>
function createFirewallSectionRulesIfNotExists
{
	param([NSXAPI]$nsx, [PSObject]$nsxFWSection, [PSObject]$nsxNSGroup, [Array]$nsxFWRuleNames)

	# On met dans des variables pour que ça soit plus clair
	$ruleIn, $ruleComm, $ruleOut = $nsxFWRuleNames
	# Représentation "string" pour les règles 
	$allRules = $nsxFWRuleNames -join "::"

	$nbExpectedRules = 3
	# On commence par check le nombre de noms qu'on a pour les règles
	if($nsxFWRuleNames.Count -ne $nbExpectedRules)
	{
		Throw ("# of rules for NSX Section incorrect! {0} expected, {1} given " -f $nbExpectedRules, $nsxFWRuleNames.Count)
	}

	# Recherche des règles existantes 
	$rules = $nsx.getFirewallSectionRules($nsxFWSection.id)

	# Si les règles n'existent pas
	if($rules.Count -eq 0)
	{
		
		$logHistory.addLineAndDisplay(("-> Creating NSX Firewall section rules '{0}', '{1}', '{2}'... " -f $ruleIn, $ruleComm, $ruleOut))

		# Création des règles 
		$rules = $nsx.addFirewallSectionRules($nsxFWSection.id, $ruleIn, $ruleComm, $ruleOut, $nsxNSGroup)

		$counters.inc('NSXFWSectionRulesCreated')
	}
	else # Les règles existent déjà 
	{
		$logHistory.addLineAndDisplay(("-> NSX Firewall section rules '{0}', '{1}', '{2}' already exists!" -f  $ruleIn, $ruleComm, $ruleOut))

		# Incrément du compteur avec gestion des doublons
		$counters.inc('NSXFWSectionRulesExisting', $allRules)
	}

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
	$logHistory =[LogHistory]::new('2.sync-BG-from-AD', (Join-Path $SCRIPT_PATH "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ArgsPrototypeChecker.inc.ps1"))

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	$doneBGList = @()

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
	# Approval policies 
	$counters.add('AppPolCreated', '# Approval Policies created')
	$counters.add('AppPolExisting', '# Approval Policies already existing')
	# NSX - NS Group
	$counters.add('NSXNSGroupCreated', '# NSX NS Group created')
	$counters.add('NSXNSGroupExisting', '# NSX NS Group existing')
	# NSX - Firewall section
	$counters.add('NSXFWSectionCreated', '# NSX Firewall Section created')
	$counters.add('NSXFWSectionExisting', '# NSX Firewall Section existing')
	# NSX - Firewall section rules
	$counters.add('NSXFWSectionRulesCreated', '# NSX Firewall Section Rules created')
	$counters.add('NSXFWSectionRulesExisting', '# NSX Firewall Section Rules existing')


	<# Pour enregistrer la liste des IDs des approval policies qui ont été traitées. Ceci permettra de désactiver les autres à la fin. #>
	$processedApprovalPoliciesIDs = @()

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
					adGroupsNotFound = @()
					ISOFolderNotRenamed = @()}


	$logHistory.addLineAndDisplay(("Executed with parameters: Environment={0}, Tenant={1}" -f $targetEnv, $targetTenant))


	
	# Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, $targetTenant, "user"), 
						 $configVra.getConfigValue($targetEnv, $targetTenant, "password"))

	# Création d'une connexion au serveur NSX pour accéder aux API REST de NSX
	$logHistory.addLineAndDisplay("Connecting to NSX-T...")
	$nsx = [NSXAPI]::new($configNSX.getConfigValue($targetEnv, "server"), $configNSX.getConfigValue($targetEnv, "user"), $configNSX.getConfigValue($targetEnv, "password"))


	# Recherche de BG existants
	$existingBGList = $vra.getBGList()
	
	<# Recherche des groupes pour lesquels il faudra créer des OUs
	 On prend tous les groupes de l'OU et on fait ensuite un filtre avec une expression régulière sur le nom. Au début, on prenait le début du nom du
	 groupe pour filtrer mais d'autres groupes avec des noms débutant de la même manière ont été ajoutés donc le filtre par expression régulière
	 a été nécessaire.
	#>
	if($targetTenant -eq $global:VRA_TENANT__EPFL)
	{
		$adGroupNameRegex = $nameGenerator.getEPFLADGroupNameRegEx("CSP_CONSUMER")
	}
	else 
	{
		$adGroupNameRegex = $nameGenerator.getITSADGroupNameRegEx("CSP_CONSUMER")
	}
	$adGroupList = Get-ADGroup -Filter ("Name -like '*'") -Server ad2.epfl.ch -SearchBase $nameGenerator.getADGroupsOUDN($true) -Properties Description | 
	Where-Object {$_.Name -match $adGroupNameRegex} 

	# Création de l'objet pour récupérer les informations sur les approval policies à créer pour les demandes de nouveaux éléments
	$newItems = [NewItems]::new("vra-new-items.json")

	# Création de l'objet pour gérer les 2nd day actions
	$secondDayActions = [SecondDayActions]::new()

	# Parcours des groupes AD pour l'environnement/tenant donné
	$adGroupList | ForEach-Object {

		$counters.inc('ADGroups')

		# Pour repartir "propre" pour le groupe AD courant
		$secondDayActions.clearApprovalPolicyMapping()

		# Génération du nom du groupe avec le domaine
		$ADFullGroupName = $nameGenerator.getADGroupFQDN($_.Name)
		$logHistory.addLineAndDisplay(("-> Current AD group         : $($_.Name)"))

		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group

		# Ajout de l'adresse par défaut à laquelle envoyer les mails. 
		$capacityAlertMails = @($configGlobal.getConfigValue("mail", "capacityAlert"))
		
		# Si Tenant EPFL
		if($targetTenant -eq $global:VRA_TENANT__EPFL)
		{
			# Pour signifier à la fonction createOrUpdateBG qu'on n'est pas dans le tenant ITServices.
			$snowServiceId = ""

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
			
			# Ajout de l'adresse mail à laquelle envoyer les "capacity alerts" pour le BG. On prend le niveau 1 car c'est celui de EXHEB
			# NOTE : 15.02.2019 - Les approbations pour les ressources sont faites par admin IaaS (level 1), donc plus besoin d'info aux approbateurs level 2
			#$capacityAlertMails += $nameGenerator.getEPFLApproveGroupsEmail($faculty, 1)

			# Nom et description de la policy d'approbation + nom du groupe AD qui devra approuver
			$itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getEPFLApprovalPolicyNameAndDesc($faculty, $global:APPROVE_POLICY_TYPE__ITEM_REQ)
			$actionReqBaseApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getEPFLApprovalPolicyNameAndDesc($faculty, $global:APPROVE_POLICY_TYPE__ACTION_REQ)
			
			# Tableau pour les approbateurs des différents niveaux
			$approverGroupAtDomainList = @()
			$level = 0
			# on fait une 
			While($true)
			{
				$level += 1
				$levelGroupInfos = $nameGenerator.getEPFLApproveADGroupName($faculty, $level, $true)
				# Si on n'a plus de groupe pour le level courant, on sort
				if($null -eq $levelGroupInfos)
				{
					break
				}
				$approverGroupAtDomainList += $levelGroupInfos.name
			}

			# Vu qu'il y aura des quotas pour les demandes sur le tenant EPFL, on utilise une policy du type "Event Subscription", ceci afin d'appeler un Workflow défini
			# qui se chargera de contrôler le quota.
			$itemReqApprovalPolicyJSON = $newItems.getApprovalPolicyJSON($targetTenant)
			# -> Pour créer les différents niveaux (si besoin) pour l'approbation 
			$itemReqApprovalLevelJSON = $newItems.getApprovalLevelJSON($targetTenant)


			# -- NSX --
			# Nom et description du NSGroup
			$nsxNSGroupName, $nsxNSGroupDesc = $nameGenerator.getEPFLSecurityGroupNameAndDesc($faculty)
			# Nom du security Tag
			$nsxSTName = $nameGenerator.getEPFLSecurityTagName($faculty)
			# Nom et description de la section de firewall
			$nsxFWSectionName, $nsxFWSectionDesc = $nameGenerator.getEPFLFirewallSectionNameAndDesc($faculty)
			# Nom de règles de firewall
			$nsxFWRuleNames = $nameGenerator.getEPFLFirewallRuleNames($faculty)

		}
		# Si Tenant ITServices
		elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
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
			# NOTE : 15.02.2019 - Les approbations pour les ressources sont faites par admin IaaS (level 1), donc plus besoin d'info aux approbateurs level 2
			#$capacityAlertMails += $nameGenerator.getITSApproveGroupsEmail($serviceShortName, 1)

			# Nom de la policy d'approbation ainsi que du groupe d'approbateurs
			$itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getITSApprovalPolicyNameAndDesc($serviceShortName, $serviceLongName, $global:APPROVE_POLICY_TYPE__ITEM_REQ)
			$actionReqBaseApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getITSApprovalPolicyNameAndDesc($serviceShortName, $serviceLongName, $global:APPROVE_POLICY_TYPE__ACTION_REQ)
			
			# Tableau pour les approbateurs des différents niveaux
			$approverGroupAtDomainList = @()
			$level = 0
			# on fait une 
			While($true)
			{
				$level += 1
				$levelGroupInfos = $nameGenerator.getITSApproveADGroupName($serviceShortName, $level, $true)

				# Si on a un nom de groupe vide, c'est qu'il n'y a aucun groupe pour le level courant donc on peut sortir de la boucle
				if($null -eq $levelGroupInfos)
				{
					break
				}
				$approverGroupAtDomainList += $levelGroupInfos.name
			}
			
			# Définition des noms des fichiers JSON contenant le nécessaire pour créer l'approval policy pour les demandes de NOUVEAUX éléments pour le tenant ITServices
			# -> Fichier de base
			$itemReqApprovalPolicyJSON = $newItems.getApprovalPolicyJSON($targetTenant)
			# -> Pour créer les différents niveaux (si besoin) pour l'approbation (appelée dans tous les cas, avec un groupe devant approuver)
			$itemReqApprovalLevelJSON = $newItems.getApprovalLevelJSON($targetTenant)


			# -- NSX --
			# Nom et description du NSGroup
			$nsxNSGroupName, $nsxNSGroupDesc = $nameGenerator.getITSSecurityGroupNameAndDesc($serviceShortName, $bgName, $snowServiceId)
			# Nom du security Tag
			$nsxSTName = $nameGenerator.getITSSecurityTagName($serviceShortName)
			# Nom et description de la section de firewall
			$nsxFWSectionName, $nsxFWSectionDesc = $nameGenerator.getITSFirewallSectionNameAndDesc($serviceShortName)
			# Nom de règles de firewall
			$nsxFWRuleNames = $nameGenerator.getITSFirewallRuleNames($serviceShortName)
		}

		# Contrôle de l'existance des groupes. Si l'un d'eux n'existe pas dans AD, une exception est levée.
		if( ((checkIfADGroupsExists -groupList $managerGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $supportGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $sharedGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $userGrpList) -eq $false) -or `
			((checkIfADGroupsExists -groupList $approverGroupAtDomainList) -eq $false))
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

		
		
		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group 

		# Création ou mise à jour du Business Group
		$bg = createOrUpdateBG -vra $vra -existingBGList $existingBGList -bgUnitID $unitID -bgSnowSvcID $snowServiceId -bgName $bgName -bgDesc $bgDesc `
									-machinePrefixName $machinePrefixName -capacityAlertsEmail ($capacityAlertMails -join ",") -customProperties $bgCustomProperties

		# Si BG pas créé, on passe au suivant (la fonction de création a déjà enregistré les infos sur ce qui ne s'est pas bien passé)
		if($null -eq $bg)
		{
			# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			return
		}


		# ----------------------------------------------------------------------------------
		# --------------------------------- Approval policies
		# Création des Approval policies pour les demandes de nouveaux éléments et les reconfigurations si celles-ci n'existent pas encore
		$itemReqApprovalPolicy = createApprovalPolicyIfNotExists -vra $vra -name $itemReqApprovalPolicyName -desc $itemReqApprovalPolicyDesc `
																 -approvalLevelJSON $itemReqApprovalLevelJSON -approverGroupAtDomainList $approverGroupAtDomainList  `
																 -approvalPolicyJSON $itemReqApprovalPolicyJSON `
																 -additionnalReplace @{} -processedApprovalPoliciesIDs ([ref]$processedApprovalPoliciesIDs)

		# Pour les approval policies des 2nd day actions, on récupère un tableau car il peut y avoir plusieurs policies
		create2ndDayActionApprovalPolicies -vra $vra -baseName $actionReqBaseApprovalPolicyName -desc $actionReqApprovalPolicyDesc `
											-approverGroupAtDomainList $approverGroupAtDomainList -secondDayActions $secondDayActions `
											-processedApprovalPoliciesIDs ([ref]$processedApprovalPoliciesIDs)

		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Roles
		createOrUpdateBGRoles -vra $vra -bg $bg -managerGrpList $managerGrpList -supportGrpList $supportGrpList `
									-sharedGrpList $sharedGrpList -userGrpList $userGrpList


		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement
		$ent = createOrUpdateBGEnt -vra $vra -bg $bg -entName $entName -entDesc $entDesc
		
		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement - 2nd day Actions
		$logHistory.addLineAndDisplay("-> (prepare) Adding 2nd day Actions to Entitlement...")
		$ent = $vra.prepareEntActions($ent, $secondDayActions)
		
		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group Entitlement - Services
		$ent = prepareAddMissingBGEntPublicServices -vra $vra -ent $ent -approvalPolicy $itemReqApprovalPolicy


		# Mise à jour de l'entitlement avec les modifications apportées ci-dessus
		$logHistory.addLineAndDisplay("-> Updating Entitlement...")
		
		$ent = $vra.updateEnt($ent, $true)



		# ----------------------------------------------------------------------------------
		# --------------------------------- Reservations
		createOrUpdateBGReservations -vra $vra -bg $bg -resTemplatePrefix $nameGenerator.getReservationTemplatePrefix()

		


		# ----------------------------------------------------------------------------------
		# --------------------------------- Dossier pour les ISO privées
		
		# Recherche de l'UNC jusqu'au dossier où mettre les ISO pour le BG
		$bgISOFolder = $nameGenerator.getNASPrivateISOPath($bgName)

		# Si on a effectivement un dossier où mettre les ISO et qu'il n'existe pas encore,
		if(($bgISOFolder -ne "") -and (-not (Test-Path $bgISOFolder)))
		{
			$logHistory.addLineAndDisplay(("--> Creating ISO folder '{0}'..." -f $bgISOFolder))
			# On le créé
			$dummy = New-Item -Path $bgISOFolder -ItemType:Directory

			# Récupération et modification des ACL pour ajouter les groupes AD qui sont pour le Role "Shared" dans le BG
			$acl = Get-Acl $bgISOFolder
			ForEach($sharedGrp in $sharedGrpList)
			{
				$ar = New-Object  system.security.accesscontrol.filesystemaccessrule($sharedGrp, "Modify", "ContainerInherit,ObjectInherit", "None","Allow")
				$acl.SetAccessRule($ar)
			}
			Set-Acl $bgISOFolder $acl

		} # FIN SI on n'est pas sur l'environnement de DEV 
		



		# ----------------------------------------------------------------------------------
		# --------------------------------- NSX

		# Création du NSGroup si besoin 
		$nsxNSGroup = createNSGroupIfNotExists -nsx $nsx -nsxNSGroupName $nsxNSGroupName -nsxNSGroupDesc $nsxNSGroupDesc -nsxSecurityTag $nsxSTName

		# Création de la section de Firewall si besoin
		$nsxFWSection = createFirewallSectionIfNotExists -nsx $nsx  -nsxFWSectionName $nsxFWSectionName -nsxFWSectionDesc $nsxFWSectionDesc

		# Création des règles dans la section de firewall
		createFirewallSectionRulesIfNotExists -nsx $nsx -nsxFWSection $nsxFWSection -nsxNSGroup $nsxNSGroup -nsxFWRuleNames $nsxFWRuleNames

		# Verrouillage de la section de firewall (si elle ne l'est pas encore)
		$nsxFWSection = $nsx.lockFirewallSection($nsxFWSection.id)

		$doneBGList += $bg.name

	}# Fin boucle de parcours des groupes AD pour l'environnement/tenant donnés

	$logHistory.addLineAndDisplay("Business Groups created from AD!")

	# ----------------------------------------------------------------------------------------------------------------------
	# ----------------------------------------------------------------------------------------------------------------------

	$logHistory.addLineAndDisplay("Cleaning 'old' Business Groups")
	
	# Recherche et parcours de la liste des BG commençant par le bon nom pour le tenant
	$vra.getBGList() | ForEach-Object {

		# Si c'est un BG d'unité ou de service et s'il faut l'effacer
		if(((isBGOfType -bg $_ -type $global:VRA_BG_TYPE__SERVICE) -or (isBGOfType -bg $_ -type $global:VRA_BG_TYPE__UNIT)) -and `
			($doneBGList -notcontains $_.name))
		{
			$logHistory.addLineAndDisplay(("-> Deleting Business Group '{0}'..." -f $_.name))
			$deleted = deleteBGAndComponentsIfPossible -vra $vra -bg $_


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

	# ----------------------------------------------------------------------------------------------------------------------
	# ----------------------------------------------------------------------------------------------------------------------

	# Désactivation des approval policies qui ne sont pas utilisées
	# $logHistory.addLineAndDisplay("Deactivating unused Approval Policies")
	# $vra.getApprovalPolicyList() | ForEach-Object {
	# 	if($processedApprovalPoliciesIDs -notcontains $_.id)
	# 	{
	# 		$logHistory.addLineAndDisplay(("-> Deactivating Approval Policy '{0}'... " -f $_.name))
	# 		$res = $vra.setApprovalPolicyState($_, $false)
	# 	}
	# }


	$vra.disconnect()

	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$logHistory.addLineAndDisplay("Done")

	# Une dernière mise à jour
	$counters.set('MachinePrefNotFound', $notifications['newBGMachinePrefixNotFound'].count + `
										$notifications['facRenameMachinePrefixNotFound'].count)

	$logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

	# Si le fichier qui demandait à ce que l'on force la recréation des policies existe, on le supprime, afin d'éviter 
	# que le script ne s'exécute à nouveau en recréant les approval policies, ce qui ne serait pas très bien...
	$recreatePoliciesFile = ([IO.Path]::Combine("$SCRIPT_PATH", $global:SCRIPT_ACTION_FILE__RECREATE_APPROVAL_POLICIES))
	if(Test-Path -Path $recreatePoliciesFile)
	{
		Remove-Item -Path $recreatePoliciesFile
	}

}
catch # Dans le cas d'une erreur dans le script
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

	$logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant $targetTenant
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters ))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
	
}