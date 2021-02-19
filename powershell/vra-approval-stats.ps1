<#
USAGES:
	vra-approval-stats.ps1 -targetEnv prod|test|dev -targetTenant vsphere.local|itservices|epfl|research
#>
<#
	BUT 		: Extrait des statistiques (fichiers CSV) sur les temps d'approbation

	DATE 		: Février 2021
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
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")

$resultsFolder = ([IO.Path]::Combine("$PSScriptRoot", "results", "vra-approval-stats"))
$resultFile = ([IO.Path]::Combine("$resultsFolder", ("{0}-{1}-{2}.csv" -f $targetEnv, $targetTenant, (Get-Date -format "yyyy-MM-dd_HH-mm-ss") )) )

$valuesSeparator = ";"

try 
{

	# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$logPath = @('vra', ('approval-requests-stats-{0}-{1}' -f $targetEnv.ToLower(), $targetTenant.ToLower()))
	$logHistory =[LogHistory]::new($logPath, $global:LOGS_FOLDER, 30)

	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX -f $targetEnv, $targetTenant), $valToReplace)

	# On contrôle le prototype d'appel du script
	. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

	$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
	
	$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
						 $targetTenant, 
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
						 $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

	# Si le dossier de sortie n'existe pas,
	if(!(Test-Path $resultsFolder))
	{
		New-Item -ItemType Directory -Force -Path $resultsFolder | Out-null
	}

	# Ajout des colonnes dans le fichier Excel
	@("Request Date", "Approval Date", "Processing Time [sec]", "Approval Group", "Approver") -join $valuesSeparator | Out-File -Encoding:utf8 -FilePath $resultFile

	# Récupération de la liste des requêtes 
	$logHistory.addLineAndDisplay("Getting approved requests list...")
	$approvalList = $vra.getApprovalRequestList() | Where-Object { $_.status -eq "Approved"}
	$logHistory.addLineAndDisplay(("{0} approved requests found" -f $approvalList.count))

	ForEach($request in $approvalList)
	{
		$requestDate = ([DateTime]::Parse($request.createdDate))
		$approveDate = ([DateTime]::Parse($request.completedDate))
		@(
			$requestDate.ToString("yyyy-MM-dd HH:mm:ss"),
			$approveDate.ToString("yyyy-MM-dd HH:mm:ss"),
			[int]((New-TimeSpan -Start $requestDate -End $approveDate).TotalSeconds),
			$request.assignees.principalId,
			$request.completedBy
		) -join $valuesSeparator | Out-File -Encoding:utf8 -FilePath $resultFile -Append
	}

	Write-Host ("Result can be found in following CSV File: {0}" -f $resultFile)
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

if($null -ne $vra)
{
	$vra.disconnect()
}