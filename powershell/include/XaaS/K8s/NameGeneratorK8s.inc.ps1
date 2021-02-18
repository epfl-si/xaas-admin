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
   
   hidden [string]$deploymentTag
   <#
		-------------------------------------------------------------------------------------
		BUT : Constructeur de classe.

         IN  : $env           -> Infrastructure sur laquelle on travaille
                                 $TARGET_ENV_DEV
                                 $TARGET_ENV_TEST
                                 $TARGET_ENV_PROD
         IN  : $tenant        -> Tenant sur lequel on travaille
                                 $VRA_TENANT_DEFAULT
                                 $VRA_TENANT_EPFL
                                 $VRA_TENANT_ITSERVICES
         
		RET : Instance de l'objet
	#>
   NameGeneratorK8s([string]$env, [string]$tenant): base($env, $tenant) 
   { 
      $this.deploymentTag = ""
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Initialise le tag de déploiement

      IN  : $deploymentTag -> Environnement du cluster, au niveau logique, pas au niveau 
                              infrastructure
                              prod|test|dev
   #>
   [void] initDeploymentTag([string]$deploymentTag)
   {
      $this.deploymentTag = $deploymentTag.toLower()
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie la représentation courte du tag de déploiement

      RET : Représentation courte du deploymentTag
   #>
   hidden [string] getDeploymentTagShortname()
   {
      if($this.deploymentTag -eq "")
      {
         Throw "deploymentTag not initialized"
      }
      return $this.deploymentTag[0]
   }


   <# -------------------------------------------------------------------------------------
      ------------------------------------ PKS --------------------------------------------
      ------------------------------------------------------------------------------------- #>

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
            $middle = ("{0}{1}{2}" -f  $this.getDetail('unitID'),
                                       $this.sanitizeName($this.getDetail('facultyName'), $global:CLUSTER_NAME_FACULTY_PART_MAX_CHAR), `
                                       $this.sanitizeName($this.getDetail('unitName'), $global:CLUSTER_NAME_UNIT_PART_MAX_CHAR))
         }

         $global:VRA_TENANT__ITSERVICES
         {
            $middle = ("{0}{1}" -f $this.sanitizeName($this.getDetail('snowServiceId')).toLower(), `
                                    $this.sanitizeName($this.getDetail('serviceShortName'), $global:CLUSTER_NAME_SERVICE_NAME_PART_MAX_CHAR))
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
      return ('{0}{1}k{2}([0-9]+)' -f $this.getTenantStartLetter(), $this.getClusterNameMiddle(), $this.getDeploymentTagShortname())
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
      
      return ("{0}{1}k{2}{3}" -f $this.getTenantStartLetter(), ` # Lettre de début du tenant
               $this.getClusterNameMiddle(), `
               $this.getDeploymentTagShortname(), `
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
      BUT : Renvoie le nom d'un Storage Class pour un cluster

      IN  : $clusterName   -> Nom du cluster

      RET : Le nom du storage class
   #>
   [string] getStorageClassName([string]$clusterName)
   {
      return "stcl-{0}" -f $clusterName
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un Resource Quota pour un cluster et un namespace

      IN  : $clusterName   -> Nom du cluster
      IN  : $namespace     -> Nom du namespace

      RET : Le nom du resource quota
   #>
   [string] getResourceQuotaName([string]$clusterName, [string]$namespace)
   {
      return "reqo-{0}-{1}" -f $clusterName, $namespace
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un Role pour un cluster et un namespace

      IN  : $namespace     -> Nom du namespace

      RET : Le nom du Role
   #>
   [string] getRoleName([string]$namespace)
   {
      return "ro-{0}-{1}" -f $this.getDetail('snowServiceId'), $namespace
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un Role Binding pour un cluster et un namespace

      IN  : $clusterName   -> Nom du cluster
      IN  : $namespace     -> Nom du namespace

      RET : Le nom du Role Binding
   #>
   [string] getRoleBindingName([string]$clusterName, [string]$namespace)
   {
      return "robi-{0}-{1}" -f $clusterName, $namespace
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un Cluster Role pour un cluster

      RET : Le nom du Cluster Role
   #>
   [string] getClusterRoleName()
   {
      return "clro-{0}" -f $this.getDetail('snowServiceId')
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un Cluster Role Binding pour un cluster

      IN  : $clusterName         -> Nom du cluster
      IN  : $forServiceAccount   -> (optionnel) pour dire si on veut le nom pour les
                                    service accounts

      RET : Le nom du Cluster Role Binding
   #>
   [string] getClusterRoleBindingName([string]$clusterName)
   {
      return $this.getClusterRoleBindingName($clusterName, $false)
   }
   [string] getClusterRoleBindingName([string]$clusterName, [bool]$forServiceAccounts)
   {
      if($forServiceAccounts)
      {
         $end = "-service"
      }
      else
      {
         $end = ""
      }
      return "clrobi-{0}{1}" -f $clusterName, $end
   }

   <# -------------------------------------------------------------------------------------
      ----------------------------------- HARBOR ------------------------------------------
      ------------------------------------------------------------------------------------- #>


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
               $this.getDeploymentTagShortname())
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom d'un compte robot temporaire pour un projet Harbor

      IN  : $nbDaysValidity	-> Nombre de jours de validité du compte

      RET : Tableau associatif avec:
            .name       -> le nom du robot
            .desc       -> la description
            .expireAt   -> Unix time de la date d'expiration
   #>
   [Hashtable] getHarborRobotAccountInfos([string]$nbDaysValidity)
   {
      # Et c'est avec cette expression barbare que nous ajoutons les X jours à la date courante
		$dateInXDays = (Get-Date).AddDays($nbDaysValidity)
      $expireAt = [int][double]::Parse((Get-Date $dateInXDays -UFormat %s))
      
      $robotName = "{0}{1}" -f $this.getHarborProjectName(), $expireAt
      $robotDesc = "Valid until {0}" -f $dateInXDays
      
      return @{
         name =$robotName
         desc = $robotDesc
         expireAt = $expireAt
      }
   }


   <# -------------------------------------------------------------------------------------
      ----------------------------------- NetWork -----------------------------------------
      ------------------------------------------------------------------------------------- #>

   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom du networkProfile à utiliser

      RET : Nom du network profile
   #>
   [string] getNetProfileName()
   {
      return "np-vra-{0}" -f $this.deploymentTag.ToLower()
   }


   <# -------------------------------------------------------------------------------------
      ----------------------------------- NSX ------------------------------------------
      ------------------------------------------------------------------------------------- #>


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom NSGroup de l'environnement dans lequel il faudra ajouter le NSGroup du cluster

      RET : Nom du NSGroup racine
   #>
   [string] getEnvSecurityGroupName()
   {
      return "sg.k8s.{0}" -f $this.deploymentTag.toLower()
   }


   <#
      -------------------------------------------------------------------------------------
      BUT : Renvoie le nom et la description du NSGroup à créer dans NSX pour un cluster

      IN  : $clusterName	-> Nom du cluster

      RET : Tableau avec :
            - nom du NSGroup
            - description du NSGroup
   #>
   [Array] getSecurityGroupNameAndDesc([string]$clusterName)
   {
      return @(
         ("sg.k8s.{0}.{1}" -f $this.env.toLower(), $clusterName)
         ("Tenant: {0}" -f $this.tenant)
      )
   }
}