<#
   BUT : Contient les constantes utilisées par la partie XaaS NAS

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020
#>

# lettre à utiliser pour monter le drive réseau pour initialiser les droits
$global:XAAS_NAS_TEMPORARY_DRIVE = "Z"

# Les types d'accès possibles 
$global:ACCESS_TYPE_CIFS    = "cifs"
$global:ACCESS_TYPE_NFS3    = "nfs3"