<#
    BUT : Contient les informations sur l'environnement NSX utilisées par les différents scripts 

    AUTEUR : Lucien Chaboudez
    DATE   : Juin 2019

    ----------
    HISTORIQUE DES VERSIONS
    1.0 - Version de base
#>

# Serveurs en fonction de l'environnement
$global:NSX_SERVER_LIST = @{}
$global:NSX_SERVER_LIST[$global:TARGET_ENV__DEV]  = ""
$global:NSX_SERVER_LIST[$global:TARGET_ENV__TEST] = ""
$global:NSX_SERVER_LIST[$global:TARGET_ENV__PROD] = ""

# ------------------------------------------------
# Utilisateur (user local donc le même pour tous les environnements)
$global:NSX_ADMIN_USERNAME = ""

# ------------------------------------------------
# Mot de passe
# Définis par environnement 
$global:NSX_PASSWORD_LIST = @{}
$global:NSX_PASSWORD_LIST[$global:TARGET_ENV__DEV]  = ""
$global:NSX_PASSWORD_LIST[$global:TARGET_ENV__TEST] = ""
$global:NSX_PASSWORD_LIST[$global:TARGET_ENV__PROD] = ""