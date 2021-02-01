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
   - Billing.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class BillingS3Bucket: Billing
{

    
    hidden [string] $entityMatchUnit = "^[0-9]{1,5}$"
    hidden [string] $entityMatchSvc = "^SVC[0-9]{3,4}$"

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $vraTenantList        -> Hashtable avec des objets de la classe VRAAPI pour interroger vRA.
                                        Chaque objet a pour clef le nom du tenant et comme "contenu" le 
                                        nécessaire pour interroger le tenant
        IN  : $db                   -> Objet de la classe SQLDB permettant d'accéder aux données.
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
                                        Ces informations se trouvent dans le fichier JSON "service.json" qui sont 
                                        dans le dossier data/billing/<service>/service.json
        IN  : $targetEnv            -> Nom de l'environnement sur lequel on est.

		RET : Instance de l'objet
	#>
    BillingS3Bucket([Hashtable]$vraTenantList, [SQLDB]$db, [PSObject]$serviceBillingInfos, [string]$targetEnv) : `
                    base($vraTenantList, $db, $serviceBillingInfos, $targetEnv, "S3_Bucket")
    {
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le type d'entité pour le bucket passé en paramètre

        IN  : $itemInfos  -> Objet représentant le bucket     
        
        RET : le type d'entité (du type énuméré [BillingEntityType])
                $null si pas supporté
    #>
    hidden [BillingEntityType] getEntityType([PSObject]$itemInfos)
    {

        # On va utiliser le champ "unitOrSvcID"
        if($itemInfos.unitOrSvcID -match $this.entityMatchUnit)
        {
            return [BillingEntityType]::Unit
        }
        if($itemInfos.unitOrSvcID -match $this.entityMatchSvc)
        {
            return [BillingEntityType]::Service
        }
        # Si on arrive ici, c'est que ce n'est pas géré
        return [BillingEntityType]::NotSupported
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la quantité utilisée pour un bucket pour un mois et une année donnés. La quantité
                est pondérée au nombre de jours pendant lesquels le bucket est utilisé dans le mois.
        
        IN  : $bucketName   -> nom du bucket 
        IN  : $month        -> Le no du mois pour lequel extraire les infos
        IN  : $year         -> L'année pour laquelle extraire les infos

        RET : L'utilisation
    #>
    [float] getBucketUsageTB([string]$bucketName, [int]$month, [int]$year)
    {
        $monthStr = $month.toString()
        if($month -lt 10)
        {
            # Ajout du 0 initial pour la requête de recherche 
            $monthStr = "0{0}" -f $monthStr
        }
        $request = "SELECT AVG(storageUtilized)/1024/1024/1024/1024 AS 'usage', COUNT(*) as 'nbDays' FROM BucketsUsage WHERE date like '{0}-{1}-%' AND bucketName='{2}'" -f $year, $monthStr, $bucketName

        $res = $this.db.execute($request)

        try
        {
            # Calcul de la moyenne en fonction du nombre de jours utilisés durant le mois
            return  $res[0].nbDays * $res[0].usage / [DateTime]::DaysInMonth($year, $month)
        }
        catch
        {
            return 0
        }
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Extrait les données pour les Buckets S3 à facturer. On va regarder dans les tables
                dans lesquelle les informations se trouvent, les transformer, et les mettre dans
                des tables dont le format est défini, ceci à l'aide des fonctions définies dans
                la classe parente
        
        IN  : $month    -> Le no du mois pour lequel extraire les infos
        IN  : $year     -> L'année pour laquelle extraire les infos

        RET : Tableau avec:
                0 -> le nombre d'éléments ajoutés pour être facturés
                1 -> le nombre d'éléments non facturable (ex si dans ITServices)
                2 -> le nombre d'éléments avec une quantité de 0
                3 -> le nombre d'éléments ne pouvant pas être facturés car données par correctes
                4 -> le nombre d'éléments pour lesquels on n'a pas assez d'informations pour les facturer
    #>
    [Array] extractData([int]$month, [int]$year)
    {
        # Compteurs
        $nbItemsAdded = 0
        $nbItemsNotBillable = 0
        $nbItemsAmountZero = 0
        $nbItemsNotSupported = 0
        $nbItemsNotEnoughInfos = 0
        
        # On commence par récupérer la totalité des Buckets qui existent. Ceci est fait en interrogeant une table spéciale
        # dans laquelle on a tous les buckets, y compris ceux qui ont été effacés
        $request = "SELECT * FROM BucketsArchive"
        $bucketList = $this.db.execute($request)

        # Parcours de la liste des buckets
        ForEach($bucket in $bucketList)
        {
            $entityType = $this.getEntityType($bucket)

            $targetTenant = $null

            # Si pas supporté, on passe à l'élément suivant. 
            # NOTE: on n'utilise pas de "switch" car l'utilisation de "Continue" n'est pas possible au sein de celui-ci...
            # On n'utilise pas non plus la valeur "targetTenant" présente dans la table BucketArchive car elle ne correspond pas au tenant vRA réel
            if($entityType -eq [BillingEntityType]::NotSupported)
            {
                # Si on arrive ici, c'est que ce n'est pas supporté ou que potentiellement le champ unitOrSvcID ne contient pas une valeur correcte,
                # ce qui peut arriver dans l'environnement de test (et prod) parce qu'on met un peu tout et n'importe quoi dans unitOrSvcID...
                Write-Warning ("Entity not supported for item (name={0}, unitOrSvcId={1})" -f $bucket.bucketName, $bucket.unitOrSvcID)
                $nbItemsNotSupported++
                Continue
            }
            elseif($entityType -eq [BillingEntityType]::Service)
            {
                Write-Warning ("Skipping 'ITService' entity (for bucket {0}) because not billed" -f $bucket.bucketName)
                $nbItemsNotBillable++
                Continue
            }
            elseif($entityType -eq [BillingEntityType]::Unit)
            {
                $targetTenant = $global:VRA_TENANT__EPFL
            }
            elseif($entityType -eq [BillingEntityType]::Project)
            {
                $targetTenant = $global:VRA_TENANT__RESEARCH
            }

            # On ajoute ou met à jour l'entité dans la DB et on retourne son ID
            $entityId = $this.initAndGetEntityId($entityType, $targetTenant, $bucket.unitOrSvcID, $bucket.bucketName)

            # Si on n'a pas trouvé l'entité, c'est que n'a pas les infos nécessaires pour l'ajouter à la DB
            if($null -eq $entityId)
            {
                Write-Warning ("Business Group '{0}' with ID {1} ('{2}') has been deleted and item '{3}' wasn't existing last month. Not enough information to bill it" -f `
                                $entityType.toString(), $bucket.unitOrSvcID, $targetTenant, $bucket.bucketName)
                $nbItemsNotEnoughInfos++
                Continue
            }


            # -- Informations sur l'élément à facturer --

            # Recherche de l'utilisation pour le mois donné 
            $bucketUsage = $this.getBucketUsageTB($bucket.bucketName, $month, $year)

            # On coupe à la 2e décimale 
            $bucketUsage = truncateToNbDecimal -number $bucketUsage -nbDecimals 2

            # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
            $itemDesc = "{0}`n({1})`nOwner: {2}" -f $bucket.bucketName, $bucket.friendlyName, $this.getItemOwner($bucket.requestor)

            if($this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $bucket.bucketName, $itemDesc, $month, $year, $bucketUsage, "TB" ,"U.1") -ne 0)
            {
                # Incrémentation du nombre d'éléments ajoutés
                $nbItemsAdded++
            }
            else # L'item n'a pas été ajouté car quantité égale à 0
            {
                $nbItemsAmountZero++
            }

        }# FIN parcours des buckets

        return @($nbItemsAdded, $nbItemsNotBillable, $nbItemsAmountZero, $nbItemsNotSupported, $nbItemsNotEnoughInfos)
    }
}