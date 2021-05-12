
<#
USAGES:
    tools-sync-static-mac.ps1 -targetEnv prod|test|dev -targetTenant epfl|itservices|research
#>
<#
    BUT 		: Script permettant de mettre à jour les adresses MAC statiques dans la DB MSSQL
                    
	DATE 	: Mai 2021
    AUTEUR 	: Lucien Chaboudez
    
    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

#>
param([string]$targetEnv, 
      [string]$targetTenant)

. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "EPFLLDAP.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SecondDayActions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "SQLDB.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vSphereAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal   = [ConfigReader]::New("config-global.json")
$configVra      = [ConfigReader]::New("config-vra.json")
$configVSphere  = [ConfigReader]::New("config-vsphere.json")


# Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
$logHistory = [LogHistory]::new(@('tools','sync-static-mac'), $global:LOGS_FOLDER, 120)
    
# On commence par contrôler le prototype d'appel du script
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

# Ajout d'informations dans le log
$logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))

# On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
$targetEnv = $targetEnv.ToLower()
$targetTenant = $targetTenant.ToLower()


$vsphereApi = [vSphereAPI]::new($configVSphere.getConfigValue(@($targetEnv, "server")), 
                                    $configVSphere.getConfigValue(@($targetEnv , "user")), 
									$configVSphere.getConfigValue(@($targetEnv, "password")))


$vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                $targetTenant, 
                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

# Pour accéder à la base de données
$sqldb = [SQLDB]::new([DBType]::MSSQL, 
                        $configVra.getConfigValue(@($targetEnv, "db", "host")),
                        $configVra.getConfigValue(@($targetEnv, "db", "dbName")),
                        $configVra.getConfigValue(@($targetEnv, "db", "user")), 
                        $configVra.getConfigValue(@($targetEnv, "db", "password")),
                        $configVra.getConfigValue(@($targetEnv, "db", "port")), 
                        $true)

$counters = [Counters]::new()                        

$counters.add("nbBG", "# Processed BG")
$counters.add("nbVM", "# Processed VM")
$counters.add("nbVMNics", "# Processed VM NICs")
$counters.add("nbDBUpdates", "# Updates in DB")

$bgList = $vra.getBGList()

# Parcours des BG
Foreach($bg in $bgList)
{
    $counters.inc('nbBG')
    
    $logHistory.addLineAndDisplay(("Processing BG '{0}'..." -f $bg.name))
    $vmList = $vra.getBGItemList($bg, $global:VRA_ITEM_TYPE_VIRTUAL_MACHINE)

    # Parcours des VM du BG
    ForEach($vm in $vmList)
    {
        $counters.inc('nbVM')
        $logHistory.addLineAndDisplay(("> VM {0}" -f $vm.name))
        
        # Récupération de la liste des NICs de la VM
        $nicList = $vsphereApi.getVMFullDetails($vm.name).nics

        # Parcours des NICs de la VM
        Foreach($nic in $nicList)
        {
            # Les informations étant dans $nic.value, on réaffecte simplement la variable
            $nic = $nic.value
            $counters.inc('nbVMNics')
            $logHistory.addLineAndDisplay((">> {0}" -f $nic.mac_address))
            # Recherche de l'entrée sur l'adresse MAC en regardant aussi si le format est correct.
            $request = "SELECT * FROM [xaas_prod].[dbo].[myvm_static_mac] WHERE [myvm_static_mac_address] LIKE '{0}' AND [myvm_static_mac_used_by] NOT LIKE '%:{1}'" -f $nic.mac_address, $vm.name
            
            $macAddressInfos = $sqldb.execute($request)

            # Si résultat, c'est que "incorrect"
            if($macAddressInfos.count -gt 0)
            {
                # VM IaaS
                if($vm.name -match '.+[0-9]{4,4}')
                {
                    $prefix = "IaaSVM"
                }
                else
                {
                    $prefix = "LegacyMyVM"
                }
                $usedBy = "{0}:{1}" -f $prefix, $vm.name
                $request = "UPDATE [xaas_prod].[dbo].[myvm_static_mac] SET myvm_static_mac_used_by = '{0}' WHERE [myvm_static_mac_address] LIKE '{1}'" -f $usedBy, $nic.mac_address
                $logHistory.addLineAndDisplay((">> Incorrect found ({0} >> {1}), updating..." -f $macAddressInfos.myvm_static_mac_used_by, $usedBy))

                $sqldb.execute($request)

                $counters.inc('nbDBUpdates')

            }# FIN si les infos dans la DB ne sont pas à jour

        }# FIN BOUCLE de parcours des NICs de la VM

    }# FIN BOUCLE de parcours des VM du BG

}# FIN BOUCLE de parcours des BG

$logHistory.addLineAndDisplay(($counters.getDisplay("Counters summary")))

$sqldb.disconnect()
$vra.disconnect()
$vsphereApi.disconnect()