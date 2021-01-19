<#
USAGES:
    xaas-billing.ps1  -targetEnv prod|test|dev -service <service> -action extractData
    xaas-billing.ps1  -targetEnv prod|test|dev -service <service> -action billing [-redoBill <billReferenc>] [-sendToCopernic] [-copernicRealMode]
    
#>
<#
    BUT 		: Script permettant de faire 2 choses :
                    1. Générer les données (utilisation) nécessaires à la facturation d'un service donné.
                        Cette action doit être entreprise à la fin d'un mois donné
                    2. Générer les factures pour un service donné et ajouter les informations dans Copernic
                        Cette action doit être entreprise au début du mois suivant. Même si on aurait pu le 
                        faire dernier jour du mois précédent le soir, c'est plus correct de faire ceci après
                        coup, le mois suivant. 

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
      [string]$service, 
      [string]$action,
      [string]$redoBill,
      [switch]$sendToCopernic,
      [switch]$copernicRealMode)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "CopernicAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))

. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "Billing.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "BillingS3Bucket.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "billing", "BillingNASVolume.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configBilling = [ConfigReader]::New("config-billing.json")
$configVra = [ConfigReader]::New("config-vra.json")

##### Constantes

# Montant minimmum à partir duquel on facture
$global:BILLING_MIN_MOUNT_CHF = 5
# Nombre de jours pendant lesquels on garde les fichiers PDF générés avant de les effacer.
$global:BILLING_KEEP_PDF_NB_DAYS = 60

# Actions possibles par le script
$global:ACTION_EXTRACT_DATA = "extractData"
$global:ACTION_BILLING      = "billing"

# Liste des tenants à facturer
$global:TENANTS_TO_BILL = @($global:VRA_TENANT__EPFL)

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

<#
-------------------------------------------------------------------------------------
	BUT : Parcours les différentes notification qui ont été ajoutées dans le tableau
		  durant l'exécution et effectue un traitement si besoin.

		  La liste des notifications possibles peut être trouvée dans la déclaration
		  de la variable $notifications plus bas dans le caode.

	IN  : $notifications-> Dictionnaire
    IN  : $targetEnv	-> Environnement courant
    IN  : $serviceName  -> Le nom du service pour lequel le script est en train de tourner
