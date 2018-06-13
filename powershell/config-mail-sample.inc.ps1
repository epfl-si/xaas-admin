<#
    BUT : Contient les informations sur les adresses mail utilisées par les différents scripts 
          et ceci pour les différents environnements existants

    DEPENDANCES : Ce script a besoin de "define.inc.ps1" pour fonctionner correctement

    AUTEUR : Lucien Chaboudez
    DATE   : Février 2018

    ----------
    HISTORIQUE DES VERSIONS
    1.0 - Version de base
#>

# Adresse mail des administrateurs, utilisée pour envoyer les mails d'information depuis les scripts
$global:ADMIN_MAIL_ADDRESS=""

# Adresse mail par défaut à laquelle envoyer les mails de "capacity alert"
$global:CAPACITY_ALERT_DEFAULT_MAIL = ""