<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS AVI Network

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021

   https://confluence.epfl.ch:8443/display/SIAC/%5BIaaS%5D+AVI+Networks
#>



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
    [Array] getTenantNameAndDesc([string]$bgName, [XaaSAviNetworksTenantType]$tenantType)
    {
        return @(
            ("{0}-{1}" -f $bgName, $tenantType.ToString()),
            ("BG: {0}, Type: {1}" -f $bgName, $tenantType.ToString())
        )
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom d'une alerte et le nom de son niveau 

        IN  : $level    -> Identifiant du niveau

		RET : Tableau avec
                - Nom de l'alerte
                - Nom du niveau
	#>
    [Array] getAlertNameAndLevel([XaaSAviNetworksAlertLevel]$level)
    {
        return @(
            ("Alert-{0}-Email" -f $level.toString()),
            ("ALERT_{0}" -f $level.toString().toUpper())
        )
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom d'une "Alert config"

        IN  : $element  -> Element qui doit être monitoré
        IN  : $status   -> statut à monitorer

		RET : Nom de l'Alert Config.
	#>
    [string] getAlertConfigName([XaaSAviNetworksMonitoredElements]$element, [XaaSAviNetworksMonitoredStatus]$status)
    {
        $elementStr = switch($element)
        {
            VirtualService { "VS" }
            Pool { "Pool"}
        }

        return ("{0}-{1}" -f $elementStr, $status.toString().toUpper())
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du virtual service.

        IN  : $friendlyName     -> Nom entré par l'utilisateur
        IN  : $deploymentTag    -> tag de déploiement

		RET : Nom du virtual service
	#>
    [string] getVirtualServiceName([string]$friendlyName, [DeploymentTag]$deploymentTag)
    {
        return "{0}-{1}" -f $friendlyName, $this.getDeploymentTagShort($deploymentTag.toString())
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du pool pour un virtual service donné.

        IN  : $virtualServiceName     -> Nom du virtual service auquel le pool est lié.

		RET : Nom du pool
	#>
    [string] getPoolName([string]$virtualServiceName)
    {
        return "{0}-pool" -f $virtualServiceName
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du VRF Context pour un virtual service donné.

        IN  : $deploymentTag    -> tag de déploiement

		RET : Nom du VRF Context
	#>
    [string] getVRFContextName([DeploymentTag]$deploymentTag)
    {
        $tenant = switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL { "EPFL" }
            $global:VRA_TENANT__ITSERVICES { "ITServices"}
        }   

        return "{0}-{1}" -f $tenant, $deploymentTag.toString()
    }

}