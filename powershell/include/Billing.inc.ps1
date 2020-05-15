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
   - MySQL.inc.ps1
   - define.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
enum EntityType 
{
    Unit
    Service
    Project
}

class Billing
{
    hidden [MySQL] $mysql
    hidden [string] $targetEnv
    hidden [PSObject] $serviceList
    hidden [EPFLLDAP] $ldap
    hidden [PSObject] $serviceBillingInfos


    <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $mysql                -> Objet de la classe MySQL permettant d'accéder aux données.
        IN  : $ldap                 -> Connexion au LDAP pour récupérer les infos sur les unités
        IN  : $serviceList          -> Objet avec la liste de services (chargé depuis le fichier JSON itservices.json)
        IN  : $serviceBillingInfos  -> Objet avec les informations de facturation pour le service 
                                        Ces informations se trouvent dans le fichier JSON "service.json" qui sont 
                                        dans le dossier data/billing/<service>/service.json
        IN  : $targetEnv            -> Nom de l'environnement sur lequel on est.

		RET : Instance de l'objet
	#>
    Billing([MySQL]$mysql, [EPFLLDAP]$ldap, [PSObject]$serviceList, [PSObject]$serviceBillingInfos, [string]$targetEnv)
    {
        $this.mysql = $mysql
        $this.ldap = $ldap
        $this.serviceList = $serviceList
        $this.serviceBillingInfos = $serviceBillingInfos
        $this.targetEnv = $targetEnv
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie une entité ou $null si pas trouvé
        
        IN  : $type             -> Type de l'entité (du type énuméré défini plus haut).
        IN  : $element          -> Id d'unité, no de service ou no de fond de projet...

        RET : Objet avec les infos de l'entité 
            $null si pas trouvé
    #>
    hidden [PSObject] getEntity([EntityType]$type, [string]$element)
    {
        $request = "SELECT * FROM BillingEntity WHERE entityType='{0}' AND entityElement='{1}'" -f $type, $element

        $entity = $this.mysql.execute($request)

        # On retourne le premier élément du tableau car c'est là que se trouve le résultat
        return $entity[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute une entité
        
        IN  : $type             -> Type de l'entité (du type énuméré défini plus haut).
        IN  : $element          -> Id d'unité, no de service ou no de fond de projet...
        IN  : $financeCenter    -> No du centre financier auquel imputer la facture

        RET : ID de l'entité
    #>
    hidden [int] addEntity([EntityType]$type, [string]$element, [string]$financeCenter)
    {
        $entity = $this.getEntity($type, $element)

        # Si l'entité existe déjà dans la DB, on retourne son ID
        if($null -ne $entity)
        {
            return [int]$entity.entityId
        }

        # L'entité n'existe pas, donc on l'ajoute 
        $request = "INSERT INTO BillingEntity VALUES (NULL, '{0}', '{1}', '{2}')" -f $type.toString(), $element, $financeCenter

        $res =  $this.mysql.execute($request)

        return [int] ($this.getEntity($type, $element)).entityId
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

        $item = $this.mysql.execute($request)

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

        RET : ID de l'entité
    #>
    hidden [int] addItem([int]$parentEntityId, [string]$type, [string]$name, [string]$desc, [int]$month, [int]$year, [double]$quantity)
    {
        
        $item = $this.getItem($name, $month, $year)

        # Si l'entité existe déjà dans la DB, on retourne son ID
        if($null -ne $item)
        {
            return $item.itemId
        }

        # L'entité n'existe pas, donc on l'ajoute 
        $request = "INSERT INTO BillingItem VALUES (NULL, '{0}', '{1}', '{2}', '{3}', '{4}', '{5}', '{6}', NULL)" -f `
                            $parentEntityId, $type, $name, $desc, $month, $year, $quantity

        $res = $this.mysql.execute($request)

        return [int]($this.getItem($name, $month, $year)).itemId
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Renvoie la description d'une EntityElement donné
        
        IN  : $entityType    -> Type de l'entité
        IN  : $entityElement -> élément. Soit no d'unité ou no de service IT, etc...

        RET : Description
    #>
    hidden [string] getEntityElementDesc([EntityType]$entityType, [string]$entityElement)
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
        BUT : Renvoie la centre financier d'une EntityElement donnée
        
        IN  : $entityType    -> Type de l'entité
        IN  : $entityElement -> élément. Soit no d'unité ou no de service IT, etc...

        RET : Centre financier
    #>
    hidden [string] getEntityElementFinanceCenter([EntityType]$entityType, [string]$entityElement)
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
                return $unitInfos.accountingnumber 
            }


        }
        Throw ("Entity type '{0}' not handled" -f $entityType.toString())
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