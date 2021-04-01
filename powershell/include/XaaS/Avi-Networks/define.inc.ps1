<#
   BUT : Contient les constantes utilisées par la partie XaaS Avi Networks

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2021

#>

# Types de tenants possibles
enum XaaSAviNetworksTenantType
{
   Development
   Test
   Production
}

# Les niveaux d'alerte pour les notifications mail
enum XaaSAviNetworksAlertLevel {
	High
	Medium
 }
 
 # Nom des éléments monitorés. Seront utilisés pour générer les bons noms de fichiers JSON pour les requêtes
 enum XaaSAviNetworksMonitoredElements {
	VirtualService
	Pool
 }
 
 # Nom des status monitorés. Seront utilisés pour générer les bons noms de fichiers JSON pour les requêtes
 enum XaaSAviNetworksMonitoredStatus {
	Up
	Down
 }


$global:XAAS_AVI_NETWORKS_USER_ROLE_NAME = "Application-Only"

$global:XAAS_AVI_NETWORKS_TENANT_TYPE = "ch.epfl.avi.tenant.type"

$global:XAAS_AVI_NETWORKS_NSXT_CLOUD = "CLOUD_NSXT"