<#
USAGES:
    vsphere-update-vm-notes-with-tools-version.ps1 -targetEnv prod|test|dev
#>
<#
	BUT 		: Met à jour les notes des VM en fonction de l'état des VM Tools

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

<# On enregistrer l'endroit où le script courant se trouve pour pouvoir effectuer l'import des autres fichiers.
On fait ceci au lieu d'utiliser $PSScriptRoot car la valeur de ce dernier peut changer si on importe un module (Import-Module) dans
un des fichiers inclus via ". <pathToFile>" #>
$SCRIPT_PATH = $PSScriptRoot

# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "LogHistory.inc.ps1"))
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ConfigReader.inc.ps1"))
# Fichiers propres au script courant 
. ([IO.Path]::Combine("$SCRIPT_PATH", "include", "functions-vsphere.inc.ps1"))


# Chargement des fichiers de configuration
$configVSphere = [ConfigReader]::New("config-vsphere.json")
$configGlobal = [ConfigReader]::New("config-global.json")


# -------------------------------------------- CONSTANTES ---------------------------------------------------

# Texte qui sépare les notes
$VM_NOTE_SEPARATOR="## VMware Tools ##"


# -------------------------------------------- FONCTIONS ---------------------------------------------------

function getUpdatedNote()
{
    param([PSObject]$vm)

    $note = $vm.Notes

    # Si la note contient déjà les détails, 
    if($note -match $VM_NOTE_SEPARATOR)
    {
        # on supprime ceux-ci 
        $note = $note -replace ("\n?{0}[\n\d\s\w:\-_,\.]*" -f $VM_NOTE_SEPARATOR)
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
    return ("{0}`n{1}`nVersion: {2}`nStatus: {3}" -f $note, $VM_NOTE_SEPARATOR, $vm.Guest.ToolsVersion, $status).trim()
}


# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ---------------------------------------------- PROGRAMME PRINCIPAL ---------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------
# ----------------------------------------------------------------------------------------------------------------------

try
{

    # Création de l'objet pour logguer les exécutions du script (celui-ci sera accédé en variable globale même si c'est pas propre XD)
    $logHistory = [LogHistory]::new('vsphere-update-VM-notes-with-Tools-version', (Join-Path $SCRIPT_PATH "logs"), 30)
    
    # On commence par contrôler le prototype d'appel du script
    . ([IO.Path]::Combine("$SCRIPT_PATH", "include", "ArgsPrototypeChecker.inc.ps1"))

	# Création d'un objet pour gérer les compteurs (celui-ci sera accédé en variable globale même si c'est pas propre XD)
	$counters = [Counters]::new()

	# Tous les Tenants
    $counters.add('VMNotesUpdated', '# VM notes updated')
    $counters.add('VMNotesOK', '# VM notes OK')

    # Chargement des modules PowerCLI pour pouvoir accéder à vSphere.
    loadPowerCliModules

    # Pour éviter que le script parte en erreur si le certificat vCenter ne correspond pas au nom DNS primaire. On met le résultat dans une variable
    # bidon sinon c'est affiché à l'écran.
    $dummy = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

    # Pour éviter la demande de rejoindre le programme de "Customer Experience"
    $dummy = Set-PowerCLIConfiguration -Scope User -ParticipateInCEIP $false -Confirm:$false

    # Connexion au serveur vSphere

    $credSecurePwd = $configVSphere.getConfigValue($targetEnv, "password") | ConvertTo-SecureString -AsPlainText -Force
    $credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $configVSphere.getConfigValue($targetEnv, "user"), $credSecurePwd	
            
    $connectedvCenter = Connect-VIServer -Server $configVSphere.getConfigValue($targetEnv, "server") -Credential $credObject

    $logHistory.addLineAndDisplay("Getting VMs...")

    # Parcours des VM existantes
    Foreach($vm in get-vm )
    {

        $logLine = ("VM {0}..." -f $vm.Name)

        # Génération de la note 
        $newNote = (getUpdatedNote -vm $vm)

        # S'il faut mettre à jour la note, 
        if($vm.Notes -ne $newNote)
        {
            $logHistory.addLineAndDisplay("{0} Updating" -f $logLine)

            $dummy = Set-Vm $vm -Notes $newNote -Confirm:$false
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
	
	# Envoi d'un message d'erreur aux admins 
	$mailSubject = getvRAMailSubject -shortSubject ("Error in script '{0}'" -f $MyInvocation.MyCommand.Name) -targetEnv $targetEnv -targetTenant $targetTenant
	$mailMessage = getvRAMailContent -content ("<b>Computer:</b> {3}<br><b>Script:</b> {0}<br><b>Parameters:</b>{4}<br><b>Error:</b> {1}<br><b>Trace:</b> <pre>{2}</pre>" -f `
	$MyInvocation.MyCommand.Name, $errorMessage, [System.Net.WebUtility]::HtmlEncode($errorTrace), $env:computername, (formatParameters -parameters $PsBoundParameters ))

	sendMailTo -mailAddress $configGlobal.getConfigValue("mail", "admin") -mailSubject $mailSubject -mailMessage $mailMessage
}


# Déconnexion du serveur vCenter
Disconnect-VIServer  -Server $connectedvCenter -Confirm:$false 