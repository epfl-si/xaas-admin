﻿<#
USAGES:
    xaas-billing.ps1  -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action generatePDF -service <service> [-limitToFile <file>] [-sendToCopernic]
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
    

#>
param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$service, 
      [string]$limitToFile,
      [switch]$sendToCopernic)


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
$configBilling = [ConfigReader]::New("config-billing.json")

# Constantes
$global:BILLING_TEMP_FOLDER = ([IO.Path]::Combine("$PSScriptRoot", "billing"))
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

        $replaceWith = $valToReplace.Item($search)

        # Si on a des retours à la ligne dans la valeur à remplacer
        if($replaceWith -like "*`n*")
        {
            # On met le tout dans des paragraphes pour que le HTML soit généré correctement
            $replaceWith = "<p>{0}</p>" -f ($replaceWith -replace "`n", "</p><p>")
        }

        $str = $str -replace  $strToSearch, $replaceWith
    }
    return $str
}




<#
	-------------------------------------------------------------------------------------
    BUT : Créé une facture depuis un fichier JSON fourni

    IN  : $sourceJSON   	-> Chemin jusqu'au fichier JSON
    IN  : $serviceInfos     -> Objet contenant les informations du service pour lequel faire la facturation
#>
function createBill([string]$sourceJSON, [PSObject]$serviceInfos)
{

    if(!(Test-Path -Path $sourceJSON))
    {
        Throw ("JSON file {0} doesn't exists" -f $sourceJSON)
    }

    $logHistory.addLine(("Processing JSON file {0}" -f $sourceJSON))

    # Chargement des données concernant les éléments à facturer
    # (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
    $billingInfos = Get-Content -path $sourceJSON -Encoding:UTF8 | ConvertFrom-Json

    
    # On commence par créer le code pour les items à facturer
    $billingItemListHtml = ""
    $quantityTot = 0
    $totalPrice = 0

    # Parcours des éléments à facturer
    ForEach($item in $billingInfos.items)
    {
        $billingItemReplacements = @{
            prestationCode = $serviceInfos.prestationCode
            description = $item.description
            monthYear = $item.monthYear
            quantity = $item.quantity
            unitPrice = $serviceInfos.unitPricePerMonthCHF
            # On coupe le prix à 2 décimales
            itemPrice = [System.Math]::Floor($item.quantity * $serviceInfos.unitPricePerMonthCHF * 100) / 100
        }

        # Mise à jour des totaux pour la facture
        $totalPrice += $billingItemReplacements.itemPrice
        $quantityTot += $billingItemReplacements.quantity

        # Création du HTML pour représenter l'item courant et ajout au code HTML représentant tous les items
        $billingItemListHtml += (replaceInString -str $billingItemTemplate -valToReplace $billingItemReplacements)
    }

    # Référence de la facture
    $billReference = ("{0}_{1}_{2}" -f $serviceInfos.serviceName, $curDateYYYYMMDD, $billingInfos.financeCenter) 

    # Elements à remplacer dans le document racine permettant de générer le HTML
    $billingDocumentReplace = @{

        docTitle = $serviceInfos.docTitle

        # Entête
        billingForType = $billingInfos.billingForType
        billingForElement = $billingInfos.billingForElement
        billReference = $billReference
        financeCenter = $billingInfos.financeCenter
        reportDate = $curDateGoodLooking 
        periodStartDate = $billingInfos.periodStartDate
        periodEndDate = $billingInfos.periodEndDate

        billingReference = $serviceInfos.billingReference
        billingFrom = $serviceInfos.billingFrom

        # Nom des colonnes
        colCode = $serviceInfos.itemColumns.colCode
        colDesc = $serviceInfos.itemColumns.colDesc
        colMonthYear = $serviceInfos.itemColumns.colMonthYear
        colConsumed = $serviceInfos.itemColumns.colConsumed
        colUnitPrice = $serviceInfos.itemColumns.colUnitPrice
        colTotPrice = $serviceInfos.itemColumns.colTotPrice

        # Liste des élément facturés 
        billingItems = $billingItemListHtml

        # Dernière ligne du tableau
        quantityTot = $quantityTot
        unitPricePerMonthCHF = $serviceInfos.unitPricePerMonthCHF
        totalPrice = $totalPrice
    }

    $billingTemplateHtml= replaceInString -str $billingTemplate -valToReplace $billingDocumentReplace 

    # Génération du nom du fichier PDF de sortie
    $PDFFilename = "{0}__{1}.pdf" -f ($billReference, [System.IO.Path]::GetFileNameWithoutExtension($sourceJSON))
    $targetPDFPath = ([IO.Path]::Combine($global:XAAS_BILLING_PDF_FOLDER, $PDFFilename))

    $logHistory.addLine(("> Generating PDF '{0}'" -f $targetPDFPath))
    ConvertHTMLtoPDF -Source $billingTemplateHtml -Destination $targetPDFPath -binFolder $global:BINARY_FOLDER -author $serviceInfos.pdfAuthor -landscape $true

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
    $logHistory = [LogHistory]::new('xaas-billing', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # Objet pour pouvoir envoyer des mails de notification
    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, "None", "None")
    
    # Templates pour la génération de factures
    $billingTemplate = Get-content -path $global:XAAS_BILLING_ROOT_DOCUMENT_TEMPLATE -Encoding UTF8
    $billingItemTemplate = Get-content -path $global:XAAS_BILLING_ITEM_DOCUMENT_TEMPLATE -Encoding UTF8

    # Génération de la date courante dans les formats nécessaires
    $curDateYYYYMMDD = Get-Date -Format "yyyyMMdd"
    $curDateGoodLooking = Get-Date -Format "dd.MM.yyyy"

    # Dossier dans lequel on pourra trouver les fichiers JSON
    $jsonFolder = ([IO.Path]::Combine($configBilling.getConfigValue($targetEnv, "jsonSourceRoot"), $targetTenant.ToLower(), $service)) 

    # Fichier JSON contenant les détails du service que l'on veut facturer
    $serviceInfosFile = ([IO.Path]::Combine("$PSScriptRoot", "data", "billing", $service.ToLower(), "service.json"))

    if(!(Test-Path -path $serviceInfosFile))
    {
        Throw ("Service file ({0}) for '{1}' not found. Please create it from 'config-sample.json' file." -f $serviceInfosFile, $service)
    }

    # Chargement des informations (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
    $serviceInfos = Get-Content -Path $serviceInfosFile -Encoding:UTF8 | ConvertFrom-Json

    # SI on doit traiter seulement un élément,
    if($null -ne $limitToFile)
    {
        $logHistory.addLine(("Execution limited to file {0}" -f $limitToFile))
        $sourceJSON = ([IO.Path]::Combine($jsonFolder, $limitToFile))
        createBill -sourceJSON $sourceJSON -serviceInfos $serviceInfos
    }
    else # On doit traiter tous les éléments
    {
        
    }



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