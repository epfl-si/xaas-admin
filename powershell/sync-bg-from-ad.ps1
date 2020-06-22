<#
USAGES:
	sync-bg-from-ad.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl [-fullSync] [-resume]
#>
<#
	BUT 		: Crée/met à jour les Business groupes en fonction des groupes AD existant

	DATE 		: Février 2018
	AUTEUR 	: Lucien Chaboudez

	PARAMETRES : 
		$targetEnv		-> nom de l'environnement cible. Ceci est défini par les valeurs $global:TARGET_ENV__* 
						dans le fichier "define.inc.ps1"
		$targetTenant 	-> nom du tenant cible. Défini par les valeurs $global:VRA_TENANT__* dans le fichier
						"define.inc.ps1"
		$fullSync 		-> switch pour dire de prendre absolument tous les groupes AD pour faire le sync. Si 
						ce switch n'est pas donné, on prendra par défaut les groupes AD qui ont été modifiés
						durant les $global:AD_GROUP_MODIFIED_LAST_X_DAYS derniers jours (voir include/define.inc.ps1)
		$resume			-> switch pour dire s'il faut tenter de reprendre depuis une précédente exécution qui 
						aurait foiré.

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
	- FORCE_ISO_FOLDER_ACL_UPDATE -> forcer la mise à jour des ACLs des dossiers où se trouvent les ISO sur le NAS


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
param ( [string]$targetEnv, [string]$targetTenant, [switch]$fullSync, [switch]$resume)


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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ResumeOnFail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vROAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NSXAPI.inc.ps1"))



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
		(Test-Path -Path ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__RECREATE_APPROVAL_POLICIES))))
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
	IN  : $existingBGList		-> Tableau associatif avec la liste des BG, aura été créé via la fonction 
									createMappingBGList
	IN  : $bgUnitID				-> (optionnel) No d'unité du BG à ajouter/mettre à jour.
									A passer uniquement si tenant EPFL, sinon ""
	IN  : $bgSnowSvcID			-> (optionnel) No de service dans Snow pour le BG à ajouter/mettre à jour.
									A passer uniquement si tenant ITServices, sinon ""
	IN  : $bgName				-> Nom du BG
	IN  : $bgDesc				-> Description du BG
	IN  : $machinePrefixName	-> Nom du préfixe de machine à utiliser.
								   Peut être "" si le BG doit être créé dans le tenant ITServices.
	IN  : $financeCenter		-> NO du centre financier
	IN  : $capacityAlertsEmail	-> Adresse mail où envoyer les mails de "capacity alert"
	IN  : $customProperties		-> Tableau associatif avec les custom properties à mettre pour le BG. Celles-ci seront
								   complétées avec d'autres avant la création.

	RET : Objet représentant la Business Group
