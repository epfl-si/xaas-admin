<#
   BUT : Contient les constantes utilisées par les différents scripts accédant au NetApp
   
   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2014

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>


$global:FILES_TO_PUSH_FOLDER        = ([IO.Path]::Combine("$PSScriptRoot", "..", "..", "filesToPush"))
$global:SSH_FOLDER                  = ([IO.Path]::Combine($global:DATA_FOLDER, "ssh"))
$global:MYNAS_MAIL_TEMPLATE_FOLDER  = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "mail-templates", "MyNAS"))
$global:MYNAS_RESULTS_FOLDER        = ([IO.Path]::Combine($global:RESULTS_FOLDER, "mynas"))

# URL du site web
$global:WEBSITE_URL_MYNAS="https://mynas.epfl.ch/"

# SSH
$global:MYNAS_SSH_KEY  = ([IO.Path]::Combine($global:SSH_FOLDER, "sshkey-wwwmynas.ppk"))
$global:MYNAS_SSH_USER = "wwwmynas"

# Mail
$global:MYNAS_MAIL_SUBJECT_PREFIX = "MyNAS Service"
