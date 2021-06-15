<#
USAGES:
	sync-bg-from-ad.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl|research [-fullSync] [-resume]
#>
<#
	BUT 		: Crée/met à jour les Projectes en fonction des groupes AD existant

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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ResumeOnFail.inc.ps1"))


# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRA8API.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vROAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NSXAPI.inc.ps1"))



# Chargement des fichiers de configuration
$configVra 		= [ConfigReader]::New("config-vra8.json")
$configGlobal 	= [ConfigReader]::New("config-global.json")
$configNSX 		= [ConfigReader]::New("config-nsx.json")
$configLdapAD 	= [ConfigReader]::New("config-ldap-ad.json")

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
	$filepath = (Join-Path $global:VRA_JSON_TEMPLATE_FOLDER $JSONFile)

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
function createApprovalPolicyIfNotExists([vRA8API]$vra, [string]$name, [string]$desc, [string]$approvalLevelJSON, [Array]$approverGroupAtDomainList, [string]$approvalPolicyJSON, [psobject]$additionnalReplace, [ref]$processedApprovalPoliciesIDs)
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
function create2ndDayActionApprovalPolicies([vRA8API]$vra, [SecondDayActions]$secondDayActions, [string]$baseName, [string]$desc, [Array]$approverGroupAtDomainList, [ref] $processedApprovalPoliciesIDs)
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
	BUT : Créé (si inexistant) ou met à jour un Project (si existant)

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $tenantName			-> Nom du tenant sur lequel on bosse
	IN  : $projectEPFLID		-> ID du Project défini par l'EPFL et pas vRA. Valable pour les Project qui sont sur tous les tenants
	IN  : $projectName			-> Nom du BG
	IN  : $projectDesc			-> Description du BG
	IN  : $machineNameTemplate	-> Template à utiliser pour la génération du nom des VM
	IN  : $financeCenter		-> Centre financier
	IN  : $adminGrpList			-> Liste des admins
	IN  : $userGrpList			-> Liste des utilisateurs
	
	RET : Objet représentant la Project
