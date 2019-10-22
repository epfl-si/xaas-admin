<#
USAGES:
    xaas-backup-sync-vm-tags.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl 
#>
<#
    BUT 		: Script lancé par une tâche planifiée, afin de synchroniser, de manière unidirectionnelle,
                    les tags de backup des VM depuis vRA vers vSphere.

	DATE 	: Octobre 2019
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.
    
#>
param([string]$targetEnv, 
      [string]$targetTenant)


      

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configVra = [ConfigReader]::New("config-vra.json")
$configGlobal = [ConfigReader]::New("config-global.json")
$configXaaSBackup = [ConfigReader]::New("config-xaas-backup.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Récupérer ou initialiser le tag d'une VM dans vSphere
$VRA_CUSTOM_PROPERTY_BACKUP_TAG = "ch.epfl.xaas.backup.vm.tag"

# -------------------------------------------- FONCTIONS ---------------------------------------------------



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-backup-sync', (Join-Path $PSScriptRoot "logs"), 30)

    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))


    # -------------------------------------------------------------------------------------------

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))

    <# Connexion à l'API Rest de vSphere. On a besoin de cette connxion aussi (en plus de celle du dessus) parce que les opérations sur les tags ne fonctionnent
    pas via les CMDLet Get-TagAssignement et autre...  #>
    $logHistory.addLineAndDisplay("Connecting to vSphere...")
    $vsphereApi = [vSphereAPI]::new($configXaaSBackup.getConfigValue($targetEnv, "vSphere", "server"), 
                                    $configXaaSBackup.getConfigValue($targetEnv, "vSphere", "user"), 
                                    $configXaaSBackup.getConfigValue($targetEnv, "vSphere", "password"))

    # Création d'une connexion au serveur vRA pour accéder à ses API REST
	$logHistory.addLineAndDisplay("Connecting to vRA...")
	$vra = [vRAAPI]::new($configVra.getConfigValue($targetEnv, "server"), 
						 $targetTenant, 
						 $configVra.getConfigValue($targetEnv, $targetTenant, "user"), 
						 $configVra.getConfigValue($targetEnv, $targetTenant, "password"))


    # On commence par récupérer la liste des VM dans vRA

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant ""
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
}

$vra.disconnect()

# Déconnexion de l'API vSphere
$vsphereApi.disconnect()