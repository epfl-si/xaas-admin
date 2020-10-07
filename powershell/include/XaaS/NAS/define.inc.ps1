<#
   BUT : Contient les constantes utilisées par la partie XaaS NAS

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

   ----------
   HISTORIQUE DES VERSIONS
   1.0 - Version de base
#>

$global:NAS_MAIL_TEMPLATE_FOLDER  = ([IO.Path]::Combine($global:RESOURCES_FOLDER, "mail-templates", "NAS"))

# Mail
$global:NAS_MAIL_SUBJECT_PREFIX = "NAS Service"