<#
USAGES:
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action create -svm <svm> 
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action resize -sizeGB <sizeGB>
    xaas-nas-endpoint.ps1 -targetEnv prod|test|dev -targetTenant test|itservices|epfl -action getsize [-volName <volName>]
#>
<#
    BUT 		: Script appelé via le endpoint défini dans vRO. Il permet d'effectuer diverses
                  opérations en rapport avec le service NAS en tant que XaaS.
                  

	DATE 	: Septembre 2020
    AUTEUR 	: Lucien Chaboudez
    
    VERSION : 1.00

    REMARQUES : 
    - Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy via Set-ExecutionPolicy. 
        Normalement, si on met la valeur "Unrestricted", cela suffit à correctement faire tourner le script. 
        Mais il se peut que si le script se trouve sur un share réseau, l'exécution ne passe pas et qu'il 
        soit demandé d'utiliser "Unblock-File" pour permettre l'exécution. Ceci ne fonctionne pas ! A la 
        place il faut à nouveau passer par la commande Set-ExecutionPolicy mais mettre la valeur "ByPass" 
        en paramètre.

    FORMAT DE SORTIE: Le script utilise le format JSON suivant pour les données qu'il renvoie.
    {
        "error": "",
        "results": []
    }

    error -> si pas d'erreur, chaîne vide. Si erreur, elle est ici.
    results -> liste avec un ou plusieurs éléments suivant ce qui est demandé.

    Confluence :
        Opérations S3 - TODO: page a créer
        Documentation - https://confluence.epfl.ch:8443/pages/viewpage.action?pageId=99188910                                

#>
param([string]$targetEnv, 
      [string]$targetTenant, 
      [string]$action, 
      [string]$svm,
      [string]$volName,
      [int]$sizeGB)

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "XaaS", "functions.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))

# Chargement des fichiers propres au NAS NetApp
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "XaaS", "NAS", "NetAppAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configNAS = [ConfigReader]::New("config-xaas-nas.json")

# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Liste des actions possibles
$ACTION_CREATE              = "create"
$ACTION_DELETE              = "delete"
$ACTION_RESIZE              = "resize"
$ACTION_GET_SIZE            = "getsize"


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{
    # Création de l'objet pour l'affichage 
    $output = getObjectForOutput

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('xaas-nas', (Join-Path $PSScriptRoot "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    # Ajout d'informations dans le log
    $logHistory.addLine("Script executed with following parameters: `n{0}" -f ($PsBoundParameters | ConvertTo-Json))
    
    # On met en minuscules afin de pouvoir rechercher correctement dans le fichier de configuration (vu que c'est sensible à la casse)
    $targetEnv = $targetEnv.ToLower()
    $targetTenant = $targetTenant.ToLower()

    $netapp = $null

    # Parcours des serveurs qui sont définis
    $configNAS.getConfigValue($targetEnv, "serverList") | ForEach-Object {

        if($null -eq $netapp)
        {
            # Création de l'objet pour communiquer avec le NAS
            $netapp = [NetAppAPI]::new($_, $configNAS.getConfigValue($targetEnv, "user"), $configNAS.getConfigValue($targetEnv, "password"))
        }
        else
        {
            $netapp.addServer($_)
        }
    }# Fin boucle de parcours des serveurs qui sont définis


    # Objet pour pouvoir envoyer des mails de notification
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue("mail", "admin"), $global:MAIL_TEMPLATE_FOLDER, $targetEnv, $targetTenant)


    # En fonction de l'action demandée
    switch ($action)
    {

        # -- Création d'un nouveau Volume 
        $ACTION_CREATE {

           

        }# FIN Action Create


        # -- Effacement d'un Volume
        $ACTION_DELETE {

        }# FIN Action Delete


        # -- Resize d'un volume
        $ACTION_RESIZE {

            $logHistory.addLine( ("Getting Volume {0}" -f $volName) )
            $vol = $netapp.getVolumeByName($volName)

            # Si volume pas trouvé
            if($null -eq $vol)
            {
                $output.error = ("Volume {0} doesn't exists" -f $volName)
                $logHistory.addLine($output.error)
            }
            else
            {
                $logHistory.addLine( ("Resizing Volume {0} to {1} GB" -f $volName, $sizeGB) )
                $netapp.resizeVolume($vol.uuid, $sizeGB)
            }

        }# FIN Action resize


        # -- Renvoie la taille d'un Volume
        $ACTION_GET_SIZE {

            if($volName -ne "")
            {
                $volNameList = @($volName)
            }
            else
            {
                $volNameList = $netapp.getVolumeList() | Select-Object -ExpandProperty name
            }

            # Parcours des volumes dont on veut la taille
            $volNameList | ForEach-Object { 

                $logHistory.addLine( ("Getting size for Volume {0}" -f $_) )
                $vol = $netapp.getVolumeByName($_)

                $output.results += @{
                    volName = $vol.name
                    sizeGB = $vol.space.size / 1024 / 1024 / 1024
                }
            }

        }# FIN Action Delete

        

    }

    $logHistory.addLine("Script execution done!")


    # Affichage du résultat
    displayJSONOutput -output $output

    # Ajout du résultat dans les logs 
    $logHistory.addLine(($output | ConvertTo-Json -Depth 100))

}
catch
{
	# Récupération des infos
	$errorMessage = $_.Exception.Message
	$errorTrace = $_.ScriptStackTrace

    # Ajout de l'erreur et affichage
    $output.error = "{0}`n`n{1}" -f $errorMessage, $errorTrace
    displayJSONOutput -output $output

	$logHistory.addError(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
    # On ajoute les retours à la ligne pour l'envoi par email, histoire que ça soit plus lisible
    $errorMessage = $errorMessage -replace "`n", "<br>"

	# Création des informations pour l'envoi du mail d'erreur
	$valToReplace = @{	
        scriptName = $MyInvocation.MyCommand.Name
        computerName = $env:computername
        parameters = (formatParameters -parameters $PsBoundParameters )
        error = $errorMessage
        errorTrace =  [System.Net.WebUtility]::HtmlEncode($errorTrace)
    }

    # Envoi d'un message d'erreur aux admins 
    $notificationMail.send("Error in script '{{scriptName}}'", "global-error", $valToReplace) 
}