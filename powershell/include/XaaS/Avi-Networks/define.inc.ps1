<#
   BUT : Contient les constantes utilisées par la partie XaaS Avi Networks

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021

#>

# Les niveaux d'alerte pour les notifications mail
enum XaaSAviNetworksAlertLevel {
   High
   Medium
}


$global:XAAS_AVI_NETWORKS_USER_ROLE_NAME = "Application-Only"

$global:XAAS_AVI_NETWORKS_TENANT_TYPE = "ch.epfl.avi.tenant.type"