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
        IN  : $ldap                 -> Connexion au LDAP pour récupérer les infos sur les unités
        IN  : $serviceList          -> Objet avec la liste de services (chargé depuis le fichier JSON itservices.json)
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
                                        Ces informations se trouvent dans le fichier JSON "service.json" qui sont 
                                        dans le dossier data/billing/<service>/service.json
        IN  : $targetEnv            -> Nom de l'environnement sur lequel on est.

		RET : Instance de l'objet
	#>
    BillingS3Bucket([Hashtable]$vraTenantList, [SQLDB]$db, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv) : base($vraTenantList, $db, $ldap, $serviceList, $serviceBillingInfos, $targetEnv)
    {
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le type d'entité pour le bucket passé en paramètre

        IN  : $bucketInfos  -> Objet représentant le bucket     
        
        RET : le type d'entité
                $null si pas supporté
    #>
    hidden [PSObject] getEntityType([PSObject]$bucketInfos)
    {

        # On va utiliser le champ "unitOrSvcID"
        if($bucketInfos.unitOrSvcID -match $this.entityMatchUnit)
        {
            return [EntityType]::Unit
        }
        if($bucketInfos.unitOrSvcID -match $this.entityMatchSvc)
        {
            return [EntityType]::Service
        }
        # Si on arrive ici, c'est que ce n'est pas géré donc on renvoie $null
        return $null
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
    #>
    [void] extractData([int]$month, [int]$year)
    {
        
        # On commence par récupérer la totalité des Buckets qui existent. Ceci est fait en interrogeant une table spéciale
        # dans laquelle on a tous les buckets, y compris ceux qui ont été effacés
        $request = "SELECT * FROM BucketsArchive"
        $bucketList = $this.db.execute($request)

        # Parcours de la liste des buckets
        ForEach($bucket in $bucketList)
        {
            $entityType = $this.getEntityType($bucket)

            $targetTenant = $null

            # Si pas supporté, on passe à l'élément suivant
            # NOTE: on n'utilise pas de "switch" car l'utilisation de "Continue" n'est pas possible au sein de celui-ci...
            if($null -eq $entityType)
            {
                Continue
            }
            elseif($entityType -eq [EntityType]::Service)
            {
                Write-Warning ("Skipping Service entity ({0}) because not billed" -f $bucket.bucketName)
                Continue
            }
            elseif($entityType -eq [EntityType]::Unit)
            {
                $targetTenant = $global:VRA_TENANT__EPFL
            }
            elseif($entityType -eq [EntityType]::Project)
            {
                $targetTenant = $global:VRA_TENANT__RESEARCH
            }
            

            # Recherche des infos sur l'élément concerné et le "détail" de celui-ci
            $entityElement = $bucket.unitOrSvcID
            $entityElementDesc = $this.getEntityElementDesc($entityType, $entityElement)

            $entityFinanceCenter = $this.getEntityElementFinanceCenter($entityType, $entityElement)

            # Ajout de l'entité à la base de données (si pas déjà présente)
            $entityId = $this.addEntity($entityType, ("{0} {1}" -f $entityElement, $entityElementDesc), $entityFinanceCenter)


            # -- Informations sur l'élément à facturer --

            # Recherche de l'utilisation pour le mois donné 
            $bucketUsage = $this.getBucketUsageTB($bucket.bucketName, $month, $year)

            # On coupe à la 2e décimale 
            $bucketUsage = truncateToNbDecimal -number $bucketUsage -nbDecimals 2

            # Recherche du bucket en lui-même
            $vraBucket = $this.vraTenantList.$targetTenant.getItem("S3_Bucket", $bucket.friendlyName)

            # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
            $itemDesc = "{0}`n({1})`nOwner: {2}" -f $bucket.bucketName, $bucket.friendlyName, $vraBucket.owners[0].value

            $itemId = $this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $bucket.bucketName, $itemDesc, $month, $year, $bucketUsage, "TB" ,"U.1")


        }# FIN parcours des buckets
    }
}