#>
function handleNotifications([System.Collections.IDictionary] $notifications, [string]$targetEnv, [string]$serviceName)
{

	# Parcours des catégories de notifications
	ForEach($notif in $notifications.Keys)
	{
		# S'il y a des notifications de ce type
		if($notifications.$notif.count -gt 0)
		{
			# Suppression des doublons 
			$uniqueNotifications = $notifications.$notif | Sort-Object| Get-Unique

			$valToReplace = @{
                serviceName = $serviceName
            }

			switch($notif)
			{
				# ---------------------------------------
				# Préfixes de machine non trouvés
				'copernicBillNotSent'
				{
					$valToReplace.entityList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Entity bill not sent to Copernic"
					$templateName = "copernic-bill-send-error"
				}

                'incorrectFinanceCenter'
                {
                    $valToReplace.entityList = ($uniqueNotifications -join "</li>`n<li>")
					$mailSubject = "Error - Incorrect finance center"
					$templateName = "billing-incorrect-finance-center"
                }

				default
				{
					# Passage à l'itération suivante de la boucle
					$logHistory.addWarningAndDisplay(("Notification '{0}' not handled in code !" -f $notif))
					continue
				}

			}# FIN EN FONCTION de la notif

            # Ajout du nom du service à la fin du sujet du mail pour pouvoir plus facilement retrouver les choses.
            $mailSubject = "{0} [Service: {1}]" -f $mailSubject, $serviceName

			# Si on arrive ici, c'est qu'on a un des 'cases' du 'switch' qui a été rencontré
			$notificationMail.send($mailSubject, $templateName, $valToReplace)

		} # FIN S'il y a des notifications pour la catégorie courante

	}# FIN BOUCLE de parcours des catégories de notifications
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
    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # Si on doit ajouter dans Copernic
    if($sendToCopernic)
    {
        if($copernicRealMode)
        {
            $logHistory.addLineAndDisplay("Data will be added in Copernic for REAL !!")
            $execMode = "REAL"
        }
        else
        {
            $logHistory.addLineAndDisplay("Data WON'T be added in Copernic because script is executed in SIMULATION MODE !!")
            $execMode = "SIMU"
        }
    }

    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT -f $targetEnv), $valToReplace)

    # Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()
    
    <# Pour enregistrer des notifications à faire par email. Celles-ci peuvent être informatives ou des erreurs à remonter
	aux administrateurs du service
	!! Attention !!
	A chaque fois qu'un élément est ajouté dans le IDictionnary ci-dessous, il faut aussi penser à compléter la
	fonction 'handleNotifications()'

	(cette liste sera accédée en variable globale même si c'est pas propre XD)
	#>
    $notifications=@{
        incorrectFinanceCenter = @()
        copernicBillNotSent = @()
    }

    # Pour accéder à la base de données
	$sqldb = [SQLDB]::new([DBType]::MSSQL,
                        $configVra.getConfigValue(@($targetEnv, "db", "host")),
                        $configVra.getConfigValue(@($targetEnv, "db", "user")),
                        $configVra.getConfigValue(@($targetEnv, "db", "password")),
                        $configVra.getConfigValue(@($targetEnv, "db", "port")),
                        $configVra.getConfigValue(@($targetEnv, "db", "dbName")))

    $vraTenantList = @{}

    # Créatino des connexions à vRA pour chaque tenant à facturer
    ForEach($tenant in $global:TENANTS_TO_BILL)
    {
        # Création d'une connexion au serveur vRA pour accéder à ses API REST
        $logHistory.addLineAndDisplay(("Connecting to vRA tenant {0}...") -f $tenant)
        $vraTenantList.$tenant = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")),
                                            $tenant, 
                                            $configVra.getConfigValue(@($targetEnv, "infra", $tenant, "user")),
                                            $configVra.getConfigValue(@($targetEnv, "infra", $tenant, "password")))
    }


    # Fichier JSON contenant les détails du service que l'on veut facturer    
    $serviceBillingInfosFile = ([IO.Path]::Combine("$PSScriptRoot", "data", "billing", $service.ToLower(), "service.json"))

    if(!(Test-Path -path $serviceBillingInfosFile))
    {
        Throw ("Service file ({0}) for '{1}' not found. Please create it from 'config-sample.json' file." -f $serviceBillingInfosFile, $service)
    }

    # Chargement des informations (On spécifie UTF8 sinon les caractères spéciaux ne sont pas bien interprétés)
    $serviceBillingInfos = loadFromCommentedJSON -jsonFile $serviceBillingInfosFile


    # Création de l'objet pour faire les opérations pour le service donné. On le créée d'une manière dynamique en utilisant la bonne classe
    # en fonction du type de service à facturer
    $expression = '$billingObject = [{0}]::new($vraTenantList, $sqldb, $serviceBillingInfos, $targetEnv)' -f $serviceBillingInfos.billingClassName
    Invoke-expression $expression

    # Pour accéder à Copernic
    $copernic = [CopernicAPI]::new($configBilling.getConfigValue(@($targetEnv, "copernic", "server")),
                                   $configBilling.getConfigValue(@($targetEnv, "copernic", "username")),
                                   $configBilling.getConfigValue(@($targetEnv, "copernic", "password")))

    # En fonction de l'action demandée
    switch($action)
    {
        ########################################################################
        ##             GENERATION DES DONNEES DE FACTURATION                  ##
        $global:ACTION_EXTRACT_DATA
        {
            # Ajout des différents compteurs
            $counters.add('itemEligibleToBeBilled', '# Items eligible to be billed')
            $counters.add('itemNonBillable', '# Items non billable (ITServices)')
            $counters.add('itemsZeroQte', '# Items with zero quantity')
            $counters.add('itemsNonBillableIncorrectData' , '# Items non billable because incorrect data')
            $counters.add('itemsNonBillableNotEnoughData' , '# Items non billable not enough data')

            $logHistory.addLineAndDisplay("Action => Data extraction")

            $month = [int](Get-Date -Format "MM")
            $year = [int](Get-Date -Format "yyyy")

            # Extraction des données pour les mettre dans la table où tout est formaté la même chose
            # On enregistre aussi le nombre d'éléments qui peuvent être facturés
            $itemEligibleToBeBilled, $itemNonBillable, $itemsZeroQte, $itemsNonBillableIncorrectData, $itemsNonBillableNotEnoughData  =  $billingObject.extractData($month, $year)

            $counters.set('itemEligibleToBeBilled',$itemEligibleToBeBilled)
            $counters.set('itemNonBillable', $itemNonBillable)
            $counters.set('itemsZeroQte', $itemsZeroQte)
            $counters.set('itemsNonBillableIncorrectData', $itemsNonBillableIncorrectData)
            $counters.set('itemsNonBillableNotEnoughData', $itemsNonBillableNotEnoughData)

        }

        ########################################################################
        ##                   GENERATION DES FACTURES                          ##
        $global:ACTION_BILLING
        {
            # Ajout des différents compteurs
            $counters.add('entityProcessed', '# Entity processed')
            $counters.add('billCanceled', '# Bill canceled')
            $counters.add('billDone', '# Entity Bill done')
            $counters.add('billSkippedToLow', '# Entity bill skipped (amount to low)')
            $counters.add('billSkippedNothing', '# Entity bill bill skipped (nothing to bill)')
            $counters.add('billSentToCopernic', '# Bill sent to Copernic')
            $counters.add('billCopernicError', '# Bill not sent to Copernic because of an error')
            $counters.add('PDFGenerated', '# PDF generated')
            $counters.add('PDFOldCleaned', '# Old PDF cleaned')
            $counters.add('billSentByEmail', '# Bill send by email')
            $counters.add('billIncorrectFinanceCenter', '# incorrect finance center')
            

            # SI on doit reset une facture pour l'émettre à nouveau
            if($redoBill -ne "")
            {
                $logHistory.addLineAndDisplay(("Canceling bill with reference {0}" -f $redoBill))
                $billingObject.cancelBill($redoBill)
                $counters.inc('billCanceled')
            }

            $logHistory.addLineAndDisplay("Action => Bill generation")
            # Templates pour la génération de factures
            $billingTemplate = Get-content -path $global:XAAS_BILLING_ROOT_DOCUMENT_TEMPLATE -Encoding UTF8
            $billingItemTemplate = Get-content -path $global:XAAS_BILLING_ITEM_DOCUMENT_TEMPLATE -Encoding UTF8

            # Génération de la date courante dans les formats nécessaires
            $curDateYYYYMMDDHHMM = Get-Date -Format "yyyyMMddHHmm"
            $curDateGoodLooking = Get-Date -Format "dd.MM.yyyy HH:mm"
            
            $logHistory.addLineAndDisplay("Looking for entities...")

            # Recherche des entités à facturer
            $entityList = $billingObject.getEntityList()

            $logHistory.addLineAndDisplay(("{0} entities found" -f $entityList.count))
            
            # Parcours des entités
            ForEach($entity in $entityList)
            {
                $logHistory.addLineAndDisplay(("Processing entity {0} ({1})..." -f $entity.entityElement, $entity.entityType))

                $counters.inc('entityProcessed')

                # Récupération des types d'items à facturer selon ce qui se trouve dans la DB
                $itemTypesToBillList = $billingObject.getEntityItemTypeToBeBilledList($entity.entityId) 

                ## 1. On commence par créer le code HTML pour les items à facturer 

                $billingItemListHtml = ""
                $quantityTot = 0
                $totalPrice = 0
                
                # Les dates de début et de fin de facturation
                $billingBeginDate = $null
                $billingEndDate = $null

                # Nombre total des items à facturer
                $totItems = 0
                $itemsLevels = @()

                # Pour enregistrer les types d'item que l'on aura facturé
                $billedItemTypes = @()

                # Parcours des types d'items à facturer selon la configuration
                ForEach($billedItemInfos in $serviceBillingInfos.billedItems)
                {

                    # Si on n'a pas d'infos de facturation pour le type d'entité courante, on ne va pas plus loin, on traite ça comme une erreur
                    if(!(objectPropertyExists -obj $billedItemInfos.entityTypesMonthlyPriceLevels -propertyName $entity.entityType))
                    {
                        Throw ("Error for item type '{0}' because no billing info found for entity '{1}'. Have a look at billing JSON configuration file for service '{2}'" -f $billedItemInfos.itemTypeInDB, $entity.entityType, $service)
                    }

                    $logHistory.addLineAndDisplay(("> Looking for items '{0}' in service '{1}'" -f $billedItemInfos.itemTypeInDB, $service))

                    # Recherche pour les éléments qu'il faut facturer et qui ne l'ont pas encore été
                    $itemList = $billingObject.getEntityItemToBeBilledList($entity.entityId, $billedItemInfos.itemTypeInDB)

                    $logHistory.addLineAndDisplay(("> {0} found = {1}" -f $billedItemInfos.itemTypeInDB, $itemList.count))

                    # Parcours des items à facturer
                    ForEach($item in $itemList)
                    {

                        # Si on n'a pas d'infos de niveau de facturation (niveau de prix) pour l'item courant, on passe au suivant
                        if(!(objectPropertyExists -obj $billedItemInfos.entityTypesMonthlyPriceLevels.($entity.entityType) -propertyName $item.itemPriceLevel))
                        {
                            Throw ("Error for item type '{0}' because price level '{1}' not found in JSON configuration file for service '{2}'" -f $item.itemType, $item.itemPriceLevel, $service)
                        }

                        # On enregistre les différents niveau de facturation qu'on traite
                        if($itemsLevels -notcontains $item.itemPriceLevel)
                        {
                            $itemsLevels += $item.itemPriceLevel
                        }

                        $totItems += 1

                        # Extraction du prix de l'item pour l'entity courante et on l'ajoute comme information à l'item, afin que ça puisse
                        # être réutilisé plus loin dans le code qui ajoute la facture dans Copernic.
                        # On récupère la valeur via "Select-Object" car le nom du niveau peut contenir des caractères non alphanumériques qui sont
                        # donc incompatibles avec un nom de propriété accessible de manière "standard" ($obj.<propertyName>)
                        $unitPricePerMonthCHF = $billedItemInfos.entityTypesMonthlyPriceLevels.($entity.entityType) | Select-Object -ExpandProperty $item.itemPriceLevel
                        $item | Add-member -NotePropertyName "unitPricePerMonthCHF" -NotePropertyValue $unitPricePerMonthCHF

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

                        $logHistory.addLineAndDisplay((">> Processing {0} '{1}'... " -f $billedItemInfos.itemTypeInDB, $item.itemName))

                        # On sauvegarde le no d'article pour pouvoir l'utiliser plus tard dans la facturation
                        $item | Add-Member -NotePropertyName "prestationCode" -NotePropertyValue $billedItemInfos.copernicPrestationCode.$targetEnv

                        $billingItemReplacements = @{
                            prestationCode = $item.prestationCode
                            description = $item.itemDesc
                            monthYear = $monthYear
                            quantity = $item.itemQuantity
                            unit = $item.itemUnit
                            unitPrice = $item.unitPricePerMonthCHF
                            # On coupe le prix à 2 décimales
                            itemPrice = truncateToNbDecimal -number ([double]($item.itemQuantity) * $item.unitPricePerMonthCHF) -nbDecimals 2
                        }

                        # Mise à jour des totaux pour la facture
                        $totalPrice += $billingItemReplacements.itemPrice
                        $quantityTot += $billingItemReplacements.quantity

                        # Création du HTML pour représenter l'item courant et ajout au code HTML représentant tous les items
                        $billingItemListHtml += (replaceInString -str $billingItemTemplate -valToReplace $billingItemReplacements)

                    }# FIN BOUCLE de parcours des items à facturer 

                    # On "enlève" le type d'item que l'on vient de facturer de la liste des types trouvés dans la DB
                    $itemTypesToBillList = $itemTypesToBillList | Where-Object { $_ -ne $billedItemInfos.itemTypeInDB }

                    # On enregistre le type d'item qu'on vient de traiter
                    $billedItemTypes += $billedItemInfos.itemTypeInDB

                }# FIN BOUCLE de parcours des types d'items à facturer


                # S'il y a dans la DB des types d'items pour lesquels on n'a pas d'information de facturation,
                if($itemTypesToBillList.Count -gt 0)
                {
                    Throw ("No billing information found for types ('{0}'). Add them in billing JSON configuration file." -f ($itemTypesToBillList -join "', '"))
                }

                ## 2. On passe maintenant à création de la facture de l'entité en elle-même

                # S'il y a des éléments à facturer
                if($totItems -gt 0)
                {
                    
                    # Si on n'a pas atteint le montant minimum pour émettre une facture pour l'entité courante,
                    if($totalPrice -lt $global:BILLING_MIN_MOUNT_CHF)
                    {
                        $logHistory.addLineAndDisplay(("Entity '{0}' won't be billed this month, bill amount to small ({1} CHF)" -f $entity.entityElement, $totalPrice))
                        $counters.inc('billSkippedToLow')
                    }
                    else # On a atteint le montant minimum pour facturer 
                    {

                        # Référence de la facture
                        $billReference = ("{0}_{1}_{2}" -f $serviceBillingInfos.serviceName, $curDateYYYYMMDDHHMM, $entity.entityFinanceCenter) 

                        $periodStartDate = Get-Date -Format "MM.yyyy" -Date $billingBeginDate
                        $periodEndDate = Get-Date -Format "MM.yyyy" -Date $billingEndDate

                        # Elements à remplacer dans le document racine permettant de générer le HTML
                        $billingDocumentReplace = @{

                            docTitle = $serviceBillingInfos.docTitle

                            # Entête
                            billingForType = $entity.entityType
                            billingForElement = $entity.entityElement
                            billReference = $billReference
                            financeCenter = $entity.entityFinanceCenter
                            reportDate = $curDateGoodLooking 
                            periodStartDate = $periodStartDate
                            periodEndDate = $periodEndDate

                            billingReference = $serviceBillingInfos.billingReference
                            billingFrom = $serviceBillingInfos.billingFrom

                            # Nom des colonnes
                            colCode = $serviceBillingInfos.itemColumns.colCode
                            colDesc = $serviceBillingInfos.itemColumns.colDesc
                            colMonthYear = $serviceBillingInfos.itemColumns.colMonthYear
                            colConsumed = $serviceBillingInfos.itemColumns.colConsumed
                            colUnit = $serviceBillingInfos.itemColumns.colUnit
                            colUnitPrice = $serviceBillingInfos.itemColumns.colUnitPrice
                            colTotPrice = $serviceBillingInfos.itemColumns.colTotPrice

                            # Liste des élément facturés 
                            billingItems = $billingItemListHtml

                            # Dernière ligne du tableau
                            totalPrice = $totalPrice
                        }

                        # S'il y a un seul type d'élément à facturer
                        # ET
                        # un seul niveau de facturation
                        if(($serviceBillingInfos.billedItems.Count -eq 1) -and ($itemsLevels.Count -eq 1))
                        {
                            # On peut mettre la valeur pour la quantité totale et le prix par mois car
                            # c'est une addition de même types d'éléments pour le premier et le même prix
                            # partout pour le 2e
                            $billingDocumentReplace.quantityTot = $quantityTot
                            $billingDocumentReplace.unitPricePerMonthCHF = $unitPricePerMonthCHF
                        }
                        else # Plusieurs types d'éléments à facturer
                        {
                            # On n'affiche pas de valeur pour les 2 cases car ça serait incohérent
                            $billingDocumentReplace.quantityTot = ""
                            $billingDocumentReplace.unitPricePerMonthCHF = ""
                        }

                        $billingTemplateHtml= replaceInString -str $billingTemplate -valToReplace $billingDocumentReplace 

                        # Génération du nom du fichier PDF de sortie
                        $PDFFilename = "{0}__{1}.pdf" -f ($billReference, $entity.entityElement)
                        $targetPDFPath = ([IO.Path]::Combine($global:XAAS_BILLING_PDF_FOLDER, $PDFFilename))

                        $logHistory.addLineAndDisplay(("> Generating PDF '{0}'" -f $targetPDFPath))
                        ConvertHTMLtoPDF -Source $billingTemplateHtml -Destination $targetPDFPath -binFolder $global:BINARY_FOLDER -author $serviceBillingInfos.pdfAuthor -landscape $serviceBillingInfos.landscapePDF    
                        $counters.inc('PDFGenerated')

                        # S'il faut envoyer à Copernic,
                        if($sendToCopernic)
                        {
                            $billDescription = "{0} - du {1} au {2}" -f $serviceBillingInfos.serviceName, $periodStartDate, $periodEndDate

                            # Si le centre financier est un "vrai" centre financier (et donc que des chiffres)
                            if($entity.entityFinanceCenter -match '[0-9]+')
                            {


                                # Facture de base
                                $PDFFiles = @( @{
                                    file = $targetPDFPath
                                    desc = $billDescription
                                } )

                                # Si on a une grille tarifaire pour le type d'entité que l'on est en train de traiter,
                                if(objectPropertyExists -obj $serviceBillingInfos.billingGrid -propertyName $entity.entityType)
                                {
                                    # Chemin jusqu'à la grille tarifaire et on regarde qu'elle existe bien.
                                    $billingGridPDFFile = ([IO.Path]::Combine($global:XAAS_BILLING_DATA_FOLDER, $service, $serviceBillingInfos.billingGrid.($entity.entityType)))
                                    if(!(Test-Path $billingGridPDFFile))
                                    {
                                        Throw ("Billing grid file not found for service ({0})" -f $billingGridPDFFile)
                                    }

                                    # On ajoute la grille tarifaire
                                    $PDFFiles += @{
                                        file = $billingGridPDFFile
                                        desc = "Grille tarifaire"
                                    }
                                }# FIN SI on a une grille tarifaire pour le type d'entité
            
                            
                                # Ajout de la facture dans Copernic avec le mode d'exécution spécifié
                                $result = $copernic.addBill($serviceBillingInfos, $targetEnv, $billReference, $billDescription, $PDFFiles, $entity, $itemList, $execMode)
                                
                                # Si une erreur a eu lieu
                                if($null -ne $result.error)
                                {
                                    # Enregistrement de l'erreur
                                    $errorId = "{0}_{1}" -f (Get-Date -Format "yyyyMMdd_hhmmss"), $entity.entityId
                                    $errorMsg = "Error adding Copernic Bill for entity '{0}'`nError message was: {1}" -f $entity.entityElement, $result.error
                                    $errorFolder = saveRESTError -category "billing" -errorId $errorId -errorMsg $errorMsg -jsonContent $copernic.getLastBodyJSON()
                                    $logHistory.addLineAndDisplay(("> Error sending bill to Copernic for entity ID (error: {0}). Details can be found in folder '{1}'" -f $result.error, $errorFolder))

                                    $counters.inc('billCopernicError')

                                    # Ajout du nécessaire pour les notifications
                                    $notifications.copernicBillNotSent += "{0} ({1}) - Error logs are on {2} in folder {3} " -f $entity.entityElement, $entity.entityType, $env:computername, $errorFolder
                                }
                                else # Pas d'erreur
                                {
                                    # Si on est en mode d'exéution réel et que la facture a bel et bien été envoyée dans Copernic 
                                    if($copernicRealMode)
                                    {
                                        $logHistory.addLineAndDisplay(("> Bill sent to Copernic (Doc number: {0}, bill ref: {1})" -f $result.docNumber, $billReference))

                                        # On dit que tous les items de la facture ont été facturés
                                        $billingObject.setEntityItemTypesAsBilled($entity.entityId, $billedItemTypes, $billReference)
                                    }
                                    else # On est en mode "simulation" donc pas d'envoi réel de facture
                                    {
                                        $logHistory.addLineAndDisplay("> Bill sent to Copernic in SIMULATION MODE without any error")
                                    }

                                    $logHistory.addLineAndDisplay(("> {0} items '{1}' set as billed for entity '{2}'" -f $itemList.count, ($billedItemTypes -join "', '"), $entity.entityElement))
                                    $counters.inc('billSentToCopernic')    

                                } # Fin si pas d'erreur
                            
                            }
                             # Le centre financier est une adresse mail EPFL
                            elseif($entity.entityFinanceCenter -match '.*?@epfl\.ch')
                            {
                                $logHistory.addLineAndDisplay(("> This bill has to ben sent at {0} mail address" -f $entity.entityFinanceCenter))

                                # Si on n'est pas en mode simulation,
                                if($copernicRealMode)
                                {
                                    $logHistory.addLineAndDisplay("> Sending mail...")
                                    $mailSubject = "vRA Billing - {0}" -f $billDescription
                                    $billingObject.sendBillByMail($entity.entityFinanceCenter, $targetPDFPath, $mailSubject, $periodStartDate, $periodEndDate)

                                    $counters.inc('billSentByEmail')  
                                }
                                else # On est en mode simulation
                                {
                                    $logHistory.addLineAndDisplay("> SIMULATION MODE.. nothing is sent!")
                                }

                            }
                            else # Le centre financier n'est pas géré
                            {
                                # On ajoute l'erreur pour que ça soit envoyé par email
                                # Le développeur est tout à fait conscient que si on arrive ici et qu'on ne peut pas faire de facturation, le fichier PDF
                                # aura malgré tout déjà été créé... ce n'est pas grave, y'a des choses pires dans la vie.
                                $logHistory.addLineAndDisplay(("> Incorrect finance center ({0}) for entity '{1}'" -f $entity.entityFinanceCenter, $entity.entityElement))
                                $notifications.incorrectFinanceCenter += ("Entity: {0} - Finance Center: {1}" -f $entity.entityElement, $entity.entityFinanceCenter)
                                $counters.inc('billIncorrectFinanceCenter')
                            }
                            
                        }# Fin s'il faut envoyer à Copernic
                        
                        $counters.inc('billDone')

                    }# FIN SI on a atteint le montant minimum pour facturer
                
                }
                else # Il n'y a aucun élément à facturer
                {
                    $logHistory.addLineAndDisplay(("Nothing left to bill for entity {0}" -f $entity.entityElement))
                    $counters.inc('billSkippedNothing')
                }

            }# FIN BOUCLE de parcours des entités

            $logHistory.addLineAndDisplay(("Cleaning PDF files older than {0} day(s)..." -f $global:BILLING_KEEP_PDF_NB_DAYS))
            # Suppression des fichiers PDF trop "vieux"
            ForEach($pdfFile in (Get-ChildItem -Path $global:XAAS_BILLING_PDF_FOLDER -Filter "*.pdf" | Where-Object {$_.CreationTime -lt (Get-Date).addDays(-$global:BILLING_KEEP_PDF_NB_DAYS)}))
            {
                Remove-Item $pdfFile.FullName -Force
                $logHistory.addLineAndDisplay(("> PDF file deleted: {0}" -f $pdfFile.FullName))
                $counters.inc('PDFOldCleaned')
            }

        } # FIN CASE action billing

    }# FIN SWITCH en fonction de l'action

    

    # Gestion des erreurs s'il y en a
	handleNotifications -notifications $notifications -targetEnv $targetEnv -serviceName $service

    # Résumé des actions entreprises
    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

    $sqldb.disconnect()

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
