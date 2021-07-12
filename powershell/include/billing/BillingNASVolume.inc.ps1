<#
   BUT : Classe permettant de récupérer des informations pour la facturation. On a 2 types d'éléments qui vont être
        géré par cette classe:
        - Entity --> l'entité pour laquelle on va faire la facturation. ça peut être une unité, un service ou un
                    projet. Les possibilités sont définies dans le type énuméré ci-dessous
        - Item --> élément à facturer pour un mois donné. Par exemple un volume NAS   

   AUTEUR : Lucien Chaboudez
   DATE   : Novembre 2020

   Prérequis:
   Les fichiers suivants doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - Billing.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class BillingNASVolume: Billing
{

    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $vraTenantList        -> Hashtable avec des objets de la classe VRA8API pour interroger vRA.
                                        Chaque objet a pour clef le nom du tenant et comme "contenu" le 
                                        nécessaire pour interroger le tenant
        IN  : $db                   -> Objet de la classe SQLDB permettant d'accéder aux données.
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
                                        Ces informations se trouvent dans le fichier JSON "service.json" qui sont 
                                        dans le dossier data/billing/<service>/service.json
        IN  : $targetEnv            -> Nom de l'environnement sur lequel on est.

		RET : Instance de l'objet
	#>
    BillingNASVolume([Hashtable]$vraTenantList, [SQLDB]$db, [PSObject]$serviceBillingInfos, [string]$targetEnv) : `
                    base($vraTenantList, $db, $serviceBillingInfos, $targetEnv, "NAS_Volume")
    {
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le type d'entité pour le volume passé en paramètre

        IN  : $itemInfos  -> Objet représentant le volume     
        
        RET : le type d'entité (du type énuméré [BillingEntityType])
                $null si pas supporté
    #>
    hidden [BillingEntityType] getEntityType([PSObject]$itemInfos)
    {
        # Le switch est "case insensitive"
        switch($itemInfos.targetTenant)
        {
            $global:VRA_TENANT__EPFL { return [BillingEntityType]::Unit}
            $global:VRA_TENANT__ITSERVICES { return [BillingEntityType]::Service }
            $global:VRA_TENANT__RESEARCH { return [BillingEntityType]::Project }

        }
        # Si on arrive ici, c'est que ce n'est pas géré
        return [BillingEntityType]::NotSupported
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la quantité utilisée pour un volume pour un mois et une année donnés. La quantité
                est pondérée au nombre de jours pendant lesquels le volume est utilisé dans le mois.
        
        IN  : $volUUID      -> UUID du volume
        IN  : $month        -> Le no du mois pour lequel extraire les infos
        IN  : $year         -> L'année pour laquelle extraire les infos

        RET : L'utilisation
    #>
    [float] getVolumeUsageTB([string]$volUUID, [int]$month, [int]$year)
    {
        $monthStr = $month.toString()
        if($month -lt 10)
        {
            # Ajout du 0 initial pour la requête de recherche 
            $monthStr = "0{0}" -f $monthStr
        }
        $request = "SELECT AVG(totSizeB)/1024/1024/1024/1024 AS 'usage', COUNT(*) as 'nbDays' FROM NasVolumeUsage WHERE date like '{0}-{1}-%' AND volId='{2}'" -f $year, $monthStr, $volUUID

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
        IN  : $logHistory   -> Objet pour faire un peu de logging de ce qu'on fait

        RET : Tableau avec:
                0 -> le nombre d'éléments ajoutés pour être facturés
                1 -> le nombre d'éléments non facturable (ex si dans ITServices)
                2 -> le nombre d'éléments avec une quantité de 0
                3 -> le nombre d'éléments ne pouvant pas être facturés car données par correctes
                4 -> le nombre d'éléments pour lesquels on n'a pas assez d'informations pour les facturer
    #>
    [Array] extractData([int]$month, [int]$year, [LogHistory]$logHistory)
    {
        # Compteurs
        $nbItemsAdded = 0
        $nbItemsNotBillable = 0
        $nbItemsAmountZero = 0
        $nbItemsNotSupported = 0
        $nbItemsNotEnoughInfos = 0

        # On commence par récupérer la totalité des entités pour lequels des volumes ont été créés
        $entityList = $this.db.execute("SELECT DISTINCT(bgId) FROM NasVolumeArchive")

        # Parcours des entités
        ForEach($entity in $entityList)
        {
            $logHistory.addLineAndDisplay(("Processing entity {0}..." -f $entity.bgId))

            $volumeList = $this.db.execute(("SELECT * FROM NasVolumeArchive WHERE bgId='{0}'" -f $entity.bgId))

            $logHistory.addLineAndDisplay(("> {0} Volumes to process" -f $volumeList.count))
    
            $oneVolumeAddedForEntity = $false

            # Assignation de la valeur pour ne pas avoir d'erreur dans l'éditeur plus loin lorsqu'on référence cette variable
            $entityId = $null
            $entityType = $null

            # Parcours de la liste des volumes
            ForEach($volume in $volumeList)
            {
                $logHistory.addLineAndDisplay((">> Processing Volume {0} ({1})..." -f $volume.volName, $volume.bgId))
                $entityType = $this.getEntityType($volume)
    
                # Si pas supporté, on passe à l'élément suivant
                # NOTE: on n'utilise pas de "switch" car l'utilisation de "Continue" n'est pas possible au sein de celui-ci...
                if($entityType -eq [BillingEntityType]::NotSupported)
                {
                    $logHistory.addLineAndDisplay((">> Entity not supported for item (name={0}, tenant={1})" -f $volume.volName, $volume.targetTenant))
                    $nbItemsNotSupported++
                    Continue
                }
    
                if($volume.targetTenant -eq $global:VRA_TENANT__ITSERVICES)
                {
                    $logHistory.addLineAndDisplay((">> Skipping ITService entity ({0}) because not billed" -f $volume.volName))
                    $nbItemsNotBillable++
                    Continue
                }
                
                # On ajoute ou met à jour l'entité dans la DB et on retourne son ID
                $entityId = $this.initAndGetEntityId($entityType, $volume.targetTenant, $volume.bgId, $volume.volId)
    
                # Si on n'a pas trouvé l'entité, c'est que n'a pas les infos nécessaires pour l'ajouter à la DB
                if($entityId -eq 0)
                {
                    $logHistory.addLineAndDisplay((">> Business Group '{0}' with ID {1} ('{2}') has been deleted and item '{3}' wasn't existing last month. Not enough information to bill it" -f `
                                    $entityType.toString(), $volume.bgId, $volume.targetTenant, $volume.volName))
                    $nbItemsNotEnoughInfos++
                    Continue
                }
                
                $logHistory.addLineAndDisplay((">> Entity '{0}' type is {1} (tenant = {2})" -f $volume.unitOrSvcID, $entityType.toString(), $volume.targetTenant))
    
                # -- Informations sur l'élément à facturer --
    
                # Recherche de l'utilisation pour le mois donné 
                $volumeUsage = $this.getVolumeUsageTB($volume.volId, $month, $year)
    
                # On coupe à la 2e décimale 
                $volumeUsage = truncateToNbDecimal -number $volumeUsage -nbDecimals 2
    
                $logHistory.addLineAndDisplay((">> Volume is using {0} TB" -f $volumeUsage))
    
                # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
                $itemDesc = "{0}`nOwner: {1}" -f $volume.volName, $this.getItemOwner($volume.requestor)
    
                # Ajout de l'item et check s'il a effectivement été ajouté
                if($this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $volume.volId, $itemDesc, $month, $year, $volumeUsage, "TB" ,"U.1") -ne 0)
                {
                    $logHistory.addLineAndDisplay(">> Added to Volumes to be billed")
                    # Incrémentation du nombre d'éléments ajoutés
                    $nbItemsAdded++
                    # Pour dire qu'on a au moins ajouté un volume pour l'entité courante
                    $oneVolumeAddedForEntity = $true
                }
                else # L'item n'a pas été ajouté car quantité égale à 0
                {
                    $logHistory.addLineAndDisplay(">> Ignored because quantity equals 0")
                    $nbItemsAmountZero++
                }
    
            }# FIN BOUCLE de parcours des volumes

            # Si on a ajouté au moins un volume pour l'entité pour le mois courant
            # ET que c'est une entité EPFL (oui, on fait quand même le check même si à priori on ne gère pas les entité ITServices encore... c'est juste pour éviter que
            # le jour où on gère les ITServices (ou projets) aussi, ben on ait une mauvaise surprise avec des services/projet qui se verraient offrir 1TB gratuit.
            if($oneVolumeAddedForEntity -and ($entityType -eq [BillingEntityType]::Unit))
            {
                $itemNameAndDesc = "Monthly free NAS usage"
                # Ajout d'un volume fictif pour l'unité, avec une utilisation négative qui représente ce qui est offert
                $this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $itemNameAndDesc, $itemNameAndDesc, $month, $year, -1, "TB" ,"U.1")
            }

        }# FIN BOUCLE de parcours des entités

        

        return @($nbItemsAdded, $nbItemsNotBillable, $nbItemsAmountZero, $nbItemsNotSupported, $nbItemsNotEnoughInfos)

    }
}