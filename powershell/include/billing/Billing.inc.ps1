<#
   BUT : Classe permettant de récupérer des informations pour la facturation. On a 2 types d'éléments qui vont être
        géré par cette classe:
        - Entity --> l'entité pour laquelle on va faire la facturation. ça peut être une unité, un service ou un
                    projet. Les possibilités sont définies dans le type énuméré ci-dessous
        - Item --> élément à facturer pour un mois donné. Par exemple un bucket S3   

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2020

   Prérequis:
   Les fichiers suivants doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - SQLDB.inc.ps1
   - define.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>

class Billing
{
    hidden [SQLDB] $db
    hidden [string] $targetEnv
    hidden [PSObject] $serviceList
    hidden [EPFLLDAP] $ldap
    hidden [PSObject] $serviceBillingInfos
    hidden [Hashtable] $vraTenantList
    hidden [string] $vRODynamicTypeName 


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $vraTenantList        -> Hashtable avec des objets de la classe VRAAPI pour interroger vRA.
                                        Chaque objet a pour clef le nom du tenant et comme "contenu" le 
                                        nécessaire pour interroger le tenant
        IN  : $db                   -> Objet de la classe SQLDB permettant d'accéder aux données.
        IN  : $ldap                 -> Connexion au LDAP pour récupérer les infos sur les unités
        IN  : $serviceList          -> Objet avec la liste de services (chargé depuis le fichier JSON itservices.json)
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
                                        Ces informations se trouvent dans le fichier JSON "service.json" qui sont 
                                        dans le dossier data/billing/<service>/service.json
        IN  : $targetEnv            -> Nom de l'environnement sur lequel on est.
        IN  : $vRODynamicTypeName   -> Nom du type dynamique dans vRA

