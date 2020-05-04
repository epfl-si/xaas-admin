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
    
    PREREQUIS :
    - Le module PSWritePDF est nécessaire (https://evotec.xyz/merging-splitting-and-creating-pdf-files-with-powershell/)
        Il peut être installé via la commande: Install-Module PSWritePDF -Force

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

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")

# Constantes
$global:BILLING_GRID_PDF_FILE = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "BillingGrid.pdf"))

<#
	-------------------------------------------------------------------------------------
    BUT : Prend le contenu de $valToReplace et cherche la chaine de caractère {{<key>}}
            dans $str puis la remplace par la valeur associée

	IN  : $str				-> Chaîne de caractères dans laquelle effectuer les remplacements
	IN  : $valToReplace     -> Dictionnaaire avec en clef la chaine de caractères
								à remplacer dans le code JSON (qui sera mise entre {{ et }} dans
								la chaîne de caractères). 
	
	RET : La chaine de caractères mise à jour
#>
function replaceInString([string]$str, [System.Collections.IDictionary] $valToReplace)
{
    # Parcours des remplacements à faire
    foreach($search in $valToReplace.Keys)
    {
        $strToSearch = "{{$($search)}}"

        $str = $str -replace  $strToSearch, $valToReplace.Item($search)
    }

    return $str
}


<#
	-------------------------------------------------------------------------------------
    BUT : Ajoute la grille tarifaire au fichier PDF généré

	IN  : $toPDFFile    -> Chemin jusqu'au fichier PDF auquel ajouter la grille tarifaire
#>
function addBillingGrid([string]$toPDFFile)
{
    # Création d'un fichier temporaire comme cible pour les fichiers "mergés"
    $tmpPDF = New-TemporaryFile 

    # Merge des 2 fichiers
    Merge-PDF -InputFile $toPDFFile, $global:BILLING_GRID_PDF_FILE -OutputFile $tmpPDF

    # Suppression du fichier PDF auquel on devait ajouter la grille et déplacement du fichier
    # temporaire car c'est lui qui contient le résultat maintenant.
    Remove-Item -Path $toPDFFile
    Move-Item -Path $tmpPDF -Destination $toPDFFile
    
}



# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-s3-billing', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    #. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # Objet pour pouvoir envoyer des mails de notification
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "None", "None")
    

    $billingDocumentPath = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "billing-document.html"))
    $billingDocument = Get-content -path $billingDocumentPath -Encoding UTF8

    $billingItemPath = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "billing-item.html"))
    $billingItemTemplate = Get-content -path $billingItemPath -Encoding UTF8


    # On commence par créer le code pour les items à facturer
    $billingItemList = ""

    $dummyItems = @(
        @{
            prestationCode = "123456"
            description = "Magnifique description"
            quantity = 11.53
            unitPrice = 20
            totalPrice = 230.6
        },
        @{
            prestationCode = "654321"
            description = "Wazaaaa "
            quantity = 8.25
            unitPrice = 20
            totalPrice = 165
        }
    )

    foreach($billingItem in $dummyItems)
    {
        $billingItemList += (replaceInString -str $billingItemTemplate -valToReplace $billingItem)
    }


    $billingDocumentReplace = @{
        financeCenter = "2468"
        billingItems = $billingItemList
    }

    $billingDocument = replaceInString -str $billingDocument -valToReplace $billingDocumentReplace

    $targetPDF = ([IO.Path]::Combine("$PSScriptRoot", "resources", "XaaS", "S3", "test.pdf"))
    $binPath = ([IO.Path]::Combine("$PSScriptRoot", "bin"))

    # $HTMLCode = Get-content -path $sourceHtml -Encoding UTF8

    ConvertHTMLtoPDF -Source $billingDocument -Destination $targetPDF -binPath $binPath -author "EPFL SI SI-EXOP" 

    addBillingGrid -toPDFFile $targetPDF

    # $output.results =

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

