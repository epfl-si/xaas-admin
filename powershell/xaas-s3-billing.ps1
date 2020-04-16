<#
USAGES:
    xaas-s3-billing.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -unitOrSvcID <unitOrSvcID> -friendlyName <friendlyName> [-linkedTo <linkedTo>] [-bucketTag <bucketTag>]
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet de créer une facture pour une unité
                    donnée pour tous les buckets S3 dont elle dispose. Toutes les informations pour créer la
                    facture sont passées en paramètre et aucune interaction avec le backend S3 n'est effectuée.

	DATE 	: Avril 2020
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
# param([string]$targetEnv, 
#       [string]$targetTenant, 
#       [string]$action, 
#       [string]$unitOrSvcID, 
#       [string]$friendlyName, 
#       [string]$linkedTo, 
#       [string]$bucketName, 
#       [string]$userType, 
#       [string]$enabled, 
#       [string]$bucketTag,       # Présent mais pas utilisé pour le moment et pas non plus dans la roadmap Scality 7.5
#       [switch]$status)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-s3-billing', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    #. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # Objet pour pouvoir envoyer des mails de notification
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "None", "None")
    



    $sourceHtml = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.html"))
    $targetPDF = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.pdf"))
    $binPath = ([IO.Path]::Combine("$PSScriptRoot", "bin"))

    $HTMLCode = Get-content -path $sourceHtml -Encoding UTF8

    ConvertHTMLtoPDF -Source $HTMLCode -Destination $targetPDF -binPath $binPath -author "EPFL SI SI-EXOP" 



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

