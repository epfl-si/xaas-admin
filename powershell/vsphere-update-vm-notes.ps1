<#
USAGES:
    vsphere-update-vm-notes.ps1 -targetEnv prod|test|dev
#>
<#
    BUT 		: Met à jour les notes des VM en fonction de:
                    - l'état des VM Tools
                    - la date du dernier backup si la VM est backupée

	DATE 		: Mai 2019
	AUTEUR 	: Lucien Chaboudez

	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>

param ( [string]$targetEnv)


# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ConfigReader.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "NotificationMail.inc.ps1"))

# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))


# Chargement des fichiers de configuration
$configVSphere = [ConfigReader]::New("config-vsphere.json")
$configGlobal = [ConfigReader]::New("config-global.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Texte qui sépare les notes
$VM_NOTE_SEPARATOR="## VM Infos ##"
# Texte qui séparait les notes avant, utilisé pour "migrer" d'un texte de séparation à un autre
$VM_NOTE_SEPARATOR_OLD="## VMware Tools ##"



# -------------------------------------------- FONCTIONS ---------------------------------------------------

<#
-------------------------------------------------------------------------------------
    BUT : Renvoie la note mise à jour avec les informations à ajouter

    IN  : $vm    -> VM à mettre à jour
#>
function getUpdatedNote()
{
    param([PSObject]$vm)

    $note = $vm.Notes

    # Si la note contient déjà les détails, 
    if($note -match $VM_NOTE_SEPARATOR)
    {
        # on supprime ceux-ci 
        $note = $note -replace ("\n?{0}[\n\d\s\w:\-_,\.\+]*" -f $VM_NOTE_SEPARATOR)
    }
    elseif($note -match $VM_NOTE_SEPARATOR_OLD)
    {
        # on supprime ceux-ci 
        $note = $note -replace ("\n?{0}[\n\d\s\w:\-_,\.\+]*" -f $VM_NOTE_SEPARATOR_OLD)
    }


    # On recherche la date du dernier backup 
    $lastBackupDate = "No backup found"
    $lastBackupInfos = $vm.CustomFields | Where-Object { $_.Key -eq "NB_LAST_BACKUP"}
    if($null -ne $lastBackupInfos)
    {
        $lastBackupDate = $lastBackupInfos.Value.Split(",")[0]
    }

    # Définition d'un texte de statut en fonction de celui renvoyé par vSphere
    $status = Switch ($vm.Guest.ExtensionData.ToolsVersionStatus)
    {
        "guestToolsUnmanaged"       { "Guest Managed" }
        "guestToolsNeedUpgrade"     { "Upgrade available" }
        "guestToolsNotInstalled"    { "Not installed" }
        "guestToolsCurrent"         { "Up-to-date" }
    }

    # Ajout des détails
    return ("{0}`n{1}`nTools version: {2}`nTools status: {3}`nLast backup: {4}" -f $note, $VM_NOTE_SEPARATOR, $vm.Guest.ToolsVersion, $status, $lastBackupDate).trim()
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logPath = @('vsphere', ('update-VM-notes-{0}' -f $targetEnv.ToLower()))
    $logHistory = [LogHistory]::new($logPath, $global:LOGS_FOLDER, 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$PSScriptRoot", "include", "ArgsPrototypeChecker.inc.ps1"))

    $logHistory.addLine(("Script executed as '{0}' with following parameters: `n{1}" -f $env:USERNAME, ($PsBoundParameters | ConvertTo-Json)))
    
    # Objet pour pouvoir envoyer des mails de notification
	$valToReplace = @{
		targetEnv = $targetEnv
	}
	$notificationMail = [NotificationMail]::new($configGlobal.getConfigValue(@("mail", "admin")), $global:MAIL_TEMPLATE_FOLDER, `
												($global:VRA_MAIL_SUBJECT_PREFIX_NO_TENANT -f $targetEnv), $valToReplace)

	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
    $counters.add('VMNotesUpdated', '# VM notes updated')
    $counters.add('VMNotesOK', '# VM notes OK')

    # Chargement des modules PowerCLI pour pouvoir accéder à vSphere.
    loadPowerCliModules

    # Pour éviter que le script parte en erreur si le certificat vCenter ne correspond pas au nom DNS primaire.
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false | Out-Null

    # Pour éviter la demande de rejoindre le programme de "Customer Experience"
    Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false | Out-Null

    # Connexion au serveur vSphere

    $credSecurePwd = $configVSphere.getConfigValue(@($targetEnv, "password")) | ConvertTo-SecureString -AsPlainText -Force
    $credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $configVSphere.getConfigValue(@($targetEnv, "user")), $credSecurePwd	
            
    $connectedvCenter = Connect-VIServer -Server $configVSphere.getConfigValue(@($targetEnv, "server")) -Credential $credObject

    $logHistory.addLineAndDisplay("Getting VMs...")

    # Parcours des VM existantes
    Foreach($vm in get-vm)
    {

        $logLine = ("VM {0}..." -f $vm.Name)

        # Génération de la note 
        $newNote = (getUpdatedNote -vm $vm)

        # S'il faut mettre à jour la note, 
        if($vm.Notes -ne $newNote)
        {
            $logHistory.addLineAndDisplay("{0} Updating" -f $logLine)

            Set-Vm $vm -Notes $newNote -Confirm:$false | Out-Null
            $counters.inc('VMNotesUpdated')
        }
        else # Pas besoin de mettre à jour. 
        {
            $logHistory.addLineAndDisplay("{0} Notes OK" -f $logLine)
            $counters.inc('VMNotesOK')
        }
        
    }# FIN BOUCLE de parcours des VM existantes


    $logHistory.addLineAndDisplay($counters.getDisplay("Counters summary"))

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


# Déconnexion du serveur vCenter
Disconnect-VIServer  -Server $connectedvCenter -Confirm:$false 