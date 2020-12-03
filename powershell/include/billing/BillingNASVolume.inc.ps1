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

		RET : Instance de l'objet
	#>
    BillingNASVolume([Hashtable]$vraTenantList, [SQLDB]$db, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv) : `
                    base($vraTenantList, $db, $ldap, $serviceList, $serviceBillingInfos, $targetEnv, "NAS_Volume")
    {
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le type d'entité pour le volume passé en paramètre

        IN  : $itemInfos  -> Objet représentant le volume     
        
        RET : le type d'entité (du type énuméré [BillingEntityType])
                $null si pas supporté
    #>
    hidden [PSObject] getEntityType([PSObject]$itemInfos)
    {
        # Le switch est "case insensitive"
        switch($itemInfos.targetTenant)
        {
            $global:VRA_TENANT__EPFL { return [BillingEntityType]::Unit}
            $global:VRA_TENANT__ITSERVICES { return [BillingEntityType]::Service }
            $global:VRA_TENANT__RESEARCH { return [BillingEntityType]::Project }

        }
        # Si on arrive ici, c'est que ce n'est pas géré donc on renvoie $null
        return $null
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

        RET : le nombre d'éléments ajoutés pour être facturés
    #>
    [int] extractData([int]$month, [int]$year)
    {
        $nbItemsAdded = 0

        # On commence par récupérer la totalité des volumes qui existent. Ceci est fait en interrogeant une table spéciale
        # dans laquelle on a tous les volumes, y compris ceux qui ont été effacés
        $request = "SELECT * FROM NasVolumeArchive"
        $volumeList = $this.db.execute($request)

        # Parcours de la liste des volumes
        ForEach($volume in $volumeList)
        {
            $entityType = $this.getEntityType($volume)

            # Si pas supporté, on passe à l'élément suivant
            # NOTE: on n'utilise pas de "switch" car l'utilisation de "Continue" n'est pas possible au sein de celui-ci...
            if($null -eq $entityType)
            {
                Continue
            }

            if($volume.targetTenant -eq $global:VRA_TENANT__ITSERVICES)
            {
                Write-Warning ("Skipping Service entity ({0}) because not billed" -f $volume.volName)
                Continue
            }
            
            # On ajoute ou met à jour l'entité dans la DB et on retourne son ID
            $entityId = $this.initAndGetEntityId($entityType, $volume.targetTenant, $volume.bgId, $volume.volId)

            # Si on n'a pas trouvé l'entité, c'est que n'a pas les infos nécessaires pour l'ajouter à la DB
            if($entityId -eq 0)
            {
                Write-Warning ("Business Group '{0}' with ID {1} ('{2}') has been deleted and item '{3}' wasn't existing last month. Not enough information to bill it" -f `
                                $entityType.toString(), $volume.bgId, $volume.targetTenant, $volume.volName)
                Continue
            }
            

            # -- Informations sur l'élément à facturer --

            # Recherche de l'utilisation pour le mois donné 
            $volumeUsage = $this.getVolumeUsageTB($volume.volId, $month, $year)

            # On coupe à la 2e décimale 
            $volumeUsage = truncateToNbDecimal -number $volumeUsage -nbDecimals 2

            # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
            $itemDesc = "{0}`nOwner: {1}" -f $volume.volName, $this.getItemOwner($volume.requestor)

            # Ajout de l'item et check s'il a effectivement été ajouté
            if($this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $volume.volId, $itemDesc, $month, $year, $volumeUsage, "TB" ,"U.1") -ne 0)
            {
                # Incrémentation du nombre d'éléments ajoutés
                $nbItemsAdded++
            }

        }# FIN parcours des buckets

        return $nbItemsAdded

    }
}