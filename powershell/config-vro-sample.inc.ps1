<#
    BUT : Contient les informations sur l'environnement vRO utilisées par les différents scripts et ceci pour les différents
		   environnements existants

    DEPENDANCES : Ce script a besoin de "define.inc.ps1" pour fonctionner correctement

    AUTEUR : Lucien Chaboudez
    DATE   : Juin 2018

    ----------
    HISTORIQUE DES VERSIONS
    1.0 - Version de base
#>

# ID de 'cafe' en fonction de l'environnement
# Peut être trouvé avec la commande suivante passée sur la console SSH de l'appliance vRA :
# grep -i cafe_cli= /etc/vcac/solution-users.properties | sed -e 's/cafe_cli=//'
$global:VRA_SERVER_LIST = @{}
$global:VRA_SERVER_LIST[$global:TARGET_ENV_DEV]	 = ""
$global:VRA_SERVER_LIST[$global:TARGET_ENV_TEST] = ""
$global:VRA_SERVER_LIST[$global:TARGET_ENV_PROD] = ""