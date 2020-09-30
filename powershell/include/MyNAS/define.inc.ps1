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


# Adresse IP du cluster Collaboratif
# FIXME: CECI VA ÊTRE REMPLACE PAR DES INFOS DANS LE FICHIER DE CONFIG JSON PAR LA SUITE
$global:CLUSTER_COLL_IP="128.178.101.99"

# URL du site web
$global:WEBSITE_URL_MYNAS="https://mynas.epfl.ch/"

# SSH
$global:MYNAS_SSH_KEY  = ([IO.Path]::Combine($global:SSH_FOLDER, "sshkey-wwwmynas.ppk"))
$global:MYNAS_SSH_USER = "wwwmynas"

# Sécuristation des e-mails: utilisation de noreply@epfl.ch
# FIXME: UTILISER L'ENVOI DE MAIL COMME POUR LES SCRIPTS IAAS
$global:FROM_MAIL="noreply+sanas-mon-2@epfl.ch"
$global:ADMIN_MAIL="dit-nas-admins@groupes.epfl.ch"
#$global:ADMIN_MAIL="lucien.chaboudez@epfl.ch"

# Mail
$global:MYNAS_MAIL_SUBJECT_PREFIX = "MyNAS Service"
