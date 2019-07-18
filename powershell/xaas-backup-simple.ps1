# Inclusion des fichiers nécessaires (génériques)
. ([IO.Path]::Combine("$PSScriptRoot", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "LogHistory.inc.ps1"))
# Fichiers propres au script courant 
. ([IO.Path]::Combine("$PSScriptRoot", "include", "functions-vsphere.inc.ps1"))

# Chargement des fichiers pour API REST
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPI.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "RESTAPICurl.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "REST", "NetBackupAPI.inc.ps1"))

# Chargement des fichiers de configuration
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config", "config-mail.inc.ps1"))
loadConfigFile([IO.Path]::Combine("$PSScriptRoot", "config", "config-xaas-backup.inc.ps1"))

$vmName = "itstxaas0436"

# Chargement des modules PowerCLI pour pouvoir accéder à vSphere.
loadPowerCliModules

# Pour éviter que le script parte en erreur si le certificat vCenter ne correspond pas au nom DNS primaire. On met le résultat dans une variable
# bidon sinon c'est affiché à l'écran.
$dummy = Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false


# On encrypte le mot de passe
$credSecurePwd = $global:XAAS_BACKUP_VCENTER_PASSWORD_LIST[$targetEnv] | ConvertTo-SecureString -AsPlainText -Force
$credObject = New-Object System.Management.Automation.PSCredential -ArgumentList $global:XAAS_BACKUP_VCENTER_USER_LIST[$targetEnv], $credSecurePwd

# Connexion au serveur vSphere.
# On passe par le paramètre -credential car sinon, on a des erreurs avec Get-AssignmentTag et Get-Tag, ou peut-être tout simplement avec les commandes dans
# lesquelles on faite un | pour passer à la suivante.
$connectedvCenter = Connect-VIServer -Server $global:XAAS_BACKUP_VCENTER_SERVER_LIST[$targetEnv] -credential $credObject


$vm = Get-VM -Server $vSphere -Name $vmName
$tagList = Get-TagAssignment -Server $vSphere -Entity $vm
    