		RET : Instance de l'objet
	#>
    Billing([Hashtable]$vraTenantList, [SQLDB]$db, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv, [string]$vRODynamicTypeName)
    {
        $this.vraTenantList = $vraTenantList
        $this.db = $db
        $this.ldap = $ldap
        $this.serviceList = $serviceList
        $this.serviceBillingInfos = $serviceBillingInfos
        $this.targetEnv = $targetEnv
        $this.vRODynamicTypeName = $vRODynamicTypeName
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une entité ou $null si pas trouvé
        
        IN  : $entityId -> Id de l'entité

        RET : Objet avec les infos de l'entité 
            $null si pas trouvé
    #>
    hidden [PSObject] getEntity([int]$entityId)
    {
        $request = "SELECT * FROM BillingEntity WHERE entityId='{0}'" -f $entityId

        $entity = $this.db.execute($request)

        # On retourne le premier élément du tableau car c'est là que se trouve le résultat
        return $entity[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une entité ou $null si pas trouvé
        
        IN  : $type             -> Type de l'entité (du type énuméré défini plus haut).
        IN  : $element          -> Id d'unité, no de service ou no de fond de projet...

        RET : Objet avec les infos de l'entité 
            $null si pas trouvé
    #>
    hidden [PSObject] getEntity([BillingEntityType]$type, [string]$element)
    {
        $request = "SELECT * FROM BillingEntity WHERE entityType='{0}' AND entityElement='{1}'" -f $type, $element

        $entity = $this.db.execute($request)

        if($entity.count -eq 0)
        {
            return $null
        }
        # On retourne le premier élément du tableau car c'est là que se trouve le résultat
        return $entity[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute une entité et la met à jour si elle existe déjà
        
        IN  : $type             -> Type de l'entité (du type énuméré défini plus haut).
        IN  : $element          -> Id d'unité, no de service ou no de fond de projet...
        IN  : $financeCenter    -> No du centre financier auquel imputer la facture
                                    OU
                                    adresse mail à laquelle envoyer la facture

        RET : ID de l'entité
    #>
    hidden [int] addEntity([BillingEntityType]$type, [string]$element, [string]$financeCenter)
    {
        $entity = $this.getEntity($type, $element)

        # Si l'entité existe déjà dans la DB
        if($null -ne $entity)
        {
            # On commence par la mettre à jour (dans le doute)
            $this.updateEntity([int]$entity.entityId, $type, $element, $financeCenter)
            # Et on retourne son ID
            return [int]$entity.entityId
        }

        # L'entité n'existe pas, donc on l'ajoute 
        $request = "INSERT INTO BillingEntity (entityType, entityElement, entityFinanceCenter) VALUES ('{0}', '{1}', '{2}')" -f $type.toString(), $element, $financeCenter

        $this.db.execute($request) | Out-Null

        return [int] ($this.getEntity($type, $element)).entityId
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Mets à jour une entité
        
        IN  : $id               -> ID de l'entity
        IN  : $type             -> Type de l'entité (du type énuméré défini plus haut).
        IN  : $element          -> Id d'unité, no de service ou no de fond de projet...
        IN  : $financeCenter    -> No du centre financier auquel imputer la facture
                                    OU
                                    adresse mail à laquelle envoyer la facture
    #>
    hidden [void] updateEntity([int]$id, [BillingEntityType]$type, [string]$element, [string]$financeCenter)
    {
        # L'entité n'existe pas, donc on l'ajoute 
        $request = "UPDATE BillingEntity SET entityType='{0}', entityElement='{1}', entityFinanceCenter='{2}' WHERE entityId={3}" -f `
                    $type.toString(), $element, $financeCenter, $id

        $this.db.execute($request) | Out-Null
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie un item ou $null si pas trouvé
        
        IN  : $itemName         -> Nom de l'item (unique). Par ex nom moche de bucket S3
        IN  : $month            -> Mois de facturation
        IN  : $year             -> année de facturation

        RET : Objet avec les infos de l'item
            $null si pas trouvé
    #>
    hidden [PSObject] getItem([string]$itemName, [int]$month, [int]$year)
    {
        
        $request = "SELECT * FROM BillingItem WHERE itemName='{0}' AND itemMonth='{1}' AND itemYear='{2}'" -f $itemName, $month, $year

        $item = $this.db.execute($request)

        # On retourne le premier élément du tableau car c'est là que se trouve le résultat
        return $item[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute un item
        
        IN  : $parentEntityId   -> ID de l'entité à laquelle l'item est rattaché
        IN  : $type             -> Type de l'item. Identifiant ce que c'est. Ex: "S3 Bucket"
        IN  : $desc             -> Description. Se retrouvera dans la facture. Peut-être quelque
                                    chose de "complet"
        IN  : $month            -> Mois de facturation
        IN  : $year             -> année de facturation
        IN  : $quantity         -> quantité facturée pour le mois/année 
        IN  : $unit             -> L'unité dans laquelle la quantité est exprimée
        IN  : $priceLevel       -> le nom du niveau à appliquer de la grille de prix

        RET : ID de l'entité
                $null si pas ajouté car trop quantité de zéro
    #>
    hidden [int] addItem([int]$parentEntityId, [string]$type, [string]$name, [string]$desc, [int]$month, [int]$year, [double]$quantity, [string]$unit, [string]$priceLevel)
    {
        # On n'ajoute pas les items qui n'ont aucune consommation car cela entraînera une erreur lorsqu'ils seront repris pour être ajoutés dans Copernic.
        # Cependant, cette condition IF peut être commentée pour le développement, pour ajouter quelques enregistrements dans la DB, pour lesquels on changera
        # ensuite manuellement la valeur "quantity".
        if($quantity -eq 0)
        {
           return $null
        }

        $item = $this.getItem($name, $month, $year)

        # Si l'entité existe déjà dans la DB, on retourne son ID
        if($null -ne $item)
        {
            return $item.itemId
        }

        # L'entité n'existe pas, donc on l'ajoute 
        $request = "INSERT INTO BillingItem (parentEntityId, itemType, itemName, itemDesc, itemMonth, itemYear, itemQuantity, itemUnit, itemPriceLevel, itemBillReference) `
                                     VALUES ('{0}', '{1}', '{2}', '{3}', '{4}', '{5}', '{6}', '{7}', '{8}', NULL)" -f `
                            $parentEntityId, $type, $name, $desc, $month, $year, $quantity, $unit, $priceLevel

        $this.db.execute($request) | Out-Null

        return [int]($this.getItem($name, $month, $year)).itemId
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la description d'une EntityElement donné
        
        IN  : $entityType    -> Type de l'entité
        IN  : $entityElement -> élément. Soit no d'unité ou no de service IT, etc...

        RET : Description
    #>
    hidden [string] getEntityElementDesc([BillingEntityType]$entityType, [string]$entityElement)
    {
        switch($entityType)
        {
            Unit
            { 
                # Dans ce cas, $entityElement contient le no d'unité
                $unitInfos = $this.ldap.getUnitInfos($entityElement)

                if($null -eq $unitInfos)
                {
                    Throw ("No information found for Unit ID '{0}' in LDAP" -f $entityElement)
                }
                return $unitInfos.ou[0]
            }

            Service 
            {
                # Dans ce cas, $entityElement contient l'identifiant du service (ex: SVC007)
                $serviceInfos = $this.serviceList.getServiceInfos($this.targetEnv, $entityElement)

                if($null -eq $serviceInfos)
                {
                    Throw ("No information found for Service ID '{0}' in JSON file" -f $entityElement)
                }
                return $serviceInfos.longName
            }

        }
        Throw ("Entity type '{0}' not handled" -f $entityType.toString())
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des entités existantes dans la DB
    #>
    [Array] getEntityList()
    {
        return $this.db.execute("SELECT * FROM BillingEntity")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des items d'une entité qu'il faut encore facturer

        IN  : $entityId -> id de l'entité des items
        IN  : $itemType -> Type d'item auquel on est intéressé
    #>
    [Array] getEntityItemToBeBilledList([string]$entityId, [string]$itemType)
    {
        # Recherche des éléments. On trie par chronologie et nom d'élément et on ne prend que ceux qui n'ont pas été facturés.
        $request = "SELECT * FROM BillingItem WHERE parentEntityId='{0}' AND itemType='{1}' AND itemBillReference IS NULL ORDER BY itemYear,itemMonth,itemName ASC" -f `
                     $entityId, $itemType

        return $this.db.execute($request)
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des types d'items d'une entité qu'il faut encore facturer

        IN  : $entityId -> id de l'entité des items
    #>
    [Array] getEntityItemTypeToBeBilledList([string]$entityId)
    {
        # Recherche des éléments. On trie par chronologie et nom d'élément et on ne prend que ceux qui n'ont pas été facturés.
        $request = "SELECT DISTINCT(itemType) AS 'itemType' FROM BillingItem WHERE parentEntityId='{0}' AND itemBillReference IS NULL" -f `
                     $entityId

        return $this.db.execute($request) | Select-Object -ExpandProperty itemType
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Initialise un item comme ayant été facturé. On initialise simplement la référence
                de la facture sur laquelle il se trouve.

        IN  : $entityId         -> id de l'entité des items
        IN  : $itemTypeList     -> Liste des types d'item à noter comme facturés pour l'entité
        IN  : $billReference    -> référence de la facture auquel l'item a été attribué
    #>
    [void] setEntityItemTypesAsBilled([string]$entityId, [Array]$itemTypeList, [string]$billReference)
    {
        ForEach($itemType in $itemTypeList)
        {
            $request = "UPDATE BillingItem SET itemBillReference='{0}' WHERE parentEntityId='{1}' AND itemType='{2}' AND itemBillReference IS NULL " -f $billReference, $entityId, $itemType

            $this.db.execute($request) | Out-Null
        }   
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Annule la facture dont la référence a été passée, dans le but de la refaire.

        IN  : $billReference    -> No de référence de la facture à annuler
    #>
    [void] cancelBill([string]$billReference)
    {
        $request = "UPDATE BillingItem SET itemBillReference=NULL WHERE itemBillReference='{0}'" -f $billReference
        $this.db.execute($request) | Out-Null
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Envoie une facture par email à une adresse donnée

        IN  : $toMail           -> Adresse à laquelle envoyer la facture
        IN  : $PDFBillFile      -> Chemin jusqu'au fichier PDF 
        IN  : $mailSubject      -> Sujet du mail
        IN  : $periodStartDate  -> Date de début de la facture
        IN  : $periodEndDate    -> Date de fin de la facture
    #>
    [void] sendBillByMail([string]$toMail, [string]$PDFBillFile, [string]$mailSubject, [string]$periodStartDate, [string]$periodEndDate)
    {
        $mailMessage = (Get-Content -Path $global:XAAS_BILLING_MAIL_TEMPLATE -Encoding UTF8 ) -join "`n"

        # Elements à remplacer dans le template du mail
        $valToReplace = @{
            serviceName = $this.serviceBillingInfos.serviceName
            periodStartDate = $periodStartDate
            periodEndDate = $periodEndDate
        }

        # Parcours des remplacements à faire
        foreach($search in $valToReplace.Keys)
        {
            $replaceWith = $valToReplace.Item($search)

            $search = "{{$($search)}}"

            # Mise à jour dans le sujet et le mail
            $mailMessage =  $mailMessage -replace $search, $replaceWith
        }
        
        Send-MailMessage -From "noreply+vra.billing.bot@epfl.ch" -To $toMail -Subject $mailSubject `
                        -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding Unicode -Attachments $PDFBillFile    
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajout ou met à jour les infos d'une entité dans la DB en fonction des informations
                que l'on a sur elle, soit dans vRA, soit dans la tables des éléments déjà facturés

        IN  : $entityType   -> Type de l'entité
        IN  : $targetTenant -> Tenant sur lequel se trouve le BG
        IN  : $bgName       -> Nom du BG
        IN  : $itemName     -> Nom de l'item à facturer

        RET : ID de l'entité
                0 si pas trouvé (vu que les id démarrent à 1 dans la DB, on n'a pas de risque de faire faux)
    #>
    hidden [int] initAndGetEntityId([BillingEntityType]$entityType, [string]$targetTenant, [string]$bgName, [string]$itemName)
    {
        $bg = $this.vraTenantList.$targetTenant.getBG($bgName)

        if($null -eq $bg)
        {
            # On regarde donc si on a déjà référencé l'item dans la DB par le passé et on tente de
            # récupérer les infos de son entité
            $entity = $this.getItemEntity($itemName)

            # Si on n'a pas trouvé l'entité, c'est que l'item n'a encore jamais été rencontré dans un des mois
            # écoulés et que le BG a été supprimé entre temps. Donc impossible de récupérer quelque information
            # que ce soit... 
            if($null -eq $entity)
            {
                # On retourne 0 (pas $null parce qu'on doit retourner un INT). 
                return 0
            }

            $entityId = $entity.entityId
        }
        else # On a trouvé les infos du BG dans vRA donc on ajoute/met à jour l'entité
        {
            $entityElement = getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID

            # Ajout de l'entité à la base de données (si pas déjà présente)
            $entityId = $this.addEntity($entityType, `
                                        ("{0} {1}" -f $entityElement, $this.getEntityElementDesc($entityType, $entityElement)), `
                                        (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BILLING_FINANCE_CENTER))
        }
        
        return $entityId
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie l'entité qui correspond à un Item. Si on a déjà un item dans la DB, on 
                va pouvoir retourner l'entité. Sinon, on retournera $null

        IN  : $itemName     -> Nom de l'Item pour lequel on veut l'entité.

        RET : Objet représentant l'entité 
                $null si pas trouvé
    #>
    hidden [PSObject] getItemEntity([string]$itemName)
    {
        $request = "SELECT * FROM BillingItem WHERE itemName='{0}'" -f $itemName

        $items = $this.db.execute($request)

        if($items.count -eq 0)
        {
            return $null
        }

        # Retour de l'entité parente 
        return $this.getEntity($items[0].parentEntityId)
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Extrait les données pour un type d'élément à facturer

        IN  : $month    -> Le no du mois pour lequel extraire les infos
        IN  : $year     -> L'année pour laquelle extraire les infos
    #>
    [void] extractData([int]$month, [int]$year)
    {
        <# 
        Cette fonction devra être implémentée par les classes enfants de celle-ci. Elle sera en charge d'extraire mensuellement
        les données depuis d'autres tables de la DB qui varieront en fonction de l'élément à facturer. Il faudra utiliser les 
        fonctions suivantes pour ajouter les informations d'une manière structurée et réutilisable facilement pour la 
        suite du processus de facturation. 
        - getEntity
        - addEntity
        - getItem
        - addItem
        #>
        Throw "Not implemented!!!"
    }


}