#>
function createOrUpdateProject([vRA8API]$vra, [string]$tenantName, [string]$projectEPFLID, [string]$projectName, [string]$projectDesc, [string]$machineNameTemplate, [string]$financeCenter, [Array]$adminGrpList, [Array]$userGrpList)
{

	$logHistory.addLineAndDisplay(("-> Handling Project with custom ID {0}..." -f $projectEPFLID))
	
	# Recherche du Project par son no identifiant (no d'unité, no de service Snow, etc... ).
	$project = $vra.getProjectByCustomId($projectEPFLID, $true)

	$projectType = switch($tenantName)
	{
		$global:VRA_TENANT__EPFL { [ProjectType]::Unit }
		$global:VRA_TENANT__ITSERVICES { [ProjectType]::Service }
		$global:VRA_TENANT__RESEARCH { [ProjectType]::Project }
		default {
			Throw ("Incorrect value given for tenant name ({0})" -f $tenantName)
		}
	}

	<# Si le Project n'existe pas, ce qui peut arriver dans les cas suivants :
		Tenant EPFL:
		- nouvelle unité (avec éventuellement nouvelle faculté)
		Tenant ITServices
		- nouveau service
	#>
	if($null -eq $project)
	{
		$customProperties = @{}

		$customProperties["$global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS"] 	 	= $global:VRA_PROJECT_STATUS__ALIVE
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_RES_MANAGE"] 			= $global:VRA_BG_RES_MANAGE__AUTO
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE"] = $global:VRA_BG_RES_MANAGE__AUTO
		$customProperties["$global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID"] 			= $projectEPFLID
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE"] 			= $projectType.toString()
		$customProperties["$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER"]= $financeCenter
		$customProperties["$global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME"] 	= $nameGenerator.getBillingEntityName()
		

		# Ajout aussi des informations sur le Tenant et le Project car les mettre ici, c'est le seul moyen que l'on pour récupérer cette information
		# pour la génération des mails personnalisée... 
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_TENANT_NAME"] = $tenantName
		$customProperties["$global:VRA_CUSTOM_PROP_VRA_PROJECT_NAME"] = $projectName
		
		
		# Vu qu'on a cherché le Project par son ID et qu'on n'a pas trouvé, on regarde quand même si un Project portant le nom de celui qu'on doit
		# créer n'existe pas déjà (si si, ça se peut #facepalm)
		$existingBg = $vra.getProject($projectName)
		if($null -ne $existingBg)
		{
			$existingProjectId = (getProjectCustomPropValue -project $existingBg -customPropName $global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID)
			$logHistory.addWarningAndDisplay(("-> Impossible to create new Project with name '{0}' (ID={1}) because another one already exists with this name (ID={2})" -f `
												$projectName, $projectEPFLID, $existingProjectId))

			$notifications.projectNameAlreadyTaken += ("Existing Project {0} ,ID={1}. New Project ID={1}" -f $projectName, $existingProjectId, $projectEPFLID)

			$counters.inc('projectNotCreated')
			# On sort et on renvoie $null pour qu'on n'aille pas plus loin dans le traitement de ce Project pour le moment.
			return $null
		}
		else # Le Nom est libre, on peut aller de l'avant
		{
			$logHistory.addLineAndDisplay(("-> Project '{0}' (ID={1}) doesn't exists, creating..." -f $projectName, $projectEPFLID))
			# Création du BG
			
			$zoneList = $vra.getCloudZoneList()
			$project = $vra.addProject($projectName, $projectDesc, $machineNameTemplate, $customProperties, $zoneList, $adminGrpList, $userGrpList)

			$counters.inc('projectCreated')
		}
		
	}
	# Si le Project existe,
	else
	{

		$logHistory.addLineAndDisplay(("-> Project '{0}' already exists" -f $project.Name))

		$projectUpdated = $false

		$counters.inc('projectExisting')
		# ==========================================================================================

		# Si le centre financier du Project a changé (ce qui peut arriver), on le met à jour
		if((getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER) -ne $financeCenter)
		{
			# Mise à jour
			$project = $vra.updateProjectCustomProperties($project, @{"$global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER" = $financeCenter})
			$projectUpdated = $true
		}

		# Si le nom de l'entité de facturation a changé (ce qui peut arriver), on la met à jour
		if((getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME) -ne $nameGenerator.getBillingEntityName())
		{
			# Mise à jour
			$project = $vra.updateProjectCustomProperties($project, @{"$global:VRA_CUSTOM_PROP_EPFL_BILLING_ENTITY_NAME" = $nameGenerator.getBillingEntityName()})
			$projectUpdated = $true
		}


		# ==========================================================================================

		# Si le nom du Project est incorrect, (par exemple si le nom de l'unité ou celle de la faculté a changé)
		# Note: Dans le cas du tenant ITServices, vu qu'on fait une recherche avec le nom, ce test ne retournera
		# 		jamais $true
		# OU
		# Si le Project est désactivé
		if(($project.name -ne $projectName) -or ($project.description -ne $projectDesc) -or (!(isProjectAlive -project $project)))
		{
			$logHistory.addLineAndDisplay(("-> Project '{0}' has changed" -f $project.name))

			# S'il y a eu changement de nom,
			if($project.name -ne $projectName)
			{
				$logHistory.addLineAndDisplay(("-> Renaming Project '{0}' to '{1}'" -f $project.name, $projectName))

				<# On commence par regarder s'il n'y aurait pas par hasard déjà un Project avec le nouveau nom.
				 Ceci peut arriver si on supprime une unité/service IT et qu'on change le nom d'un autre en même temps pour reprendre le nom de 
				 ce qui a été supprimé. Etant donné que les Project passent en "ghost" sans être renommé dans le cas où ils doivent être supprimés, 
				 il y a toujours conflit de noms
				#>
				if($null -ne $vra.getBG($projectName)) 
				{
					$logHistory.addWarningAndDisplay(("-> Impossible to rename Project '{0}' to '{1}'. A Project with the new name already exists" -f $project.name, $projectName))
					$notifications.projectNameDuplicate += ("{0} &gt;&gt; {1}" -f $project.name, $projectName)
					$counters.inc('projectNotRenamed')

					# On sort et on renvoie $null pour qu'on n'aille pas plus loin dans le traitement de ce Project pour le moment.
					return $null
				}
				
				# Recherche du nom actuel du dossier où se trouvent les ISO du BG
				$projectISOFolderCurrent = $nameGenerator.getNASPrivateISOPath($project.name)
				# Recherche du nouveau nom du dossier où devront se trouver les ISO
				$projectISOFolderNew = $nameGenerator.getNASPrivateISOPath($projectName)

				$logHistory.addLineAndDisplay(("-> Renaming ISO folder for BG: '{0}' to '{1}'" -f $projectISOFolderCurrent, $projectISOFolderNew))
				
				try 
				{
					<# Renommage du dossier en mode "force". Aucune idée de savoir quel est le comportement dans le cas où une ISO est montée...
					Mais la probabilité qu'une unité soit renommée est déjà très faible, et je pense que c'est encore plus improbable qu'en 
					même temps une ISO soit montée dans une VM. 
					On met "-ErrorAction 'Stop'" pour s'assurer qu'en cas d'erreur on passe bien dans le "catch". Si on ne le fait pas, 
					ça va passer tout droit et simplement afficher l'erreur à la console. On n'aura pas de possibilité d'effectuer des 
					actions suite à l'erreur. #>
					Rename-Item -Path $projectISOFolderCurrent -NewName $projectISOFolderNew -Force -ErrorAction 'Stop'
				}
				catch 
				{
					<# Erreur de renommage, probablement car ISO montée. Dans ce cas-là, on fait en sorte de notifier les admins.
					Le dossier portant l'ancien nom va donc rester et un nouveau dossier sera créé automatiquement avec le nouveau nom à
					la fin du script du fait qu'il n'existe pas. #> 
					$logHistory.addErrorAndDisplay(("-> Error renaming folder. Error is : {0}" -f $_.Error.Message))
				
					# Ajout d'information dans les notifications pour faire en sorte que les admins soient informés par mail.
					$notifications.ISOFolderNotRenamed += ("{0} -> {1}" -f $projectISOFolderCurrent, $projectISOFolderNew)

					# On continue ensuite l'exécution normalement 
				}
				
				# Mise à jour de la custom property qui contient le nom du BG
				$project = $vra.updateProject($project, $projectName, $projectDesc, $machineNameTemplate, @{"$global:VRA_CUSTOM_PROP_VRA_PROJECT_NAME" = $projectName})

				$projectUpdated = $true
				$counters.inc('projectRenamed')

			}# Fin s'il y a eu changement de nom 

			$logHistory.addLineAndDisplay(("-> Updating and/or Reactivating Project '{0}' to '{1}'" -f $project.name, $projectName))

			# Si le Project était en Ghost, 
			if(!(isProjectAlive -project $project))
			{
				# on compte juste la chose
				$counters.inc('projectResurrected')
			}
			
			# Mise à jour des informations
			$project = $vra.updateProject($project, $projectName, $projectDesc, $machineNameTemplate, @{"$global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS" = $global:VRA_PROJECT_STATUS__ALIVE})

			$projectUpdated = $true
			
		}

		# Mise à jour du compteur si besoin
		if($projectUpdated)
		{
			$counters.inc('projectUpdated')
		}

	} # FIN SI le Project existe déjà

	return $project
	
}

<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistants) ou met à jour les roles d'un Project (si existants)

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $project				-> Objet contenant le Projet à mettre à jour
	IN  : $manageGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
								   managers. Si pas passé ou $null, on ne change rien dans la liste spécifiée
	IN  : $supportGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
								   personnes du support. Si pas passé ou $null, on ne change rien dans la liste spécifiée
	IN  : $userGrpList		-> (optionnel) Tableau avec la liste des adresses mail à mettre pour les
									"Share users". Si pas passé ou $null, on ne change rien dans la liste spécifiée
	RET : Rien
#>
function createOrUpdateProjectRoles([vRA8API]$vra, [PSCustomObject]$project, [Array]$adminGrpList, [Array]$supportGrpList, [Array]$userGrpList)
{

	$logHistory.addLineAndDisplay(("-> Updating roles for Project {0}..." -f $project.name))

	# S'il faut faire des modifs
	if($adminGrpList.count -gt 0)
	{
		$logHistory.addLineAndDisplay("--> Updating 'Group manager role'...")
		$vra.deleteProjectUserRoleContent($project, [vRAUserRole]::Administrators)
		
		$vra.addProjectUserRoleContent($project, [vRAUserRole]::Administrators, $adminGrpList)
	}

	# S'il faut faire des modifs
	if(($supportGrpList.Count -gt 0) -or ($userGrpList.count -gt 0))
	{
		$userAndSupportGrpList = $supportGrpList + $userGrpList

		$logHistory.addLineAndDisplay("--> Updating 'Support role'...")

		# Si le role est géré de manière manuelle pour le BG
		if((getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE) -eq $global:VRA_BG_RES_MANAGE__MAN)
		{
			$logHistory.addLineAndDisplay("---> Role manually managed, skipping it...")	
		}
		else # Le rôle est géré de manière automatique
		{
			$vra.deleteProjectUserRoleContent($project, [vRAUserRole]::Users)
			$vra.addProjectUserRoleContent($project, [vRAUserRole]::Users, $userAndSupportGrpList)
		}
	}


}


<#
-------------------------------------------------------------------------------------
	BUT : Créé (si inexistant) ou met à jour un Entitlement de Project (si existant).
			Ajoute aussi les content source avec le niveau de confidentialité donné

	IN  : $vra 					-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $project				-> Objet Project auquel l'entitlement est attaché
	IN  : $contentSourcePrivacy	-> Niveau de confidentialité des "content source"
	IN  : $entType				-> Type d'entitlement
	IN  : $nameGenerator		-> Objet faisant office de générateur de noms
	IN  : $deniedServices		-> Tableau avec les services à ne pas mettre pour le Projet.
									Le tableau contient une liste d'objet ayant les clefs suivantes:
									.svc	-> nom du service concerné
									.items 	-> tableau des items "denied". Si vide, c'est l'entier du
												service qui est "denied". Sinon, on ajoute spécifiquement
												les autres items du catalogue, à l'exception de ceux qui
												sont présents dans la liste
	IN  : $mandatoryItems		-> Tableau avec la liste des items de catalogue à ajouter obligatoirement
									à la liste des "Entitled items"	
	IN  : $onlyForGroups		-> Tableau avec la liste des noms des groupes auquels donner accès.
									Si vide, on ne limite à personne, open bar pour tous.

	RET : Objet contenant l'Entitlement

	-deniedServices $deniedVRASvc -mandatoryItems $mandatoryEntItemsList
#>
function createOrUpdateProjectEnt([vRA8API]$vra, [PSCustomObject]$project, [CatalogProjectPrivacy]$contentSourcePrivacy, [EntitlementType]$entType, [NameGenerator]$nameGenerator, [Array]$deniedServices, [Array]$mandatoryItems, [Array]$onlyForGroups)
{
	# Extraction des noms des services non autorisés
	$deniedServicesNames = @($deniedServices | Select-Object -ExpandProperty svc)

	#FIXME: Gérer les "mandatory catalog items" une fois qu'on saura les gérer un par un
	$logHistory.addLineAndDisplay(("Getting '{0}' Content Source list..." -f $contentSourcePrivacy))

	$contentSourceList = $vra.getContentSourcesList($contentSourcePrivacy)
	
	$logHistory.addLineAndDisplay(("{0} {1} Content Sources found" -f $contentSourceList.count, $contentSourcePrivacy))

	# Parcours des Content Sources trouvées
	ForEach($contentSource in $contentSourceList)
	{
		$logHistory.addLineAndDisplay(("> Processing Content Source '{0}'..." -f $contentSource.name))

		# S'il n'y a pas d'items dans la Content Source
		if($contentSource.itemsImported -eq 0)
		{
			$logHistory.addWarningAndDisplay(("> No item found in Content Source '{0}', skipping it" -f $contentSource.name))
			continue
		}

		#FIXME: Gérer aussi les Entitlement [EntitlementType]::Admin
		$entName = $contentSource.name
		$ent = $vra.getProjectEntitlement($project, $entName)

		# L'entitlement n'existe pas encore
		if($null -eq $ent)
		{
			$logHistory.addLineAndDisplay((">> Entilement '{0}' doesn't exists" -f $entName))

			# Si le Content Source n'est pas dans ceux qui ne sont pas autorisés pour le Projet
			if($deniedServicesNames -notcontains $contentSource.name)
			{
				$logHistory.addLineAndDisplay((">> Creating Entitlement '{0}' for Content Source '{1}'..." -f $entName, $contentSource.name))
				# Ajout de l'entitlement (appelé "content sharing" dans la GUI WEB)
				$ent = $vra.addEntitlement($contentSource, $project)
			}
			else # Le ContentSource n'est pas autorisé
			{
				$logHistory.addLineAndDisplay((">> Content Source '{0}' not allowed for Project '{1}', skipping Entitlement creation" -f $contentSource.name, $project.name))
			}
			
		}
		else # L'Entitlement existe déjà
		{
			$logHistory.addLineAndDisplay((">> Entitlement '{0}' already exists" -f $entName))

			# Si le content Source n'est pas autorisé pour le projet courant, on le supprime
			if($deniedServicesNames -contains $contentSource.name)
			{
				$logHistory.addLineAndDisplay((">> Content Source '{0}' not allowed for Project '{1}', removing Entitlement..." -f $contentSource.name, $projectName))
				$vra.deleteEntitlement($ent)
			}

		} # FIN SI l'entitlement existe déjà

	}# FIN BOUCLE de parcours des Content Sources trouvées

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
	$valToReplace = @{}
	$notificationMail.send("Error - No Reservation Template found for tenant!", "no-reservation-template-found-for-tenant", $valToReplace)
}


<#
-------------------------------------------------------------------------------------
	BUT : Met un Project en mode "ghost" dans le but qu'il soit effacé par la suite.
			On change aussi les droits d'accès

	IN  : $vra 				-> Objet de la classe vRAAPI permettant d'accéder aux API vRA
	IN  : $bg				-> Objet contenant le Project a effacer. Cet objet aura été renvoyé
					   			par un appel à une méthode de la classe vRAAPI
	IN  : $targetTenant		-> Tenant sur lequel on se trouve	
	
	RET : $true si mis en ghost
		  $false si pas mis en ghost
#>
function setProjectAsGhostIfNot([vRA8API]$vra, [PSObject]$project, [string]$targetTenant)
{
	
	# Si le Project est toujours actif
	if(isProjectAlive -project $project)
	{
		$notifications.bgSetAsGhost += $project.name
		
		# On marque le Project comme "Ghost"
		$vra.updateProjectCustomProperties($project, @{"$global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS" = $global:VRA_BG_STATUS__GHOST})
		
		$counters.inc('projectGhost')

		# ---- EPFL ----
		if($targetTenant -eq $global:VRA_TENANT__EPFL )
		{
			
			# Récupération du contenu du rôle des admins de faculté pour le BG
			$facAdmins = getProjectRoleContent -project $project -userRole ([vRAUserRole]::Administrators) 
			
			# Ajout des admins de la faculté de l'unité du Project afin qu'ils puissent gérer les élments du BG.
			createOrUpdateProjectRoles -vra $vra -project $project -sharedGrpList $facAdmins
		}
		# ITServices ou Research
		elseif( ($targetTenant -eq $global:VRA_TENANT__ITSERVICES) -or ($targetTenant -eq $global:VRA_TENANT__RESEARCH) )
		{
			# Ajout des admins
			createOrUpdateProjectRoles -vra $vra -project $project -sharedGrpList @($nameGenerator.getRoleADGroupName([UserRole]::Admin, $false))

		}
		else
		{
			Throw ("!!! Tenant '{0}' not supported in this script" -f $targetTenant)
		}
		
		$setAsGhost = $true

	} 
	else # Le Project est déjà en "ghost"
	{
		$setAsGhost = $false

		$logHistory.addLineAndDisplay("--> Already in 'ghost' status...")
	}

	return $setAsGhost
}



<#
-------------------------------------------------------------------------------------
	BUT : Permet de savoir si le Project passé est vivant ou voué à disparaitre

	IN  : $bg		-> Project dont on veut savoir s'il est vivant

	RET : Nom du groupe de sécurité à ajouter
#>
function isProjectAlive([PSCustomObject]$project)
{

	$projectStatus = getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS

	# Si la "Custom property" a été trouvée,
	if($null -ne $projectStatus)
	{
		return $projectStatus -eq $global:VRA_PROJECT_STATUS__ALIVE
	}

	<# Si on arrive ici, c'est qu'on n'a pas défini de clef (pour une raison inconnue) pour enregistrer le statut
	   On enregistre donc la chose et on dit que le Project est "vivant"
	#>
	$notifications.projectWithoutCustomPropStatus += $project.name
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
				# Project sans "custom property" permettant de définir le statut
				'projectWithoutCustomPropStatus'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.customProperty = $global:VRA_CUSTOM_PROP_VRA_PROJECT_STATUS
					$mailSubject = "Warning - Project without '{{customProperty}}' custom property"
					$templateName = "bg-without-custom-prop"
				}

				# ---------------------------------------
				# Project sans "custom property" permettant de définir le type
				'projectWithoutCustomPropType'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$valToReplace.customProperty = $global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE
					$mailSubject = "Warning - Project without '{{customProperty}}' custom property"
					$templateName = "bg-without-custom-prop"
				}

				# ---------------------------------------
				# Project marqué comme étant des 'ghost'
				'bgSetAsGhost'
				{
					$valToReplace.bgList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Info - Project marked as 'ghost'"
					$templateName = "bg-set-as-ghost"
				}

				# ---------------------------------------
				# Groupes AD soudainement devenus vides...
				'emptyADGroups'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Info - AD groups empty for Project"
					$templateName = "empty-ad-groups"
				}

				# ---------------------------------------
				# Groupes AD pour les rôles...
				'adGroupsNotFound'
				{
					$valToReplace.groupList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - AD groups not found for Project"
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
				
				# ---------------------------------------
				# Liste des éléments de catalogue "obligatoires" non trouvés
				'mandatoryItemsNotFound'
				{
					$valToReplace.itemList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Mandatory catalog items not found"
					$templateName = "mandatory-catalog-items-not-found"
				}

				# ---------------------------------------
				# Liste des actions "day-2" non trouvées
				'notFound2ndDayActions'
				{
					$valToReplace.actionList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Second day actions not found"
					$templateName = "day2-actions-not-found"
				}

				# ---------------------------------------
				# Pas possible de renommer un Project car le nouveau nom existe déjà
				'projectNameDuplicate'
				{
					$valToReplace.bgRenameList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Project cannot be renamed because of duplicate name"
					$templateName = "bg-rename-duplicate"
				}

				# ---------------------------------------
				# Pas possible de créer un Project car le nom existe déjà
				'projectNameAlreadyTaken'
				{
					$valToReplace.bgCreateList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Project cannot be created because of duplicate name"
					$templateName = "bg-create-duplicate"
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

	IN  : $ldap			-> Objet pour communiquer avec LDAP
	IN  : $groupList	-> Liste des groupes à contrôler

	RET : $true	-> Tous les groupes existent
		  $false -> au moins un groupe n'existe pas.
#>
function checkIfADGroupsExists([EPFLLDAP]$ldap, [System.Collections.ArrayList]$groupList)
{

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

				try
				{
					$dummy = Get-ADGroup $groupShort

					# Si on arrive jusqu'ici, c'est que le groupe existe, donc on l'enregistre pour ne plus avoir le à le contrôler par la suite 
					$global:existingADGroups += $groupName
				}
				catch
				{
					$logHistory.addWarningAndDisplay(("Security group '{0}' not found in Active Directory" -f $groupName))
					# Enregistrement du nom du groupe
					$notifications.adGroupsNotFound += $groupName
					$allOK = $false
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
function createNSGroupIfNotExists([NSXAPI]$nsx, [string]$nsxNSGroupName, [string]$nsxNSGroupDesc, [string]$nsxSecurityTag)
{

	$nsGroup = $nsx.getNSGroupByName($nsxNSGroupName, [NSXAPIEndPoint]::Manager)

	# Si le NSGroup n'existe pas,
	if($null -eq $nsGroup)
	{
		$logHistory.addLineAndDisplay(("-> Creating NSX NS Group '{0}'... " -f $nsxNSGroupName))

		# Création de celui-ci
		$nsGroup = $nsx.addNSGroup($nsxNSGroupName, $nsxNSGroupDesc, $nsxSecurityTag, [NSXNSGroupMemberType]::VirtualMachine, [NSXAPIEndpoint]::Manager)

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
function createFirewallSectionIfNotExists([NSXAPI]$nsx, [string]$nsxFWSectionName, [string]$nsxFWSectionDesc, [psobject]$nsxNSGroup)
{

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
	IN  : $nsxFWRuleNames	-> Tableau avec les noms des règles. Contient des tableaux associatifs,
								un pour chaque règle, avec les infos de celle-ci
#>
function createFirewallSectionRulesIfNotExists([NSXAPI]$nsx, [PSObject]$nsxFWSection, [PSObject]$nsxNSGroup, [Array]$nsxFWRuleNames)
{

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
	$rules = $nsx.getFirewallSectionRulesList($nsxFWSection.id)

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
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
									Programme principal
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
	-------------------------------------------------------------------------------------
#>

# Objet pour sauvegarder/restaurer la progression du script en cas de plantage
$resumeOnFail = [ResumeOnFail]::new($targetTenant)

<# Pour lister les groupes AD qui existent afin de ne pas contrôler 1000x le même groupe. Cette variable est créée de manière global
pour pouvoir être accédée par la fonction checkIfADGroupsExists #>
$global:existingADGroups = @()

try
{
	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logPath = @('vra', ('sync-BG-from-AD-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()))
	$logHistory =[LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

	# Petite info dans les logs.
	if($fullSync)
	{
		$logHistory.addWarningAndDisplay("Doing a FULL sync with all AD groups...")
	}
	else
	{
		$logHistory.addLineAndDisplay( ("Taking only AD groups modified last {0} day(s)..." -f $global:AD_GROUP_MODIFIED_LAST_X_DAYS))
	}

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
	$counters.add('ADGroups', '# AD group processed')
	$counters.add('projectCreated', '# Project created')
	$counters.add('projectUpdated', '# Project updated')
	$counters.inc('projectExisting', '# Project already existing')
	$counters.add('projectNotCreated', '# Project not created (because of an error)')
	$counters.add('projectNotRenamed', '# Project not renamed')
	$counters.add('ProjectResumeSkipped', '#Project skipped because of resume')
	$counters.add('projectGhost',	'# Project set as "ghost"')
	$counters.add('projectRenamed',	'# Project renamed')
	$counters.add('projectResurrected', '# Project set alive again')
	# Entitlements
	$counters.add('EntCreated', '# Entitlements created')
	$counters.add('EntUpdated', '# Entitlements updated')
	# Services
	$counters.add('EntServices', '# Existing Entitlements Services')
	$counters.add('EntServicesRemoved', '# Removed Entitlements Services (because denied)')
	$counters.add('EntServicesAdded', '# Entitlements Services added')
	$counters.add('EntServicesDenied', '# Entitlements Services denied')
	# Reservations
	$counters.add('ResCreated', '# Reservations created')
	$counters.add('ResUpdated', '# Reservations updated')
	$counters.add('ResDeleted', '# Reservations deleted')
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
	$notifications=@{projectWithoutCustomPropStatus = @()
					projectWithoutCustomPropType = @()
					bgSetAsGhost = @()
					projectNameDuplicate = @()
					projectNameAlreadyTaken = @()
					emptyADGroups = @()
					adGroupsNotFound = @()
					ISOFolderNotRenamed = @()
					mandatoryItemsNotFound = @()
					notFound2ndDayActions = @()
				}


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

	# Pour faire les recherches dans LDAP
	$ldap = [EPFLLDAP]::new($configLdapAd.getConfigValue(@("user")), $configLdapAd.getConfigValue(@("password")))						 

	$doneElementList = @()

	# Si on doit tenter de reprendre une exécution foirée ET qu'un fichier de progression existait, on charge son contenu
	if($resume)
	{
		$logHistory.addLineAndDisplay("Trying to resume from previous failed execution...")
		$progress = $resumeOnFail.load()
		if($null -ne $progress)
		{
			$doneElementList = $progress
			$logHistory.addLineAndDisplay(("Progress file found, using it! {0} Project already processed. Skipping to unprocessed (could take some time)..." -f $doneElementList.Count))
		}
		else
		{
			$logHistory.addLineAndDisplay("No progress file found :-(")
		}
	}


	<# Recherche des groupes pour lesquels il faudra créer des OUs
	 On prend tous les groupes de l'OU #>
	
	# La liste des propriétés pouvant être récupérées via -Properties
	$adGroupList = Get-ADGroup -Filter ("Name -like '*'") -Server ad2.epfl.ch -SearchBase $nameGenerator.getADGroupsOUDN($true, [ADSubOUType]::User) -Properties Description,whenChanged 

	# Création de l'objet pour récupérer les informations sur les approval policies à créer pour les demandes de nouveaux éléments
	# FIXME: 
	# $newItemsApprovalFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "new-items-approval.json"))
	# $newItemsApprovalList = loadFromCommentedJSON -jsonFile $newItemsApprovalFile

	# Création de l'objet pour gérer les 2nd day actions
	$secondDayActions = [SecondDayActions]::new([EntitlementType]::User)
	$secondDayActionsAdm = [SecondDayActions]::new([EntitlementType]::Admin)

	# On détermine s'il est nécessaire de mettre à jour les ACLs des dossiers contenant les ISO
	$forceACLsUpdateFile =  ([IO.Path]::Combine("$PSScriptRoot", $global:SCRIPT_ACTION_FILE__FORCE_ISO_FOLDER_ACL_UPDATE))
	$forceACLsUpdate = (Test-path $forceACLsUpdateFile)

	# Chargement des informations sur les unités qui doivent être facturées sur une adresse mail
	$mandatoryEntItemsFile = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "mandatory-entitled-items.json"))
	$mandatoryEntItemsList = loadFromCommentedJSON -jsonFile $mandatoryEntItemsFile

	# Calcul de la date dans le passé jusqu'à laquelle on peut prendre les groupes modifiés.
	$aMomentInThePast = (Get-Date).AddDays(-$global:AD_GROUP_MODIFIED_LAST_X_DAYS)


	# Parcours des groupes AD pour l'environnement/tenant donné
	$adGroupList | ForEach-Object {

		$counters.inc('ADGroups')

		# ----------------------------------------------------------------------------------
		# --------------------------------- Project
		
		# Initialisation du générateur de nom depuis les infos présentes dans le groupe AD
		$nameGenerator.initDetailsFromADGroup($_)
		
		$descInfos = $nameGenerator.extractInfosFromADGroupDesc($_.Description)

		# ---- EPFL ----
		if($targetTenant -eq $global:VRA_TENANT__EPFL )
		{
			
			# Eclatement de la description et du nom pour récupérer le informations
			$dummy, $projectEPFLID = $nameGenerator.extractInfosFromADGroupName($_.Name)
			
			$financeCenter = $descInfos.financeCenter
			$deniedVRASvc = $descInfos.deniedVRASvc

			# Création du nom/description du Project
			$projectDesc = $nameGenerator.getProjectDescription()

		}


		# ---- ITServices ----
		elseif($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
		{
			# Pas de centre financier pour le tenant ITServices
			$financeCenter = ""

			$deniedVRASvc = $descInfos.deniedVRASvc

			# Création du nom/description du Project
			$projectDesc = $descInfos.svcName
							
			# Custom properties du Project
			$projectEPFLID = $descInfos.svcId
		}


		# ---- Research ----
		elseif($targetTenant -eq $global:VRA_TENANT__RESEARCH)
		{
			$financeCenter = $descInfos.financeCenter

			# Création du nom/description du Project
			$projectDesc = $descInfos.projectAcronym
			
			# Eclatement de la description et du nom pour récupérer le informations 
			# Vu qu'on reçoit un tableau à un élément, on prend le premier (vu que les autres... n'existent pas)
			$projectEPFLID = $nameGenerator.extractInfosFromADGroupName($_.Name)[0]

			# Aucun service de défendu
			$deniedVRASvc = @()
		}

		else
		{
			Throw ("Tenant {0} not handled" -f $targetTenant)
		}
		
		# Récupération du nom du BG
		$projectName = $nameGenerator.getProjectName()
		# Template de nommage de VM
		$machineNameTemplate = $nameGenerator.getVMNameTemplate()

		# Si on a déjà traité le groupe AD
		if( ($doneElementList | Foreach-Object { $_.adGroup } ) -contains $_.name)
		{
			$counters.inc('ProjectResumeSkipped')
			# passage au Project suivant
			return
		}

		# Si on ne doit pas faire une synchro complète,
		if(!$fullSync)
		{
			# Si le groupe a déjà été modifié
			# ET
			# Si la date de modification du groupe est plus vieille que le nombre de jour que l'on a défini,
			if(($null -ne $_.whenChanged) -and ([DateTime]::Parse($_.whenChanged.toString()) -lt $aMomentInThePast))
			{
				$logHistory.addLineAndDisplay(("--> Skipping group, modification date older than {0} day(s) ago ({1})" -f $global:AD_GROUP_MODIFIED_LAST_X_DAYS, $_.whenChanged))
				$doneElementList += @{
					adGroup = $_.name
					projectName = $projectName
				}
				$counters.inc('projectExisting')
				return
			}
		}
		
		#### Lorsque l'on arrive ici, c'est que l'on commence à exécuter le code pour les Project qui n'ont pas été "skipped" lors du 
		#### potentiel '-resume' que l'on a passé au script.

		# Pour repartir "propre" pour le groupe AD courant
		# FIXME: voir si c'est encore utile
		$secondDayActions.clearApprovalPolicyMapping()

		# Génération du nom du groupe avec le domaine
		$ADFullGroupName = $nameGenerator.getADGroupFQDN($_.Name)

		# On n'affiche que maintenant le groupe AD que l'on traite, comme ça on économise du temps d'affichage pour le passage de tous les
		# groupes qui ont potentiellement déjà été traités si on fait un "resume"
		$logHistory.addLineAndDisplay(("[{0}/{1}] Current AD group: {2}" -f $counters.get('ADGroups'), $adGroupList.Count, $_.Name))

		# FIXME: Modifier le nécessaire
		# Groupes de sécurités AD pour les différents rôles du BG
		$adminGrpList = @($nameGenerator.getRoleADGroupName([UserRole]::Admin, $true))
		$supportGrpList = @($nameGenerator.getRoleADGroupName([UserRole]::Support, $true))
		# Pas besoin de "générer" le nom du groupe ici car on le connaît déjà vu qu'on est en train de parcourir les groupes AD
		# créés par le script "sync-ad-groups-from-ldap.ps1"
		$userGrpList  = @($ADFullGroupName, $supportGrpList)

		# Ajout de l'adresse mail à laquelle envoyer les "capacity alerts" pour le BG. On prend le niveau 1 car c'est celui de EXHEB
		# NOTE : 15.02.2019 - Les approbations pour les ressources sont faites par admin IaaS (level 1), donc plus besoin d'info aux approbateurs level 2
		#$capacityAlertMails += $nameGenerator.getApproveGroupsEmail(1)
		
		# Nom de la policy d'approbation ainsi que du groupe d'approbateurs

		# FIXME: Voir comment faire en temps voulu avec les approval policies
		# FIXME: APPROVAL POLICIES --->
		# $itemReqApprovalPolicyName, $itemReqApprovalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($global:APPROVE_POLICY_TYPE__ITEM_REQ)
		# $actionReqBaseApprovalPolicyName, $actionReqApprovalPolicyDesc = $nameGenerator.getApprovalPolicyNameAndDesc($global:APPROVE_POLICY_TYPE__ACTION_REQ)

		# # Tableau pour les approbateurs des différents niveaux
		# $approverGroupAtDomainList = @()
		# $level = 0
		# # on fait une boucle infine et on sortira quand on n'aura plus d'infos
		# While($true)
		# {
		# 	$level += 1
		# 	$levelGroupInfos = $nameGenerator.getApproveADGroupName($level, $true)
		# 	# Si on n'a plus de groupe pour le level courant, on sort
		# 	if($null -eq $levelGroupInfos)
		# 	{
		# 		break
		# 	}
		# 	$approverGroupAtDomainList += $levelGroupInfos.name
		# }

		# # Vu qu'il y aura des quotas pour les demandes sur le tenant EPFL, on utilise une policy du type "Event Subscription", ceci afin d'appeler un Workflow défini
		# # qui se chargera de contrôler le quota.
		# $newItemApprovalInfos = $newItemsApprovalList | Where-Object { $_.tenant -eq $targetTenant}
		
		# FIXME: <--- APPROVAL POLICIES 

		# -- NSX --
		# Nom et description du NSGroup
		$nsxNSGroupName, $nsxNSGroupDesc = $nameGenerator.getSecurityGroupNameAndDesc($projectName)
		# Nom du security Tag
		$nsxSTName = $nameGenerator.getSecurityTagName()
		# Nom et description de la section de firewall
		$nsxFWSectionName, $nsxFWSectionDesc = $nameGenerator.getFirewallSectionNameAndDesc()
		# Nom de règles de firewall
		$nsxFWRuleNames = $nameGenerator.getFirewallRuleNames()

		# Contrôle de l'existance des groupes. Si l'un d'eux n'existe pas dans AD, une exception est levée.
		if( ((checkIfADGroupsExists -ldap $ldap -groupList $adminGrpList) -eq $false) -or `
			((checkIfADGroupsExists -ldap $ldap -groupList $supportGrpList) -eq $false) -or `
			((checkIfADGroupsExists -ldap $ldap -groupList $userGrpList) -eq $false) -or `
			((checkIfADGroupsExists -ldap $ldap -groupList $approverGroupAtDomainList) -eq $false))
		{
			$logHistory.addWarningAndDisplay(("Security groups for Project ({0}) roles not found in Active Directory, skipping it !" -f $projectName))

			# On enregistre quand même le nom du Project, même si on n'a pas pu continuer son traitement. Si on ne fait pas ça et qu'il existe déjà,
			# il sera supprimé à la fin du script, chose qu'on ne désire pas.
			$doneElementList += @{
				adGroup = $_.name
				projectName = $projectName
			}

			# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			return
		}


		# Si le groupe est vide,
		if((Get-ADGroupMember $_.Name).Count -eq 0)
		{
			# On enregistre l'info pour notification
			$notifications.emptyADGroups += ("{0} ({1})" -f $_.Name, $projectName)
		}

		
		
		# ----------------------------------------------------------------------------------
		# --------------------------------- Project 

		# Création ou mise à jour du Project
		$project = createOrUpdateProject -vra $vra -projectEPFLID $projectEPFLID -tenantName $targetTenant -projectName $projectName -projectDesc $projectDesc `
									-machineNameTemplate $machineNameTemplate -financeCenter $financeCenter -adminGrpList $adminGrpList -userGrpList $userGrpList

		
		# Si Project pas créé, on passe au s	uivant (la fonction de création a déjà enregistré les infos sur ce qui ne s'est pas bien passé)
		if($null -eq $project)
		{
			# On note quand même le Project comme pas traité
			$doneElementList += @{
				adGroup = $_.name
				projectName = $projectName
			}
			# Note: Pour passer à l'élément suivant dans un ForEach-Object, il faut faire "return" et non pas "continue" comme dans une boucle standard
			return
		}

		# Si l'élément courant (unité, service, projet...) doit avoir une approval policy,
		if($descInfos.hasApproval)
		{
			# FIXME: GERER LES APPROVAL POLICIES
			# ----------------------------------------------------------------------------------
			# --------------------------------- Approval policies
			# Création des Approval policies pour les demandes de nouveaux éléments et les reconfigurations si celles-ci n'existent pas encore
			# $itemReqApprovalPolicy = createApprovalPolicyIfNotExists -vra $vra -name $itemReqApprovalPolicyName -desc $itemReqApprovalPolicyDesc `
			# 							-approvalLevelJSON $newItemApprovalInfos.approvalLevelJSON -approverGroupAtDomainList $approverGroupAtDomainList  `
			# 							-approvalPolicyJSON $newItemApprovalInfos.approvalPolicyJSON `
			# 							-additionnalReplace @{} -processedApprovalPoliciesIDs ([ref]$processedApprovalPoliciesIDs)

			# # Pour les approval policies des 2nd day actions, on récupère un tableau car il peut y avoir plusieurs policies
			# create2ndDayActionApprovalPolicies -vra $vra -baseName $actionReqBaseApprovalPolicyName -desc $actionReqApprovalPolicyDesc `
			# 							-approverGroupAtDomainList $approverGroupAtDomainList -secondDayActions $secondDayActions `
			# 							-processedApprovalPoliciesIDs ([ref]$processedApprovalPoliciesIDs)
		}
		else # Pas d'approval policy de définie
		{
			# $itemReqApprovalPolicy = $null
		}
		
		


		# ----------------------------------------------------------------------------------
		# --------------------------------- Entitlements


		# -- Public
		
		
		#FIXME: Gérer aussi les Entitlement "Private"

		#  TODO: COntinuer depuis ici


		# # Pour les utilisateurs (toutes les actions)
		$ent = createOrUpdateProjectEnt -vra $vra -project $project -contentSourcePrivacy ([CatalogProjectPrivacy]::Public) -entType ([EntitlementType]::User) -NameGenerator $nameGenerator `
									-onlyForGroups @() -deniedServices $deniedVRASvc -mandatoryItems $mandatoryEntItemsList
		# # Pour les admins (actions VIP)
		# $entAdm = createOrUpdateProjectEnt -vra $vra -bg $project -entName $entNameAdm -entDesc $entDescAdm -entType ([EntitlementType]::Admin) -NameGenerator $nameGenerator `
		# 							-onlyForGroups $adminGrpList.split('@')[0]
		
		# # ----------------------------------------------------------------------------------
		# # --------------------------------- Project Entitlement - 2nd day Actions
		# $logHistory.addLineAndDisplay("-> (prepare) Adding 2nd day Actions to Entitlement for users...")
		# $result = $vra.prepareEntActions($ent, $secondDayActions, $targetTenant)
		# $ent = $result.entitlement
		# # Mise à jour de la liste des actions non trouvées
		# $notifications.notFound2ndDayActions += $result.notFoundActions

		# $logHistory.addLineAndDisplay("-> (prepare) Adding 2nd day Actions to Entitlement for admins...")
		# $result = $vra.prepareEntActions($entAdm, $secondDayActionsAdm, $targetTenant)
		# $entAdm = $result.entitlement

		# # Mise à jour de la liste des actions non trouvées
		# $notifications.notFound2ndDayActions += $result.notFoundActions

		

		# ----------------------------------------------------------------------------------
		# --------------------------------- Dossier pour les ISO privées
		
		if($targetEnv -ne $global:TARGET_ENV__DEV)
		{
			# Recherche de l'UNC jusqu'au dossier où mettre les ISO pour le BG
			$bgISOFolder = $nameGenerator.getNASPrivateISOPath($projectName)

			$ISOFolderCreated = $false
			# Si on a effectivement un dossier où mettre les ISO et qu'il n'existe pas encore,
			# NOTE: Si on est sur le DEV, on a fait en sorte que $bgISOFolder soit vide ("") donc
			# on n'entrera jamais dans ce IF
			if(($bgISOFolder -ne "") -and (-not (Test-Path $bgISOFolder)))
			{
				$logHistory.addLineAndDisplay(("--> Creating ISO folder '{0}'..." -f $bgISOFolder))
				# On le créé
				New-Item -Path $bgISOFolder -ItemType:Directory | Out-Null

				$ISOFolderCreated = $true
				# On attend 1 seconde que le dossier se créée bien car si on essaie trop rapidement d'y accéder, on ne va pas pouvoir
				# récuprer les ACL correctement...
				Start-sleep -Seconds 1
			} # FIN S'il faut créer un dossier pour les ISO et qu'il n'existe pas encore.


			# Si on a créé un dossier 
			# OU 
			# qu'on doit mettre à jour les ACLs
			# OU
			# que c'est un Project avec le groupe de support qui est managé
			if($ISOFolderCreated -or $forceACLsUpdate -or `
				(getProjectCustomPropValue -project $project -customPropName $global:VRA_CUSTOM_PROP_VRA_BG_ROLE_SUPPORT_MANAGE) -ne $global:VRA_BG_RES_MANAGE__AUTO)
			{
				$logHistory.addLineAndDisplay(("--> Preparing ACLs for ISO folder '{0}'..." -f $bgISOFolder))
				# Récupération et modification des ACL pour ajouter les groupes AD qui sont pour le Role "Shared" dans le BG
				$acl = Get-Acl $bgISOFolder
		
				# On détermine qui a accès. Par défaut, tous les utilisateurs du BG
				$grantsToGroups = $userGrpList
								
				# Extraction des noms des groupes présents dans les ACLs du dossier, seulement ceux qui ne sont pas (et on les met au format <item>@intranet.epfl.ch)
				$aclGroups = @($acl.Access | Where-Object { !$_.IsInherited } | ForEach-Object { "{0}@intranet.epfl.ch" -f $_.IdentityReference.Value.Split('\')[1]} )
		
				<# Note:
					On pourrait simplement virer toutes les ACLs et les réappliquer mais dans le cas éventuel où une entrée aurait été modifiée 
					(par exemple avec un peu plus de droits, vu que nécessaire depuis OSX), elle serait supprimée et recréée "faux". Donc là, 
					on ne nettoie que ce qui ne devrait plus être là en fait.
				#>
		
				# On détermine ce qui doit être ajouté ou supprimé
				$diff = Compare-Object -ReferenceObject $grantsToGroups -DifferenceObject $aclGroups
		
				# Si on a des différences entre ce qui est appliqué comme ACL et ce qui devrait être appliqué
				if($null -ne $diff)
				{
					# Parcours de ce qui doit être supprimé
					ForEach($toRemove in ($diff | Where-Object { $_.SideIndicator -eq "=>"} | Select-Object -ExpandProperty InputObject ))
					{
						$logHistory.addLineAndDisplay(("---> Removing incorrect Group/User '{0}'..." -f $toRemove))
						$acl.RemoveAccessRule( ($acl.Access | Where-Object { !$_.IsInherited -and $_.IdentityReference -like ('*\{0}' -f $toRemove)}) )
					}
		
					# Parcours de ce qui doit être ajouté
					ForEach($toAdd in ($diff | Where-Object { $_.SideIndicator -eq "<="} | Select-Object -ExpandProperty InputObject))
					{
						$logHistory.addLineAndDisplay(("---> Adding Group/User '{0}'..." -f $toAdd))
						# On fait en sorte de créer le dossier sans donner les droits de création de sous-dossier à l'utilisateur, histoire qu'il ne puisse pas décompresser une ISO
						$ar = New-Object  system.security.accesscontrol.filesystemaccessrule($toAdd,  "CreateFiles, WriteExtendedAttributes, WriteAttributes, Delete, ReadAndExecute, Synchronize", "ContainerInherit,ObjectInherit",  "None", "Allow")
						$acl.SetAccessRule($ar)
					}
		
					$logHistory.addLineAndDisplay(("--> Applying ACLs on ISO folder '{0}'..." -f $bgISOFolder))
					Set-Acl $bgISOFolder $acl
				}
				else # Les ACLs sont à jour
				{
					$logHistory.addLineAndDisplay(("--> ACLs on ISO folder '{0}' is up-to-date" -f $bgISOFolder))
				}

			}
			else # Si on n'a pas besoin de mettre à jour les ACLs
			{
				$logHistory.addLineAndDisplay(("--> No need to update ACLs on ISO folder '{0}'" -f $bgISOFolder))
			}
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

		$doneElementList += @{
			adGroup = $_.name
			projectName = $projectName
		}
		# On sauvegarde l'avancement dans le cas où on arrêterait le script au milieu manuellement
		$resumeOnFail.save($doneElementList)	

	}# Fin boucle de parcours des groupes AD pour l'environnement/tenant donnés

	$logHistory.addLineAndDisplay("Projects created from AD!")

	# ----------------------------------------------------------------------------------------------------------------------
	# ----------------------------------------------------------------------------------------------------------------------

	$logHistory.addLineAndDisplay("Cleaning 'old' Projects")
	
	# # Extraction de la liste des ID "custom" des éléments qui ont été traités. Cela sera donc les SVCxxxx ou ID d'unité suivant le tenant)
	$doneProjectidList = ($doneElementList | ForEach-Object { ($nameGenerator.extractInfosFromADGroupName($_.adGroup))[-1] } )

	# Recherche et parcours de la liste des Project commençant par le bon nom pour le tenant
	$vra.getProjectList() | ForEach-Object {

		# Recherche si le Project est d'un des types donné, pour ne pas virer des Project "admins"
		$isProjectOfType = isProjectOfType -project $_ -typeList @([ProjectType]::Service, [ProjectType]::Unit, [ProjectType]::Project)

		# Si la custom property qui donne les infos n'a pas été trouvée
		if($null -eq $isProjectOfType)
		{
			$notifications.projectWithoutCustomPropType += $_.name
			$logHistory.addLineAndDisplay(("-> Custom Property '{0}' not found in Project '{1}'..." -f $global:VRA_CUSTOM_PROP_VRA_PROJECT_TYPE, $_.name))
		}
		else # On a les infos sur le type de BG
		{
			$projectId = (getProjectCustomPropValue -project $_ -customPropName $global:VRA_CUSTOM_PROP_EPFL_PROJECT_ID)
			# Si on n'a pas trouvé de groupe AD qui correspondait au BG, on peut le mettre en "ghost"
			if(($null -ne $projectId) -and  ($doneProjectidList -notcontains $projectId))
			{
				$logHistory.addLineAndDisplay(("-> Setting Project '{0}' as Ghost..." -f $_.name))
				setProjectAsGhostIfNot -vra $vra -project $_ -targetTenant $targetTenant | Out-Null
			}

		}# FIN SI la custom property avec le type du Projet a été trouvée

	}# FIN BOUCLE de parcours des projets qui sont dans vRA


	# Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -targetTenant $targetTenant

	$logHistory.addLineAndDisplay("Done")

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
	$logHistory.addLineAndDisplay($vra.getFuncCallsDisplay("vRA # func calls"))
	$logHistory.addLineAndDisplay($nsx.getFuncCallsDisplay("NSX # func calls"))
	

	# Si un fichier de progression existait, on le supprime
	$resumeOnFail.clean()

}
catch # Dans le cas d'une erreur dans le script
{
	# Sauvegarde de la progression en cas d'erreur
	$logHistory.addLineAndDisplay(("Saving progress for future resume ({0} Project processed)" -f $doneElementList.Count))
	$resumeOnFail.save($doneElementList)	

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