<#
USAGES:
    xaas-billing.ps1  -targetEnv prod|test|dev -targetTenant test|itservices|epfl -service <service> [-sendToCopernic]
    
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
      [string]$service, 
      [switch]$sendToCopernic)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "MySQL.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Billing.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "BillingS3Bucket.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ITServices.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configBilling = [ConfigReader]::New("config-billing.json")

# Constantes
$global:BILLING_MIN_MOUNT_CHF = 5

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
        if($replaceWith -like "*\n*")
        {
            # On met le tout dans des paragraphes pour que le HTML soit généré correctement
            $replaceWith = "<p>{0}</p>" -f ($replaceWith -replace "\\n", "</p><p>")
        }

        $str = $str -replace  $strToSearch, $replaceWith
    }
    return $str
}

<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie la représentation MM.YYYY pour le mois et l'année passés
    
    IN  : $month            -> Mois de facturation
    IN  : $year             -> année de facturation

    RET : Représentation MM.YYYY de ce qui est passé
#>
function getItemDateMonthYear([int]$month, [int]$year)
{
    $monthStr = $month.toString()
    if($month -lt 10)
    {
        # Ajout du 0 initial pour la requête de recherche 
        $monthStr = "0{0}" -f $monthStr
    }
    return ("{0}.{1}" -f $monthStr, $year)
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

    # Pour accéder à la base de données
    $mysql = [MySQL]::new($configBilling.getConfigValue($targetEnv, "db", "host"), `
                          $configBilling.getConfigValue($targetEnv, "db", "dbName"), `
                          $configBilling.getConfigValue($targetEnv, "db", "user"), `
                          $configBilling.getConfigValue($targetEnv, "db", "password"), `
                          $global:BINARY_FOLDER, `
                          $configBilling.getConfigValue($targetEnv, "db", "port"))

    $ldap = [EPFLLDAP]::new()

    # Objet pour lire les informations sur le services IT
    $itServices = [ITServices]::new()

    # On prend la liste correspondant à l'environnement sur lequel on se trouve
    $itServicesList = $itServices.getServiceList($targetEnv)

    # Fichier JSON contenant les détails du service que l'on veut facturer    
    $serviceBillingInfosFile = ([IO.Path]::Combine("$PSScriptRoot", "data", "billing", $service.ToLower(), "service.json"))

    if(!(Test-Path -path $serviceBillingInfosFile))
    {
        Throw ("Service file ({0}) for '{1}' not found. Please create it from 'config-sample.json' file." -f $serviceBillingInfosFile, $service)
    }

    # Chargement des informations (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
    $serviceBillingInfos = Get-Content -Path $serviceBillingInfosFile -Encoding:UTF8 | ConvertFrom-Json


    # Création de l'objet pour faire les opérations pour le service donné
    $billingS3Bucket = [BillingS3Bucket]::new($mysql, $ldap, $itServicesList, $serviceBillingInfos, $targetEnv)


    ########################################################################
    ##             GENERATION DES DONNEES DE FACTURATION                  ##


    # Extraction des données pour les mettre dans la table où tout est formaté la même chose
    $billingS3Bucket.extractData(4, 2020)



    ########################################################################
    ##                   GENERATION DE LA FACTURE                         ##

    # Templates pour la génération de factures
    $billingTemplate = Get-content -path $global:XAAS_BILLING_ROOT_DOCUMENT_TEMPLATE -Encoding UTF8
    $billingItemTemplate = Get-content -path $global:XAAS_BILLING_ITEM_DOCUMENT_TEMPLATE -Encoding UTF8

    # Génération de la date courante dans les formats nécessaires
    $curDateYYYYMMDDHHMM = Get-Date -Format "yyyyMMddhhmm"
    $curDateGoodLooking = Get-Date -Format "dd.MM.yyyy hh:mm"
    
    $logHistory.addLineAndDisplay("Looking for entities...")

    # Recherche des entités à facturer
    $entityList = $billingS3Bucket.getEntityList()

    $logHistory.addLineAndDisplay(("{0} entities found" -f $entityList.count))
    
    # Parcours des entités
    ForEach($entity in $entityList)
    {
        $logHistory.addLineAndDisplay(("Processing entity {0} ({1})..." -f $entity.entityElement, $entity.entityType))

        ## 1. On commence par créer le code pour les items à facturer 

        $billingItemListHtml = ""
        $quantityTot = 0
        $totalPrice = 0
        
        # Les dates de début et de fin de facturation
        $billingBeginDate = $null
        $billingEndDate = $null

        $logHistory.addLineAndDisplay(("> Looking for items for service '{0}' ({1})" -f $service, $serviceBillingInfos.itemTypeInDB))

        # Recherche pour les éléments qu'il faut facturer et qui ne l'ont pas encore été
        $itemList = $billingS3Bucket.getEntityItemToBeBilledList($entity.entityId, $serviceBillingInfos.itemTypeInDB)

        $logHistory.addLineAndDisplay(("> {0} found = {1}" -f $serviceBillingInfos.itemTypeInDB, $itemList.count))

        # Parcours des éléments à facturer
        ForEach($item in $itemList)
        {
            $monthYear = (getItemDateMonthYear -month $item.itemMonth -year $item.itemYear)

            # Initialisation des dates pour comparaison
            if($null -eq $billingBeginDate)
            {
                $billingBeginDate = $billingEndDate = [datetime]::parseexact($monthYear, 'MM.yyyy', $null)
            }
            else # On a les dates donc on peut comparer.
            {
                # On essaie de trouver la plus grande et la plus petite date
                $tmpDate = [datetime]::parseexact($monthYear, 'MM.yyyy', $null)
                if($tmpDate -lt $billingBeginDate)
                {
                    $billingBeginDate = $tmpDate
                }
                elseif($tmpDate -gt $billingEndDate)
                {
                    $billingEndDate = $tmpDate
                }
            }


            $logHistory.addLineAndDisplay((">> Processing {0} '{1}'... " -f $serviceBillingInfos.itemTypeInDB, $item.itemName))
            $billingItemReplacements = @{
                prestationCode = $serviceBillingInfos.prestationCode
                description = $item.itemDesc
                monthYear = $monthYear
                quantity = $item.itemQuantity
                unitPrice = $serviceBillingInfos.unitPricePerMonthCHF
                # On coupe le prix à 2 décimales
                itemPrice = truncateToNbDecimal -number ([double]($item.itemQuantity) * $serviceBillingInfos.unitPricePerMonthCHF) -nbDecimals 2
            }

            # Mise à jour des totaux pour la facture
            $totalPrice += $billingItemReplacements.itemPrice
            $quantityTot += $billingItemReplacements.quantity

            # Création du HTML pour représenter l'item courant et ajout au code HTML représentant tous les items
            $billingItemListHtml += (replaceInString -str $billingItemTemplate -valToReplace $billingItemReplacements)
        }


        ## 2. On passe maintenant à la facture en elle-même

        
        # Si on n'a pas atteint le montant minimum pour émettre une facture,
        if($totalPrice -lt $global:BILLING_MIN_MOUNT_CHF)
        {
            $logHistory.addLineAndDisplay(("Entity '{0}' won't be billed this month, bill amount to small ({1} CHF)" -f $entity.entityElement, $totalPrice))
        }
        else
        {

            # Référence de la facture
            $billReference = ("{0}_{1}_{2}" -f $serviceBillingInfos.serviceName, $curDateYYYYMMDDHHMM, $entity.entityFinanceCenter) 

            # Elements à remplacer dans le document racine permettant de générer le HTML
            $billingDocumentReplace = @{

                docTitle = $serviceBillingInfos.docTitle

                # Entête
                billingForType = $entity.entityType
                billingForElement = $entity.entityElement
                billReference = $billReference
                financeCenter = $entity.entityFinanceCenter
                reportDate = $curDateGoodLooking 
                periodStartDate = Get-Date -Format "MM.yyyy" -Date $billingBeginDate
                periodEndDate = Get-Date -Format "MM.yyyy" -Date $billingEndDate

                billingReference = $serviceBillingInfos.billingReference
                billingFrom = $serviceBillingInfos.billingFrom

                # Nom des colonnes
                colCode = $serviceBillingInfos.itemColumns.colCode
                colDesc = $serviceBillingInfos.itemColumns.colDesc
                colMonthYear = $serviceBillingInfos.itemColumns.colMonthYear
                colConsumed = $serviceBillingInfos.itemColumns.colConsumed
                colUnitPrice = $serviceBillingInfos.itemColumns.colUnitPrice
                colTotPrice = $serviceBillingInfos.itemColumns.colTotPrice

                # Liste des élément facturés 
                billingItems = $billingItemListHtml

                # Dernière ligne du tableau
                quantityTot = $quantityTot
                unitPricePerMonthCHF = $serviceBillingInfos.unitPricePerMonthCHF
                totalPrice = $totalPrice
            }
            
            $billingTemplateHtml= replaceInString -str $billingTemplate -valToReplace $billingDocumentReplace 

            # Génération du nom du fichier PDF de sortie
            $PDFFilename = "{0}__{1}.pdf" -f ($billReference, $entity.entityElement)
            $targetPDFPath = ([IO.Path]::Combine($global:XAAS_BILLING_PDF_FOLDER, $PDFFilename))

            $logHistory.addLineAndDisplay(("> Generating PDF '{0}'" -f $targetPDFPath))
            ConvertHTMLtoPDF -Source $billingTemplateHtml -Destination $targetPDFPath -binFolder $global:BINARY_FOLDER -author $serviceBillingInfos.pdfAuthor -landscape $true    

            # On dit que tous les items de la facture ont été facturés
            $billingS3Bucket.setEntityItemTypeAsBilled($entity.entityId, $serviceBillingInfos.itemTypeInDB, $billReference)
            
        }

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
