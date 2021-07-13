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

# Type qu'on peut avoir pour les Vip des Virtual Services
enum XaaSAviNetworksVipType {
   Private
   Public
}

# Niveau de sécurité SSL
enum XaaSAviNetworksSSLProfile {
   Security
   Compatibility
}

# Element "cible" qui est derrière un Virtual Service
enum XaaSAviNetworksTargetElement {
   VM
   TKGI
}

# Types d'algorithmes de load balancer supportés
enum XaaSAviNetworksLBAlgorithm
{
   LB_ALGORITHM_LEAST_CONNECTIONS
   LB_ALGORITHM_ROUND_ROBIN
   LB_ALGORITHM_FASTEST_RESPONSE
   LB_ALGORITHM_CONSISTENT_HASH
   LB_ALGORITHM_LEAST_LOAD
   LB_ALGORITHM_FEWEST_SERVERS
}

# Algoritme de Hash si on choisi LB_ALGORITHM_CONSISTENT_HASH
enum XaaSAviNetworksLBAlgorithmHash
{
   LB_ALGORITHM_CONSISTENT_HASH_SOURCE_IP_ADDRESS
   LB_ALGORITHM_CONSISTENT_HASH_SOURCE_IP_ADDRESS_AND_PORT
   LB_ALGORITHM_CONSISTENT_HASH_URI
   LB_ALGORITHM_CONSISTENT_HASH_CUSTOM_HEADER
   LB_ALGORITHM_CONSISTENT_HASH_CUSTOM_STRING
   LB_ALGORITHM_CONSISTENT_HASH_CALLID
}


$global:XAAS_AVI_NETWORKS_USER_ROLE_NAME = "Application-Only"
$global:XAAS_AVI_NETWORKS_ANALYTICS_PROFILE = "System-Analytics-Profile"

$global:XAAS_AVI_NETWORKS_TENANT_TYPE = "ch.epfl.avi.tenant.type"

$global:XAAS_AVI_NETWORKS_HEALTH_MONITOR_LIST = @{
   vm =@(
      "System-TCP-443-EPFL",
      "System-Ping-EPFL"
   )
   tkgi = @(
      "System-Ping-EPFL",
      "System-TCP-80-EPFL", 
      "System-TCP-443-EPFL"
   )
}