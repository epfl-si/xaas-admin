<#
   BUT : Contient les constantes utilisées par la partie XaaS K8s (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020
#>

# Nombre de digit à utiliser pour coder le nom du cluster
$global:CLUSTER_NAME_NB_DIGIT = 4

# Nombre max de caractères que peut contenir le nom de la faculté dans un nom de cluster
$global:CLUSTER_NAME_FACULTY_PART_MAX_CHAR = 6