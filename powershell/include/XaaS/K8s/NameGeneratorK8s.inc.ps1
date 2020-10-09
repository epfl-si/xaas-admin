<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS K8s (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/functions.inc.ps1
   

#>


class NameGeneratorK8s: NameGeneratorBase
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
   NameGeneratorK8s([string]$env, [string]$tenant): base($env, $tenant) 
   { }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom du cluster avec le numéro donné

      IN  : $number   -> Numéro du cluster qu'on désire

      RET : Le nom du cluster
   #>
   [string] getClusterName([int]$number)
   {
      $numberStr = $number.ToString().PadLeft($global:CLUSTER_NAME_NB_DIGIT, "0")
        
      switch($this.tenant)
      {
         $global:VRA_TENANT__EPFL
         {
            return ("{0}{1}" -f $this.getTenantShortName() )
         }

         $global:VRA_TENANT__ITSERVICES
         {

         }

         $global:VRA_TENANT__RESEARCH
      }
   }
}