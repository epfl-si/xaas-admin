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

        IN  : $mysql        -> Objet de la classe MySQL permettant d'accéder aux données.
        IN  : $ldap         -> Connexion au LDAP pour récupérer les infos sur les unités
        IN  : $serviceList  -> Objet avec la liste de services (chargé depuis le fichier JSON itservices.json)
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
        IN  : $targetEnv    -> Nom de l'environnement sur lequel on est.

		RET : Instance de l'objet
	#>
    BillingS3Bucket([MySQL]$mysql, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv) : base($mysql, $ldap, $serviceList, $serviceBillingInfos, $targetEnv)
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
        <# 
            Du fait qu'on a un environnement de test qui est sur la production et que les données ne sont pas
            "propres" par rapport à ce qu'on a défini en production car tout est affecté au tenant "test", même
            si c'est de la "prod". La définition du type de l'entity va se faire de manière différente
        #>
        if($this.targetEnv -eq $global:TARGET_ENV__TEST)
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
        else # Production
        {
            switch($bucketInfos.targetTenant)
            {
                $global:VRA_TENANT__EPFL { return Unit }
                $global:VRA_TENANT__ITSERVICES { return Service}
            }
            Throw ("Tenant '{0}' not handled" -f $bucketInfos.targetTenant)
        }
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la quantité utilisée pour un bucket pour un mois et une année donnés
        
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
        $request = "SELECT AVG(storageUtilized)/1024/1024/1024/1024 AS 'usage' FROM BucketsUsage WHERE date like '{0}-{1}-%' AND bucketName='{2}'" -f $year, $monthStr, $bucketName

        $res = $this.mysql.execute($request)

        # Si aucune utilisation
        if($res[0].usage -eq "NULL")
        {
            return 0
        }
        return  $res[0].usage
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
        
        # On commence par récupérer la totalité des Buckets qui existent
        $request = "SELECT * FROM Buckets"
        $bucketList = $this.mysql.execute($request)

        # Parcours de la liste des buckets
        ForEach($bucket in $bucketList)
        {
            $entityType = $this.getEntityType($bucket)

            # Si pas supporté, on passe à l'élément suivant
            if($null -eq $entityType)
            {
                Continue
            }

            # On skip les entité "Service"
            if($entityType -eq [EntityType]::Service)
            {
                Write-Warning ("Skipping Service entity ({0})" -f $bucket.bucketName)
                Continue
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

            # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
            $itemDesc = "{0}`n{1}`n({2})" -f $this.serviceBillingInfos.itemDescPrefix, $bucket.bucketName, $bucket.friendlyName

            $itemId = $this.addItem($entityId, $this.serviceBillingInfos.itemTypeInDB, $bucket.bucketName, $itemDesc, $month, $year, $bucketUsage)


        }# FIN parcours des buckets
    }
}