#>
function createOrUpdateBG
{
	param([vRAAPI]$vra, [Hashtable]$existingBGList, [string]$bgUnitID, [string]$bgSnowSvcID, [string]$bgName, [string]$bgDesc, [string]$machinePrefixName, [string]$financeCenter, [string]$capacityAlertsEmail,[System.Collections.Hashtable]$customProperties)

	# On transforme à null si "" pour que ça passe correctement plus loin
	if($machinePrefixName -eq "")
	{
		$machinePrefixName = $null
	}

	# Si on doit gérer le tenant contenant toutes les Unités,
	if(($bgUnitID -ne "") -and ($bgSnowSvcID -eq ""))
	{
		$tenantName = $global:VRA_TENANT__EPFL

		$bgIdProp = $bgUnitID
		
		# Recherche du BG par son no d'unité.
		$bg = getBGFromMappingList -mappingList $existingBGList -customPropValue $bgUnitID

		# Si la recherche du BG par son no de l'unité ne donne rien,
		if($null -eq $bg)
		{
			# Ajout des customs properties en vue de sa création
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE__UNIT
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
		$tenantName = $global:VRA_TENANT__ITSERVICES

		$bgIdProp = $bgSnowSvcID

		# Recherche du BG par son ID de service dans ServiceNow
		$bg = getBGFromMappingList -mappingList $existingBGList -customPropValue $bgSnowSvcID

		# On tente de rechercher le BG par son nom et s'il n'existe pas,
		if($null -eq $bg)
		{
			# Création des propriété custom
			$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_TYPE"] = $global:VRA_BG_TYPE__SERVICE
			
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
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_STATUS"] = $global:VRA_BG_STATUS__ALIVE
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE"] = $global:VRA_BG_RES_MANAGE__AUTO
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE"] = $global:VRA_BG_RES_MANAGE__AUTO

		$customProperties["$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER"] = $financeCenter

		# Ajout aussi des informations sur le Tenant et le BG car les mettre ici, c'est le seul moyen que l'on pour récupérer cette information
		# pour la génération des mails personnalisée... 
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_TENANT_NAME"] = $tenantName
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_NAME"] = $bgName
		

		$logHistory.addLineAndDisplay("-> BG doesn't exists, creating...")
		# Création du BG
		$bg = $vra.addBG($bgName, $bgDesc, $capacityAlertsEmail, $machinePrefixId, $customProperties)

		$counters.inc('BGCreated')
	}
	# Si le BG existe,
	else
	{

		$counters.inc('BGExisting')
		# ==========================================================================================

		# Si le BG n'a pas la custom property donnée, on l'ajoute
		# FIXME: Cette partie de code pourra être enlevée au bout d'un moment car elle est juste prévue pour mettre à jours
		# les BG existants avec la nouvelle "Custom Property"
		if($null -eq (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER))
		{
			# Ajout de la custom Property avec la valeur par défaut 
			$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER" = $financeCenter})
		}

		# Si le BG n'a pas la custom property donnée, on l'ajoute
		# FIXME: Cette partie de code pourra être enlevée au bout d'un moment car elle est juste prévue pour mettre à jours
		# les BG existants avec la nouvelle "Custom Property"
		if($null -eq (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID))
		{
			# Ajout de la custom Property avec la valeur par défaut 
			$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_EPFL_BG_ID" = $bgIdProp})
		}


		# ==========================================================================================

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
				
				# Mise à jour de la custom property qui contient le nom du BG
				$bg = $vra.updateBG($bg, $bgName, $bgDesc, $machinePrefixId, @{"$global:VRA_CUSTOM_PROP_VRA_BG_NAME" = $bgName})
				
			}# Fin s'il y a eu changement de nom 

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

		# Si le role est géré de manière manuelle pour le BG
		if((getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE) -eq $global:VRA_BG_RES_MANAGE__MAN)
		{
			$logHistory.addLineAndDisplay("---> Role manually managed, skipping it...")	
		}
		else # Le rôle est géré de manière automatique
		{
			$vra.deleteBGRoleContent($bg.id, "CSP_SUPPORT")
			$supportGrpList | ForEach-Object { $vra.addRoleToBG($bg.id, "CSP_SUPPORT", $_) }
		}
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
		# Si le nom a changé (car le nom du BG a changé) ou la description a changé 
		if(($ent.name -ne $entName) -or ($ent.description -ne $entDesc))
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

	$valToReplace = @{errorMsg = $errorMsg}
	$notificationMail.send("Error - 2nd day action JSON file error!", "2nd-action-json-file-error", $valToReplace)
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
	$valToReplace = @{}
	$notificationMail.send("Error - No Reservation Template found for tenant!", "no-reservation-template-found-for-tenant", $valToReplace)
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
	$resTemplateList = $vra.getResListMatch($resTemplatePrefix, $true)

	if($resTemplateList.Count -eq 0)
	{
		$logHistory.addErrorAndDisplay("No Reservation template found !! An email has been sent to administrators to inform them.")
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
	BUT : Met un BG en mode "ghost" dans le but qu'il soit effacé par la suite.
			On change aussi les droits d'accès
	IN  : $vra 		-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg		-> Objet contenant le BG a effacer. Cet objet aura été renvoyé
					   par un appel à une méthode de la classe vRAAPI
	RET : $true si mis en ghost
		  $false si pas mis en ghost
#>
function setBGAsGhostIfNot
{
	param([vRAAPI]$vra, [PSObject]$bg)

	# Si le BG est toujours actif
	if(isBGAlive -bg $bg)
	{
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

		$setAsGhost = $true

	} 
	else # Le BG est déjà en "ghost"
	{
		$setAsGhost = $false

		$logHistory.addLineAndDisplay("--> Already in 'ghost' status...")
	}

	return $setAsGhost
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

	$bgStatus = getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_STATUS

	# Si la "Custom property" a été trouvée,
	if($null -ne $bgStatus)
	{
		return $bgStatus -eq $global:VRA_BG_STATUS__ALIVE
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

			$valToReplace = @{}

			switch($notif)
			{
				# ---------------------------------------
				# Préfixes de machine non trouvés
				'newBGMachinePrefixNotFound'
				{
					$valToReplace.prefixList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Machine prefixes not found"
					$templateName = "bg-machine-prefix-not-found"
				}

				# ---------------------------------------
				# BG sans "custom property" permettant de définir le statut
				'bgWithoutCustomPropStatus'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.customProperty = $global:VRA_CUSTOM_PROP_VRA_BG_STATUS
					$mailSubject = "Warning - Business Group without '{{customProperty}}' custom property"
					$templateName = "bg-without-custom-prop"
				}

				# ---------------------------------------
				# BG sans "custom property" permettant de définir le type
				'bgWithoutCustomPropType'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.customProperty = $global:VRA_CUSTOM_PROP_VRA_BG_TYPE
					$mailSubject = "Warning - Business Group without '{{customProperty}}' custom property"
					$templateName = "bg-without-custom-prop"
				}

				# ---------------------------------------
				# BG marqué comme étant des 'ghost'
				'bgSetAsGhost'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Info - Business Group marked as 'ghost'"
					$templateName = "bg-set-as-ghost"
				}

				# ---------------------------------------
				# Préfix de machine non trouvé pour un renommage de faculté
				'facRenameMachinePrefixNotFound'
				{
					$valToReplace.prefixList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Machine prefixes not found for new faculty name"
					$templateName = "fac-rename-machine-prefix-not-found"
				}

				# ---------------------------------------
				# Groupes AD soudainement devenus vides...
				'emptyADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Info - AD groups empty for Business Group"
					$templateName = "empty-ad-groups"
				}

				# ---------------------------------------
				# Groupes AD pour les rôles...
				'adGroupsNotFound'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - AD groups not found for Business Group"
					$templateName = "ad-groups-not-found-for-bg"
				}

				# ---------------------------------------
				# Renommage de dossier d'ISO privées échoué
				'ISOFolderNotRenamed'
				{
					$valToReplace.folderList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Private ISO folder renaming failed"
					$templateName = "iso-folder-not-renamed"
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

		# Si on n'a pas encore check le groupe,
		if($global:existingADGroups -notcontains $groupName)
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
					$logHistory.addWarningAndDisplay(("Security group '{0}' not found in Active Directory" -f $groupName))
					# Enregistrement du nom du groupe
					$notifications['adGroupsNotFound'] += $groupName
					$allOK = $false
				}
				else # Le groupe est OK
				{
					# On l'enregistre pour ne plus avoir le à le contrôler par la suite 
					$global:existingADGroups += $groupName
				}

			}# FIN Si le groupe ressemble à un groupe AD

		} # Fin SI le groupe n'est pas dans ceux qui sont OK

	} # FIN BOUCLE sur les groupes à contrôler
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
	IN  : $nsxNSGroup		-> Objet réprésentant le NSGroup auquel lier la section
	
	RET : Objet représentant la section de firewall
