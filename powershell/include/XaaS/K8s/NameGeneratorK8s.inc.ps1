<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour tout ce qui est XaaS K8s (Kubernetes)

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/functions.inc.ps1
   

#>

enum K8sDNSEntryType
{
   EntryMain
   EntryIngress
}

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
      BUT : Renvoie la partie centrale pour le nom d'un cluster en fonction du tenant
   #>
   hidden [string] getClusterNameMiddle()
   {
      $middle = ""
      switch($this.tenant)
      {
         $global:VRA_TENANT__EPFL
         {
            $middle = ("{0}{1}" -f $this.sanitizeName($this.getDetail('facultyName'), $global:CLUSTER_NAME_FACULTY_PART_MAX_CHAR), `
                                   $this.sanitizeName($this.getDetail('unitName')))
         }

         $global:VRA_TENANT__ITSERVICES
         {
            $middle = ($this.sanitizeName($this.getDetail('serviceShortName')))
         }

         $global:VRA_TENANT__RESEARCH
         {
            $middle = ($this.sanitizeName($this.getDetail('projectId')))
         }
      }
      return $middle
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie la regex à utiliser pour chercher les noms de cluster pour le tenant/env
            courant

      RET : La regex
   #>
   [string] getClusterRegex()
   {
      return ('{0}{1}k{2}([0-9]+)' -f $this.getTenantShortName(), $this.getClusterNameMiddle(), $this.getEnvShortName())
   }

   
   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom du cluster avec le numéro donné

      IN  : $number   -> Numéro du cluster qu'on désire

      RET : Le nom du cluster
   #>
   [string] getClusterName([int]$number)
   {
      $numberStr = $number.ToString().PadLeft($global:CLUSTER_NAME_NB_DIGIT, "0")
      
      return ("{0}{1}k{2}{3}" -f $this.getTenantShortName(), ` # Nom court du tenant
               $this.getClusterNameMiddle(), `
               $this.getEnvShortName(), `
               $numberStr)
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom DNS à utiliser pour un cluster et un "type" d'entrée donnée

      IN  : $clusterName      -> Nom du cluster
      IN  : $entrType         -> Le type d'entrée, principal ou pour Ingress.

      RET : Le nom de l'entrée DNS
   #>
   [string] getClusterDNSName([string]$clusterName, [K8sDNSEntryType]$entryType)
   {
      switch($entryType)
      {
         EntryMain { return $clusterName }
         EntryIngress { return ("i.{0}" -f $clusterName) }
      }

      Throw "Invalid value given for 'entryType'"
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un projet

      RET : Le nom du projet
   #>
   [string] getHarborProjectName()
   {
      $middle = ""
      switch($this.tenant)
      {
         $global:VRA_TENANT__EPFL
         {
            $middle = $this.sanitizeName($this.getDetail('facultyName'), $global:CLUSTER_NAME_FACULTY_PART_MAX_CHAR)
         }

         $global:VRA_TENANT__ITSERVICES
         {
            $middle = ($this.sanitizeName($this.getDetail('serviceShortName')))
         }

         $global:VRA_TENANT__RESEARCH
         {
            $middle = ($this.sanitizeName($this.getDetail('projectId')))
         }
      }
      

      return ("{0}{1}{2}" -f $this.getTenantShortName(), ` # Nom court du tenant
               $middle, `
               $this.getEnvShortName())
   }

}