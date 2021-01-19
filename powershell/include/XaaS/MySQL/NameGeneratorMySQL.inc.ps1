<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS MySQL

   AUTEUR : Lucien Chaboudez
   DATE   : Janvier 2021

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/functions.inc.ps1
   

#>


class NameGeneratorMySQL: NameGeneratorBase
{
   
   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

        IN  : $env      -> Environnement sur lequel on travaille
                           $TARGET_ENV_DEV
                           $TARGET_ENV_TEST
                           $TARGET_ENV_PROD
        IN  : $tenant   -> Tenant sur lequel on travaille
                           $VRA_TENANT_DEFAULT
                           $VRA_TENANT_EPFL
                           $VRA_TENANT_ITSERVICES

		RET : Instance de l'objet
	#>
   NameGeneratorMySQL([string]$env, [string]$tenant): base($env, $tenant)
   {
   }

   # TODO:
        
}