#>
function createFirewallSectionIfNotExists
{
	param([NSXAPI]$nsx, [string]$nsxFWSectionName, [string]$nsxFWSectionDesc, [psobject]$nsxNSGroup)

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
		$fwSection = $nsx.addFirewallSection($nsxFWSectionName, $nsxFWSectionDesc, $insertBeforeSection.id, $nsxNSGroup)

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

	$nbExpectedRules = 4
	# On commence par check le nombre de noms qu'on a pour les règles
	if($nsxFWRuleNames.Count -ne $nbExpectedRules)
	{
		Throw ("# of rules for NSX Section incorrect! {0} expected, {1} given " -f $nbExpectedRules, $nsxFWRuleNames.Count)
	}

	# On met dans des variables pour que ça soit plus clair
	$ruleIn, $ruleComm, $ruleOut, $ruleDeny = $nsxFWRuleNames
	# Représentation "string" pour les règles, utilisée pour gérer les doublons pour le compteur de règles existantes
	$allRules = $nsxFWRuleNames | ConvertTo-Json

	# Recherche des règles existantes 
	$rules = $nsx.getFirewallSectionRules($nsxFWSection.id)

	# Si les règles n'existent pas
	if($rules.Count -eq 0)
	{
		
		$logHistory.addLineAndDisplay(("-> Creating NSX Firewall section rules '{0}', '{1}', '{2}', '{3}'... " -f $ruleIn.name, $ruleComm.name, $ruleOut.name, $ruleDeny.name))

		# Création des règles 
		$rules = $nsx.addFirewallSectionRules($nsxFWSection.id, $ruleIn, $ruleComm, $ruleOut, $ruleDeny, $nsxNSGroup)

		$counters.inc('NSXFWSectionRulesCreated')
	}
	else # Les règles existent déjà 
	{
		$logHistory.addLineAndDisplay(("-> NSX Firewall section rules '{0}', '{1}', '{2}', '{3}' already exists!" -f  $ruleIn.name, $ruleComm.name, $ruleOut.name, $ruleDeny.name))

		# Incrément du compteur avec gestion des doublons
		$counters.inc('NSXFWSectionRulesExisting', $allRules)
	}

}


