<#
    BUT : Contient les informations sur l'environnement vRA utilisées par les différents scripts et ceci pour les différents
		   environnements existants

    DEPENDANCES : Ce script a besoin de "define.inc.ps1" pour fonctionner correctement

    AUTEUR : Lucien Chaboudez
    DATE   : Février 2018

    ----------
    HISTORIQUE DES VERSIONS
    1.0 - Version de base
    1.1 - Ajout de la liste des serveurs, passage des éléments en $global:
#>

# Serveurs en fonction de l'environnement
$global:VRA_SERVER_LIST = @{}
$global:VRA_SERVER_LIST[$global:TARGET_ENV_DEV]	 = ""
$global:VRA_SERVER_LIST[$global:TARGET_ENV_TEST] = ""
$global:VRA_SERVER_LIST[$global:TARGET_ENV_PROD] = ""

# ------------------------------------------------
# Utilisateurs par tenant
# Les noms d'utilisateur doivent être au format <username>@<domain> sinon ça ne passe pas.
$global:VRA_USER_LIST = @{}
$global:VRA_USER_LIST[$global:VRA_TENANT_DEFAULT]	 = ""
$global:VRA_USER_LIST[$global:VRA_TENANT_EPFL]	     = ""
$global:VRA_USER_LIST[$global:VRA_TENANT_ITSERVICES] = ""


# ------------------------------------------------
# Mot de passe
# Définis par environnement puis par tenant
$global:VRA_PASSWORD_LIST = @{}
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_DEV] = @{}
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_DEV][$global:VRA_TENANT_DEFAULT]    = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_DEV][$global:VRA_TENANT_EPFL]       = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_DEV][$global:VRA_TENANT_ITSERVICES] = ""


$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_TEST]	= @{}
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_TEST][$global:VRA_TENANT_DEFAULT]    = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_TEST][$global:VRA_TENANT_EPFL]       = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_TEST][$global:VRA_TENANT_ITSERVICES] = ""


$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_PROD]	= @{}
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_PROD][$global:VRA_TENANT_DEFAULT]    = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_PROD][$global:VRA_TENANT_EPFL]       = ""
$global:VRA_PASSWORD_LIST[$global:TARGET_ENV_PROD][$global:VRA_TENANT_ITSERVICES] = ""

