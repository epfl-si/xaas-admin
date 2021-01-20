<#
   BUT : Contient les constantes utilisées par la partie XaaS K8s (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020
#>

$global:K8S_CERT_FOLDER = ([IO.Path]::Combine($global:DATA_FOLDER, "xaas", "k8s", "certificates"))

# Nombre de digit à utiliser pour coder le nom du cluster
$global:CLUSTER_NAME_NB_DIGIT = 4

# Nombre max de caractères que peut contenir le nom de la faculté/unité dans un nom de cluster
$global:CLUSTER_NAME_FACULTY_PART_MAX_CHAR = 6
$global:CLUSTER_NAME_UNIT_PART_MAX_CHAR = 8

$global:CLUSTER_NAME_SERVICE_NAME_PART_MAX_CHAR = 15

# Nom de la zone DNS
$global:K8S_DNS_ZONE_NAME = "xaas.epfl.ch"

### Valeurs par défaut pour les fichiers YAML
# Voir aussi le fichier 'config/config-xaas-k8s.json' pour d'autres valeurs différentes via les environnements
$global:DEFAULT_NAMESPACE = "default"
$global:PSP_PRIVILEGED = $false
$global:PSP_ALLOW_PRIVILEGE_ESCALATION = $false
$global:RESOURCE_QUOTA_LB_AND_NODEPORTS = 0

# NSX
$global:NSX_LOGICAL_SWITCH_MEMBER_TYPE = "LogicalSwitch"