<#
-------------------------------------------------------------------------------------
	BUT : Prend une liste des BG et créé un mapping entre la valeur de la custom
			property donnée et le BG. On fait ceci pour avoir à éviter de parcourir
			N fois la liste de BG pour chercher s'il existe. Là, on pourra accéder
			directement via la valeur de la custom property donc ça sera plus rapide.

	IN  : $bgList			-> La liste des BG pour laquelle créer le mapping
	IN  : $customPropName	-> Le nom de la custom property à chercher

	RET : Tableau associatif avec en clef la valeur de la custom property cherchée préfixée
			avec _ histoire d'avoir un caractère autorisé pour commencer le nom de la clef.
			Et en valeur, on trouve le BG.
#>
function createMappingBGList([Array]$bgList, [string]$customPropName)
{
	$mappingList = @{}

	$logHistory.addLineAndDisplay(("Creating mapping list for {0} Business Groups..." -f $bgList.count))
	# Parcours des BG
	ForEach($bg in $bgList)
	{
		# Récupération de la valeur de la customProperty
		$propValue = getBGCustomPropValue -bg $bg -customPropName $customPropName

		if($null -ne $propValue)
		{
			# Création d'un nom de clef pour qu'elle commence avec un caractères autorisé
			$key = "_{0}" -f $propValue

			$mappingList.$key = $bg
		}
	}

	return $mappingList
}


<#
-------------------------------------------------------------------------------------
	BUT : Renvoie le BG correspondant à la valeur de custom property passée

	IN  : $mappingList			-> La liste de mapping qui aura été générée par la
									fonction createMappingBGList
	IN  : $customPropValue		-> Valeur de la custom property pour laquelle on veut le BG

	RET : Le BG
			$null si pas trouvé
