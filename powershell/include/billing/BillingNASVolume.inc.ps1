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
    BillingNASVolume([Hashtable]$vraTenantList, [SQLDB]$db, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv) : base($vraTenantList, $db, $ldap, $serviceList, $serviceBillingInfos, $targetEnv)
    {
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie le type d'entité pour le volume passé en paramètre

        IN  : $volumeInfos  -> Objet représentant le volume     
        
        RET : le type d'entité
                $null si pas supporté
    #>
    hidden [PSObject] getEntityType([PSObject]$volumeInfos)
    {
        # Le switch est "case insensitive"
        switch($volumeInfos.targetTenant)
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
    #>
    [void] extractData([int]$month, [int]$year)
    {
        
        # On commence par récupérer la totalité des volumes qui existent. Ceci est fait en interrogeant une table spéciale
        # dans laquelle on a tous les volumes, y compris ceux qui ont été effacés
        $request = "SELECT * FROM NasVolumeArchive"
        $volumeList = $this.db.execute($request)

        # Parcours de la liste des volumes
        ForEach($volume in $volumeList)
        {
            $entityType = $this.getEntityType($volume)

            $targetTenant = $volume.targetTenant

            # Si pas supporté, on passe à l'élément suivant
            # NOTE: on n'utilise pas de "switch" car l'utilisation de "Continue" n'est pas possible au sein de celui-ci...
            if($null -eq $entityType)
            {
                Continue
            }

            if($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
            {
                Write-Warning ("Skipping Service entity ({0}) because not billed" -f $volume.volName)
                Continue
            }
            
            # Recherche des détails de l'entité
            $entityDetails = $this.getEntityDetails($targetTenant, $volume.bgName)

            if($null -eq $entityDetails)
            {
                Write-Warning ("Business group '{0}' doesn't exists anymore on tenant '{1}'" -f $volume.bgName, $targetTenant)
                Continue
            }

            # Recherche des infos sur l'élément concerné et le "détail" de celui-ci
            $entityElement = $entityDetails.entityElement
            $entityElementDesc = $this.getEntityElementDesc($entityType, $entityElement)

            $entityFinanceCenter = $entityDetails.entityFinanceCenter

            # Ajout de l'entité à la base de données (si pas déjà présente)
            $entityId = $this.addEntity($entityType, ("{0} {1}" -f $entityElement, $entityElementDesc), $entityFinanceCenter)


            # -- Informations sur l'élément à facturer --

            # Recherche de l'utilisation pour le mois donné 
            $volumeUsage = $this.getVolumeUsageTB($volume.volId, $month, $year)

            # On coupe à la 2e décimale 
            $volumeUsage = truncateToNbDecimal -number $volumeUsage -nbDecimals 2

            # Recherche du volume en lui-même dans vRA
            $vraVolume = $this.vraTenantList.$targetTenant.getItem("NAS_Volume", $volume.volName)

            # Si le volume a été effacé entre temps,
            if($null -eq $vraVolume)
            {
                # Le owner est du coup "inconnu"
                $owner = "Unknown"
            }
            else
            {
                $owner = $vraVolume.owners[0].value
            }

            # Description de l'élément (qui sera mise ensuite dans le PDF de la facture)
            $itemDesc = "{0}`nOwner: {1}" -f $volume.volName, $owner

            $this.addItem($entityId, $this.serviceBillingInfos.billedItems[0].itemTypeInDB, $volume.volId, $itemDesc, $month, $year, $volumeUsage, "TB" ,"U.1") | Out-Null


        }# FIN parcours des buckets
    }
}