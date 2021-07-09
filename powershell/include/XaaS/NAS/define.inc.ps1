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


# lettre à utiliser pour monter le drive réseau pour initialiser les droits
$global:XAAS_NAS_TEMPORARY_DRIVE = "Z"

# Types de volumes qu'on peut avoir sur le NAS
# Si on appelle la fonction "ToString()" sur l'un d'eux, ça doit renvoyer ce qui est passé en paramètre du script "endpoint"
Enum XaaSNASVolType {
   col # Collaboratif
   app # Applicatif
}

# Identifiant du type dynamique dans vRA
$global:VRA_XAAS_NAS_DYNAMIC_TYPE = "NAS_Volume"
$global:VRA_XAAS_NAS_CUSTOM_PROPERTY_WEBDAV_ACCESS = "webdavAccess"

# Limites
$global:MAX_VOL_PER_UNIT = 999