#>
function getBGFromMappingList([Hashtable]$mappingList, [string]$customPropValue)
{
	# Génération de la clef de recherche
	$key = "_{0}" -f $customPropValue

	# Si la clef existe, retour du résultat
	if($mappingList.Keys -contains $key)
	{
		return $mappingList.$key
	}
	return $null
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

# Objet pour sauvegarder/restaurer la progression du script en cas de plantage
$resumeOnFail = [ResumeOnFail]::new()

<# Pour lister les groupes AD qui existent afin de ne pas contrôler 1000x le même groupe. Cette variable est créée de manière global
pour pouvoir être accédée par la fonction checkIfADGroupsExists #>
$global:existingADGroups = @()

try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logName = 'vra-sync-BG-from-AD-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()
	$logHistory =[LogHistory]::new($logName, (Join-Path $PSScriptRoot "logs"), 30)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	# Petite info dans les logs.
	if($fullSync)
	{
		$logHistory.addLineAndDisplay("Doing a FULL sync with all AD groups...")
	}
	else
	{
		$logHistory.addLineAndDisplay( ("Taking only AD groups modified last {0} day(s)..." -f $global:AD_GROUP_MODIFIED_LAST_X_DAYS))
	}

	# Création de l'objet qui permettra de générer les noms des groupes AD et "groups"
	$nameGenerator = [NameGenerator]::new($targetEnv, $targetTenant)

	# Objet pour pouvoir envoyer des mails de notification
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)


	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()
	$counters.add('ADGroups', '# AD group processed')
	$counters.add('BGCreated', '# Business Group created')
	$counters.add('BGUpdated', '# Business Group updated')
	$counters.inc('BGExisting', '# Business Group already existing')
	$counters.add('BGNotCreated', '# Business Group not created (because of an error)')
	$counters.add('BGNotRenamed', '# Business Group not renamed')
	$counters.add('BGResumeSkipped', '# Business Group skipped because of resume')
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

	# Recherche de la custom prop pour faire la liste de mapping
	if($targetTenant -eq $global:VRA_TENANT__EPFL)
	{
		$customPropName = $global:VRA_CUSTOM_PROP_EPFL_UNIT_ID
	}
	elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
	{
		$customPropName = $global:VRA_CUSTOM_PROP_EPFL_SNOW_SVC_ID
	}
	# Création de la liste de mapping
	$customPropToExistingBGMapping = createMappingBGList -bgList $existingBGList -customPropName $customPropName

	$doneBGList = @()

	# Si on doit tenter de reprendre une exécution foirée ET qu'un fichier de progression existait, on charge son contenu
	if($resume)
	{
		$logHistory.addLineAndDisplay("Trying to resume from previous failed execution...")
		$progress = $resumeOnFail.load()
		if($null -ne $progress)
		{
			$doneBGList = $progress
			$logHistory.addLineAndDisplay(("Progress file found, using it! {0} BG already processed. Skipping to unprocessed (could take some time)..." -f $doneBGList.Count))
		}
		else
		{
			$logHistory.addLineAndDisplay("No progress file found :-(")
		}
	}
	
	$doneBGList = @()

	# Si on doit tenter de reprendre une exécution foirée ET qu'un fichier de progression existait, on charge son contenu
	if($resume)
	{
		$logHistory.addLineAndDisplay("Trying to resume from previous failed execution...")
		$progress = $resumeOnFail.load()
		if($null -ne $progress)
		{
			$doneBGList = $progress
			$logHistory.addLineAndDisplay(("Progress file found, using it! {0} BG already processed" -f $doneBGList.Count))
		}
		else
		{
			$logHistory.addLineAndDisplay("No progress file found :-(")
		}
	}

	<# Recherche des groupes pour lesquels il faudra créer des OUs
	 On prend tous les groupes de l'OU et on fait ensuite un filtre avec une expression régulière sur le nom. Au début, on prenait le début du nom du
	 groupe pour filtrer mais d'autres groupes avec des noms débutant de la même manière ont été ajoutés donc le filtre par expression régulière
	 a été nécessaire. #>
	$adGroupNameRegex = $nameGenerator.getADGroupNameRegEx("CSP_CONSUMER")
	
	# La liste des propriétés pouvant être récupérées via -Properties
	$adGroupList = Get-ADGroup -Filter ("Name -like '*'") -Server ad2.epfl.ch -SearchBase $nameGenerator.getADGroupsOUDN($true) -Properties Description,whenChanged | 
	Where-Object {$_.Name -match $adGroupNameRegex} 

	# Création de l'objet pour récupérer les informations sur les approval policies à créer pour les demandes de nouveaux éléments
	$newItems = [NewItems]::new("vra-new-items.json")

	# Création de l'objet pour gérer les 2nd day actions
	$secondDayActions = [SecondDayActions]::new()

	# On détermine s'il est nécessaire de mettre à jour les ACLs des dossiers contenant les ISO
	$forceACLsUpdateFile =  ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__FORCE_ISO_FOLDER_ACL_UPDATE))
	$forceACLsUpdate = (Test-path $forceACLsUpdateFile)

	# Calcul de la date dans le passé jusqu'à laquelle on peut prendre les groupes modifiés.
	$aMomentInThePast = (Get-Date).AddDays(-$global:AD_GROUP_MODIFIED_LAST_X_DAYS)

	# Ajout de l'adresse par défaut à laquelle envoyer les mails. 
	$capacityAlertMails = @($configGlobal.getConfigValue("mail", "capacityAlert"))

	# Parcours des groupes AD pour l'environnement/tenant donné
	$adGroupList | ForEach-Object {

		$counters.inc('ADGroups')

		# ----------------------------------------------------------------------------------
		# --------------------------------- Business Group
		# Si Tenant EPFL
		if($targetTenant -eq $global:VRA_TENANT__EPFL)
		{
			# Pour signifier à la fonction createOrUpdateBG qu'on n'est pas dans le tenant ITServices.
			$snowServiceId = ""

			# Eclatement de la description et du nom pour récupérer le informations
			$facultyID, $unitID = $nameGenerator.extractInfosFromADGroupName($_.Name)
			$faculty, $unit, $financeCenter = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

			# Initialisation des détails pour le générateur de noms
			$nameGenerator.initDetails(@{facultyName = $faculty
										 facultyID = $facultyID
										 unitName = $unit
										 unitID = $unitID
										 financeCenter = $financeCenter})

			# Création du nom/description du business group
			$bgDesc = $nameGenerator.getBGDescription()

			# Nom du préfix de machine
			$machinePrefixName = $nameGenerator.getVMMachinePrefix()

			# Custom properties du Buisness Group
			$bgCustomProperties = @{"$global:VRA_CUSTOM_PROP_EPFL_UNIT_ID" = $unitID
									"$global:VRA_CUSTOM_PROP_EPFL_BG_ID" = $unitID}
	
		}
		# Si Tenant ITServices
		elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
		{
			# Pour signifier à la fonction createOrUpdateBG qu'on n'est pas dans le tenant EPFL.
			$unitID = ""
			$financeCenter = ""

			# Eclatement de la description et du nom pour récupérer le informations 
			# Vu qu'on reçoit un tableau à un élément, on prend le premier (vu que les autres... n'existent pas)
			$serviceShortName = $nameGenerator.extractInfosFromADGroupName($_.Name)[0]
			$snowServiceId, $serviceLongName  = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

			# Initialisation des détails pour le générateur de noms
			$nameGenerator.initDetails(@{serviceShortName = $serviceShortName
				serviceName = $serviceLongName
				snowServiceId = $snowServiceId})

			# Création du nom/description du business group
			$bgDesc = $serviceLongName
			
			# Nom du préfix de machine
			# NOTE ! Il n'y a pas de préfix de machine pour les Business Group du tenant ITServices.
			$machinePrefixName = ""
			
			# Custom properties du Buisness Group
			$bgCustomProperties = @{"$global:VRA_CUSTOM_PROP_EPFL_SNOW_SVC_ID" = $snowServiceId
									"$global:VRA_CUSTOM_PROP_EPFL_BG_ID" = $snowServiceId}

		}# FIN Si Tenant ITServices

		# Récupération du nom du BG
		$bgName = $nameGenerator.getBGName()

		# Si on a déjà traité le BG
		if($doneBGList -contains $bgName)
		{
			$counters.inc('BGResumeSkipped')
			# passage au BG suivant
			return
		}
		
		#### Lorsque l'on arrive ici, c'est que l'on commence à exécuter le code pour les BG qui n'ont pas été "skipped" lors du 
		#### potentiel '-resume' que l'on a passé au script.

		# Pour repartir "propre" pour le groupe AD courant
		$secondDayActions.clearApprovalPolicyMapping()

		# Génération du nom du groupe avec le domaine
		$ADFullGroupName = $nameGenerator.getADGroupFQDN($_.Name)

		# On n'affiche que maintenant le groupe AD que l'on traite, comme ça on économise du temps d'affichage pour le passage de tous les
		# groupes qui ont potentiellement déjà été traités si on fait un "resume"
		$logHistory.addLineAndDisplay(("[{0}/{1}] Current AD group: {2}" -f $counters.get('ADGroups'), $adGroupList.Count, $_.Name))

		# Génération du nom et de la description de l'entitlement
		$entName, $entDesc = $nameGenerator.getBGEntNameAndDesc()

		# Groupes de sécurités AD pour les différents rôles du BG
		$managerGrpList = @($nameGenerator.getRoleADGroupName("CSP_SUBTENANT_MANAGER", $true))
		$supportGrpList = @($nameGenerator.getRoleADGroupName("CSP_SUPPORT", $true))
		# Pas besoin de "générer" le nom du groupe ici car on le connaît déjà vu qu'on est en train de parcourir les groupes AD
		# créés par le script "sync-ad-groups-from-ldap.ps1"
		$sharedGrpList  = @($ADFullGroupName)
		$userGrpList    = @($ADFullGroupName)

		# Ajout de l'adresse mail à laquelle envoyer les "capacity alerts" pour le BG. On prend le niveau 1 car c'est celui de EXHEB
		# NOTE : 15.02.2019 - Les approbations pour les ressources sont faites par admin IaaS (level 1), donc plus besoin d'info aux approbateurs level 2
		#$capacityAlertMails += $nameGenerator.getApproveGroupsEmail(1)
		
		# Nom de la policy d'approbation ainsi que du groupe d'approbateurs
		$itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($global:APPROVE_POLICY_TYPE__ITEM_REQ)
		$actionReqBaseApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($global:APPROVE_POLICY_TYPE__ACTION_REQ)

		# Tableau pour les approbateurs des différents niveaux
		$approverGroupAtDomainList = @()
		$level = 0
		# on fait une 
		While($true)
		{
			$level += 1
			$levelGroupInfos = $nameGenerator.getApproveADGroupName($level, $true)
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
		$nsxNSGroupName, $nsxNSGroupDesc = $nameGenerator.getSecurityGroupNameAndDesc($bgName)
		# Nom du security Tag
		$nsxSTName = $nameGenerator.getSecurityTagName()
		# Nom et description de la section de firewall
		$nsxFWSectionName, $nsxFWSectionDesc = $nameGenerator.getFirewallSectionNameAndDesc()
		# Nom de règles de firewall
		$nsxFWRuleNames = $nameGenerator.getFirewallRuleNames()


		# Si on ne doit pas faire une synchro complète,
		if(!$fullSync)
		{
			# Si le groupe a déjà été modifié
			# ET
			# Si la date de modification du groupe est plus vieille que le nombre de jour que l'on a défini,
			if(($null -ne $_.whenChanged) -and ([DateTime]::Parse($_.whenChanged.toString()) -lt $aMomentInThePast))
			{
				$logHistory.addLineAndDisplay(("--> Skipping group, modification date older than {0} day(s) ago ({1})" -f $global:AD_GROUP_MODIFIED_LAST_X_DAYS, $_.whenChanged))
				$doneBGList += $bgName
				$counters.inc('BGExisting')
				return
			}
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
		$bg = createOrUpdateBG -vra $vra -existingBGList $customPropToExistingBGMapping -bgUnitID $unitID -bgSnowSvcID $snowServiceId -bgName $bgName -bgDesc $bgDesc `
									-machinePrefixName $machinePrefixName -financeCenter $financeCenter -capacityAlertsEmail ($capacityAlertMails -join ",") -customProperties $bgCustomProperties

		# Si BG pas créé, on passe au suivant (la fonction de création a déjà enregistré les infos sur ce qui ne s'est pas bien passé)
		if($null -eq $bg)
		{
			# On note quand même le BG comme pas traité
			$doneBGList += $bgName
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
		# NOTE: Si on est sur le DEV, on a fait en sorte que $bgISOFolder soit vide ("") donc
		# on n'entrera jamais dans ce IF
		if(($bgISOFolder -ne "") -and (-not (Test-Path $bgISOFolder)))
		{
			$logHistory.addLineAndDisplay(("--> Creating ISO folder '{0}'..." -f $bgISOFolder))
			# On le créé
			$dummy = New-Item -Path $bgISOFolder -ItemType:Directory

			# Pour faire en sorte que les ACLs soient mises à jour.
			$ISOFolderCreated = $true

			# On attend 1 seconde que le dossier se créée bien car si on essaie trop rapidement d'y accéder, on ne va pas pouvoir
			# récuprer les ACL correctement...
			Start-sleep -Seconds 1
		} # FIN S'il faut créer un dossier pour les ISO et qu'il n'existe pas encore.

		
		# Si on a créé un dossier où qu'on doit mettre à jour les ACLs
		if($ISOFolderCreated -or $forceACLsUpdate)
		{
			$logHistory.addLineAndDisplay(("--> Applying ACLs on ISO folder '{0}'..." -f $bgISOFolder))
			# Récupération et modification des ACL pour ajouter les groupes AD qui sont pour le Role "Shared" dans le BG
			$acl = Get-Acl $bgISOFolder
			ForEach($sharedGrp in $sharedGrpList)
			{
				$logHistory.addLineAndDisplay(("---> Group '{0}'..." -f $sharedGrp))
				# On fait en sorte de créer le dossier sans donner les droits de création de sous-dossier à l'utilisateur, histoire qu'il ne puisse pas décompresser une ISO
				# NOTE: Si l'ACL existe déjà, elle sera écrasée avec la nouvelle qu'on a ici
				$ar = New-Object  system.security.accesscontrol.filesystemaccessrule($sharedGrp,  "CreateFiles, WriteExtendedAttributes, WriteAttributes, Delete, ReadAndExecute, Synchronize", "ContainerInherit,ObjectInherit",  "None", "Allow")
				$acl.SetAccessRule($ar)
			}
			Set-Acl $bgISOFolder $acl

			# Pour ne pas retomber dans la condition à la prochaine itération de la boucle
			$ISOFolderCreated = $false
		}



		# ----------------------------------------------------------------------------------
		# --------------------------------- NSX

		# Création du NSGroup si besoin 
		$nsxNSGroup = createNSGroupIfNotExists -nsx $nsx -nsxNSGroupName $nsxNSGroupName -nsxNSGroupDesc $nsxNSGroupDesc -nsxSecurityTag $nsxSTName

		# Création de la section de Firewall si besoin
		$nsxFWSection = createFirewallSectionIfNotExists -nsx $nsx  -nsxFWSectionName $nsxFWSectionName -nsxFWSectionDesc $nsxFWSectionDesc -nsxNSGroup $nsxNSGroup

		# Création des règles dans la section de firewall
		createFirewallSectionRulesIfNotExists -nsx $nsx -nsxFWSection $nsxFWSection -nsxNSGroup $nsxNSGroup -nsxFWRuleNames $nsxFWRuleNames

		# Verrouillage de la section de firewall (si elle ne l'est pas encore)
		$nsxFWSection = $nsx.lockFirewallSection($nsxFWSection.id)

		$doneBGList += $bg.name
		# On sauvegarde l'avancement dans le cas où on arrêterait le script au milieu manuellement
		$resumeOnFail.save($doneBGList)	

	}# Fin boucle de parcours des groupes AD pour l'environnement/tenant donnés

	$logHistory.addLineAndDisplay("Business Groups created from AD!")

	# ----------------------------------------------------------------------------------------------------------------------
	# ----------------------------------------------------------------------------------------------------------------------

	$logHistory.addLineAndDisplay("Cleaning 'old' Business Groups")
	
	# Recherche et parcours de la liste des BG commençant par le bon nom pour le tenant
	$vra.getBGList() | ForEach-Object {

		# Recherche si le BG est d'un des types donné
		$isBGOfType = isBGOfType -bg $_ -typeList @($global:VRA_BG_TYPE__SERVICE, $global:VRA_BG_TYPE__UNIT)

		# Si la custom property qui donne les infos n'a pas été trouvée
		if($null -eq $isBGOfType)
		{
			$notifications['bgWithoutCustomPropType'] += $bg.name
		}
		elseif($isBGOfType -and ($doneBGList -notcontains $_.name))
		{
			$logHistory.addLineAndDisplay(("-> Setting Business Group '{0}' as Ghost..." -f $_.name))
			$setAsGhost = setBGAsGhostIfNot -vra $vra -bg $_

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
	$recreatePoliciesFile = ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__RECREATE_APPROVAL_POLICIES))
	if(Test-Path -Path $recreatePoliciesFile)
	{
		Remove-Item -Path $recreatePoliciesFile
	}

	# Si on a dû mettre à jour les ACLs des dossiers, 
	if($forceACLsUpdate)
	{
		Remove-Item -Path $forceACLsUpdateFile
	}

	# Affichage des nombres d'appels aux fonctions des objets REST
	$vra.displayFuncCalls()
	$nsx.displayFuncCalls()

	# Si un fichier de progression existait, on le supprime
	$resumeOnFail.clean()

}
catch # Dans le cas d'une erreur dans le script
{
	# Sauvegarde de la progression en cas d'erreur
	$logHistory.addLineAndDisplay(("Saving progress for future resume ({0} BG processed)" -f $doneBGList.Count))
	$resumeOnFail.save($doneBGList)	

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