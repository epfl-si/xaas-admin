<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS AVI Network

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021

#>

enum AviNetworksTenantType
{
   Development
   Test
   Production
}

class NameGeneratorAviNetworks: NameGeneratorBase
{
   
   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $vraEnv       -> Environnement sur lequel on travaille, notion vRA du terme
                                $TARGET_ENV_DEV
                                $TARGET_ENV_TEST
                                $TARGET_ENV_PROD
        IN  : $vraTenant   -> Tenant sur lequel on travaille
                                $VRA_TENANT_DEFAULT
                                $VRA_TENANT_EPFL
                                $VRA_TENANT_ITSERVICES

		RET : Instance de l'objet
	#>
    NameGeneratorAviNetworks([string]$vraEnv, [string]$vraTenant): base($vraEnv, $vraTenant)
   {
   }


   <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom et la description d'un tenant pour un BG donné

        IN  : $bgName         -> Nom du BusinessGroup
        IN  : $tenantType   -> Type de tenant (voir en haut du présent fichier)

		RET : Tableau avec
                - Nom du tenant
                - Description du tenant
	#>
    [Array] getTenantNameAndDesc([string]$bgName, [AviNetworksTenantType]$tenantType)
    {
        return @(
            ("{0}-{1}" -f $bgName, $tenantType.ToString()),
            ("BG: {0}, Type: {1}" -f $bgName, $tenantType.ToString())
        )
    }
}