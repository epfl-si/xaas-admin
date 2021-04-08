<#
USAGES:
    tools-send-its-windows-vm-list.ps1 -targetEnv prod|test|dev -mail <mail>
#>
<#
    BUT 		: Script permettant de récupérer la liste des VM qui sont sur ITServices et de les envoyer
                    par mail à une adresse donnée
                  

	DATE 	: Avril 2021
    AUTEUR 	: Lucien Chaboudez
    

#>
param ( [string]$targetEnv, 
        [string]$mail)

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

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "APIUtils.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "vRAAPI.inc.ps1"))


# Chargement des fichiers de configuration
$configGlobal = [ConfigReader]::New("config-global.json")
$configVra = [ConfigReader]::New("config-vra.json")

$targetTenant = "ITServices"

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logPath = @('tools', ('send-its-vm-list-{0}' -f $targetEnv.ToLower()))
    $logHistory = [LogHistory]::new($logPath, $global:LOGS_FOLDER, 120)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # Objet pour pouvoir envoyer des mails de notification
    $valToReplace = @{
        targetEnv = $targetEnv
    }

    $notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
                                                ($global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT -f $targetEnv), $valToReplace)

    

    $vra = [vRAAPI]::new($configVra.getConfigValue(@($targetEnv, "infra", "server")), 
                        $targetTenant, 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "user")), 
                        $configVra.getConfigValue(@($targetEnv, "infra", $targetTenant, "password")))

    # Fichier de sortie pour les informations extraites
    $outFolder = ([IO.Path]::Combine($global:RESULTS_FOLDER, "ITS-VM-List"))
    if(!(Test-Path $outFolder))
    {
        New-Item -ItemType Directory -path $outFolder | Out-Null
    }
    $outFile = ([IO.Path]::Combine($outFolder, "its-vm-list.csv"))

    # Définition des noms des colonnes
    $cols = @("VM Name",
            "Svc longName",
            "BG snowId",
            "Business Group")

    $cols -join ";" | Out-File $outFile -Encoding:utf8


    $logHistory.addLineAndDisplay("Getting BG List...")

    $bgList = $vra.getBGList()

    $vmFound = $false
    Foreach($bg in $bgList)
    {
        $logHistory.addLineAndDisplay(("-> Processing BG '{0}'..." -f $bg.name))

        # Recherche de l'ID
        $bgId = (getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID)
        $logHistory.addLineAndDisplay(("-> Custom ID is '{0}'" -f $bgId))

        $logHistory.addLineAndDisplay(("-> Getting Item List for BG '{0}'..." -f $bg.name))

        $vmList = $vra.getBGItemList($bg, $global:VRA_ITEM_TYPE_VIRTUAL_MACHINE)

        # Parcours des VM
        ForEach($vm in $vmList)
        {
            $logHistory.addLineAndDisplay(("--> VM '{0}'" -f $vm.name))

            # Récupération du Blueprint pour déterminer si c'est une VM Windows ou pas
            $bluePrint = getvRAObjectCustomPropValue -object $vm -customPropName "VirtualMachine.Cafe.Blueprint.Name"

            if($bluePrint -like "*Windows*")
            {
                $logHistory.addLineAndDisplay("--> Windows VM")

                $values = @($vm.name,
                        $bg.description,
                        $bgId,
                        $bg.name)

                $values -join ";" | Out-File $outFile -Encoding:utf8 -Append

                $vmFound = $true
            }
            else
            {
                $logHistory.addLineAndDisplay("--> NOT a Windows VM")
            }
            

        } # FIN BOUCLE de parcours des VM

    } # FIN BOUCLE de parcours des Business Groups
    
    if($vmFound)
    {
        $logHistory.addLineAndDisplay(("Sending result mail to '{0}'..." -f $mail))

        $mailFrom = ("noreply+{0}" -f $configGlobal.getConfigValue(@("mail", "admin")))
        $mailSubject = "ITServices per BG VM List"
        $mailMessage = "Bonjour,<br><br>Voici la liste des VM qui existent actuellement dans le tenant ITServices.<br><br>Salutations<br><br>vRA Bot"

        Send-MailMessage -From $mailFrom -To $mail -Subject $mailSubject -Attachments $outFile `
                        -Body $mailMessage -BodyAsHtml:$true -SmtpServer "mail.epfl.ch" -Encoding:UTF8
    }

    
}
catch
{
    
    # Récupération des infos
    $errorMessage = $_.Exception.Message
    $errorTrace = $_.ScriptStackTrace

    $logHistory.addErrorAndDisplay(("An error occured: `nError: {0}`nTrace: {1}" -f $errorMessage, $errorTrace))
    
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

