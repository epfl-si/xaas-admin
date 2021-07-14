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
        IN  : $deploymentTag -> Le tag de déploiement    

		RET : Instance de l'objet
	#>
    NameGeneratorAviNetworks([string]$vraEnv, [string]$vraTenant, [DeploymentTag]$deploymentTag): base($vraEnv, $vraTenant)
    {
        $this.initDeploymentTag($deploymentTag)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom court pour un type de VIP de Virtual Service

        IN  : $vipType      -> Le type de la VIP
        
		RET : Le nom court du type
	#>
    hidden [string] getVSVipTypeShortName([XaaSAviVipType]$vipType)
    {
        $res = switch($vipType)
        {
            Private { "priv" }
            Public { "pub" }
        }
        return $res
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la première lettre du profil SSL

        IN  : $sslProfile     -> Profil SSL

		RET : Première lettre du profil
	#>
    hidden [string] getSSLProfileFirstLetter([XaaSAviSSLProfile]$sslProfile)
    {
        return $sslProfile.ToString().toLower()[0]
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
    [Array] getTenantNameAndDesc([string]$bgName, [XaaSAviTenantType]$tenantType)
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
    [Array] getAlertNameAndLevel([XaaSAviAlertLevel]$level)
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
    [string] getAlertConfigName([XaaSAviMonitoredElements]$element, [XaaSAviMonitoredStatus]$status)
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

        IN  : $friendlyNameOrBgId   -> Nom entré par l'utilisateur ou ID du Business Group
        IN  : $targetElement        -> Element cible pour le Virtual Service  

		RET : Nom du virtual service
	#>
    [string] getVirtualServiceName([string]$friendlyNameOrBgId, [XaaSAviTargetElement]$targetElement, [XaaSAviVipType]$vipType, [XaaSAviSSLProfile]$sslProfile)
    {
        return "{0}-{1}-{2}-{3}-{4}" -f `
            $friendlyNameOrBgId, 
            $this.getDeploymentTagShortname(), 
            $targetElement.toString().toLower(),
            $this.getVSVipTypeShortName($vipType),
            $this.getSSLProfileFirstLetter($sslProfile)
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom du pool pour un virtual service donné.

        IN  : $virtualServiceName     -> Nom du virtual service auquel le pool est lié.

		RET : Nom du pool
	#>
    [string] getPoolName([string]$virtualServiceName)
    {
        return "pool-{0}" -f $virtualServiceName
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie le nom de la VIP d'un Virtual Service

        IN  : $lbType               -> Type de load balancer  
        IN  : $virtualServiceName   -> Nom du virtual service auquel la VIP est liée.

		RET : Tableau avec:
                -> Nom de la VIP
                -> FQDN de la VIP
	#>
    [Array] getVSVipInfos([XaaSAviLBType]$lbType, [string]$virtualServiceName)
    {
        
        # Documentation sur le format ici: https://confluence.epfl.ch:8443/display/SIAC/%5BIaaS%5D+AVI+Networks  
              
        $vipName = "vsvip-{0}-NSX-T-{1}" -f `
                        $virtualServiceName, 
                        # Nom de l'environnement avec première lettre en majuscule
                        (Get-Culture).textInfo.toTitleCase($this.getEnvShortName())

        
        $testInfra = ""
        if($this.env -eq $global:TARGET_ENV__TEST)
        {
            $testInfra = "-t"
        }

        $vipFQDN = ""
        switch($lbType)
        {
            standard
            {
                $vipFQDN = switch($this.tenant)
                {
                    $global:VRA_TENANT__EPFL
                    {
                        "u{0}.lb{1}.xaas.epfl.ch" -f $virtualServiceName, $testInfra
                    }

                    $global:VRA_TENANT__ITSERVICES
                    {
                        "{0}.lb{1}.xaas.epfl.ch" -f $virtualServiceName, $testInfra
                    }

                    default 
                    {
                        Throw ("Incorrect tenant given '{0}'" -f $this.tenant)
                    }
                }
            }

            custom
            {
                $vipFQDN = "{0}.lb{1}.xaas.epfl.ch" -f $virtualServiceName, $testInfra
            }
        }
        
        
        return @($vipName, $vipFQDN)
    }


}