<#
   BUT : Permet d'accéder de manière aisée aux informations contenues dans le fichier JSON décrivant
        les éléments à utiliser pour créer les approval policies pour les requêtes de nouveaux éléments.

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2019



	REMARQUES :
	

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NewItems : JSONUtils
{
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Charge les données du fichier JSON passé en paramètre. On ne fait ici qu'appeler
               le constructeur de la classe parente
        
        IN  : $JSONFilename     -> Nom court du fichier JSON à charger
    #>
    NewItems([string]$JSONFilename) : base($JSONFilename)
    {
        # Rien à faire ici
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du fichier JSON à utiliser pour créer l'approval policy pour le tenant
               passé en paramètre
        
        IN  : $tenant      -> Nom du tenant
    #>
    [string] getApprovalPolicyJSON([string]$tenant)
    {
      return $this.getJSONNodeValue($this.JSONData, "tenant", $tenant, "approvalPolicyJSON")
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du fichier JSON à utiliser pour créer les différents level d'approbation
               (pour l'approval policy) pour le tenant passé en paramètre
        
        IN  : $tenant      -> Nom du tenant
    #>
    [string] getApprovalLevelJSON([string]$tenant)
    {
      return $this.getJSONNodeValue($this.JSONData, "tenant", $tenant, "approvalLevelJSON")
    }
}    