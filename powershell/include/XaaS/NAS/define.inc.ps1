<#
   BUT : Contient les constantes utilisées par la partie XaaS NAS

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020
#>

# lettre à utiliser pour monter le drive réseau pour initialiser les droits
$global:XAAS_NAS_TEMPORARY_DRIVE = "Z"

# Types de volumes qu'on peut avoir sur le NAS
# Si on appelle la fonction "ToString()" sur l'un d'eux, ça doit renvoyer ce qui est passé en paramètre du script "endpoint"
Enum XaaSNASVolType {
   col # Collaboratif
   app # Applicatif
}