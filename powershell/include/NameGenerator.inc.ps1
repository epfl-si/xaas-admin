<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour :
         - Groupes utilisés dans Active Directory et l'application "groups" (https://groups.epfl.ch). Les noms utilisés pour 
           ces groupes sont identiques mais le groupe AD généré pour le groupe de l'application "groups" est différent.
         - OU Active Directory dans laquelle les groupes doivent être mis.
         

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Le fichier "define.inc.ps1" doit avoir été inclus au programme principal avant que le fichier courant puisse être inclus.

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NameGenerator
{
    hidden [string]$tenant  # Tenant sur lequel on est en train de bosser 
    hidden [string]$env     # Environnement sur lequel on est en train de bosser.

    hidden $GROUP_TYPE_AD = 'adGroup'
    hidden $GROUP_TYPE_GROUPS = 'groupsGroup'

    static [string] $AD_GROUP_PREFIX = "vra_"
    static [string] $AD_DOMAIN_SUFFIX = "@intranet.epfl.ch"
    static [string] $AD_GROUP_GROUPS_SUFFIX = "_AppGrpU"
    static [string] $GROUPS_EMAIL_SUFFIX = "@groupes.epfl.ch"


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
    NameGenerator([string]$env, [string]$tenant)
    {
        if($global:TARGET_ENV_LIST -notcontains $env)
        {
            Throw ("Invalid environment given ({0})" -f $env)
        }

        if($global:TARGET_TENANT_LIST -notcontains $tenant)
        {
            Throw ("Invalid Tenant given ({0})" -f $tenant)
        }

        $this.tenant = $tenant
        $this.env    = $env
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# ----------------------------------------------------------------------------- EPFL --------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'expression régulière permettant de définir si un nom de groupe est 
              un nom pour le rôle passé et ceci pour l'environnement donné.

        IN  : $role     -> Nom du rôle pour lequel on veut la RegEX
                            "CSP_SUBTENANT_MANAGER"
							"CSP_SUPPORT"
							"CSP_CONSUMER_WITH_SHARED_ACCESS"
                            "CSP_CONSUMER"

        RET : L'expression régulières
    #>
    [string] getEPFLADGroupNameRegEx([string]$role)
    {
        if($role -eq "CSP_SUBTENANT_MANAGER")
        {
            # vra_<envShort>_adm_<tenantShort>
            return "{0}{1}_adm_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
        }
        # Support
        elseif($role -eq "CSP_SUPPORT")
        {
            # vra_<envShort>_sup_<facultyName>
            return "{0}{1}_sup_\d+" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # vra_<envShort>_<facultyID>_<unitID>
            return "{0}{1}_\d+_\d+" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
        }  
        else
        {
            Throw ("Incorrect role given ({0})" -f $role)
        }
        
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau avec :
               - le nom du groupe à utiliser pour le Role $role d'un BG d'une unité  $unitId, au sein du tenant EPFL.
               En fonction du paramètre $type, on sait si on doit renvoyer un nom de groupe "groups"
               ou un nom de groupe AD.
               - la description à utiliser pour le groupe. Valable uniquement si $type == 'ad'

               Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.

        REMARQUE : ATTENTION A BIEN PASSER DES [int] POUR CERTAINS PARAMETRES !! SI CE N'EST PAS FAIT, C'EST LE 
                   MAUVAIS PROTOTYPE DE FONCTION QUI RISQUE D'ETRE PRIS EN COMPTE.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group
        IN  : $facultyID        -> ID de la faculté du Business Group
        IN  : $unitName         -> Nom de l'unité
        IN  : $unitID           -> ID de l'unité du Business Group
        IN  : $type             -> Type du nom du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
        
        RET : Liste avec :
            - Nom du groupe à utiliser pour le rôle.
            - Description du groupe (si $type == 'ad', sinon, "")
    #>
    hidden [System.Collections.ArrayList] getEPFLRoleGroupNameAndDesc([string]$role, [string]$facultyName, [int]$facultyID, [string]$unitName, [int]$unitID, [string]$type, [bool]$fqdn)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        # Admin
        if($role -eq "CSP_SUBTENANT_MANAGER")
        {
            # Même nom de groupe (court) pour AD et "groups"
            # vra_<envShort>_adm_<tenantShort>
            $groupName = "{0}{1}_adm_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
            $groupDesc = "Administrators for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
        }
        # Support
        elseif($role -eq "CSP_SUPPORT")
        {
            # Même nom de groupe (court) pour AD et "groups"
            # vra_<envShort>_sup_<facultyName>
            $groupName = "{0}{1}_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $facultyName.toLower()
            $groupDesc = "Support for Faculty {0} on Tenant {1} on Environment {2}" -f $facultyName.toUpper(), $this.tenant.ToUpper(), $this.env.ToUpper()
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # Groupe AD
            if($type -eq $this.GROUP_TYPE_AD)
            {
                # vra_<envShort>_<facultyID>_<unitID>
                $groupName = "{0}{1}_{2}_{3}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $facultyID, $unitID
                # <facultyName>;<unitName>
                $groupDesc = "{0};{1}" -f $facultyName.toUpper(), $unitName.toUpper()
            }
            # Groupe "groups"
            else
            {
                Throw ("Incorrect values combination : '{0}', '{1}'" -f $role, $type)
            }
        }
        # Autre EPFL
        else
        {
            Throw ("Incorrect value for role : '{0}'" -f $role)
        }

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return @($groupName, $groupDesc)

    }

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les paramètres passés 
              Pas utilisé pour CSP_SUPPORT, voir plus bas.

        REMARQUE : ATTENTION A BIEN PASSER DES [int] POUR CERTAINS PARAMETRES !! SI CE N'EST PAS FAIT, C'EST LE 
                   MAUVAIS PROTOTYPE DE FONCTION QUI RISQUE D'ETRE PRIS EN COMPTE.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyID        -> ID de la faculté du Business Group
        IN  : $unitID           -> ID de l'unité du Business Group
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupName([string]$role, [int]$facultyID, [int]$unitID, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, "", $facultyID,"", $unitID, $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }
    
    [string] getEPFLRoleADGroupName([string]$role, [int]$facultyID, [int]$unitID)
    {
        return $this.getEPFLRoleADGroupName($role, $facultyID, $unitID, $false)
    }
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les paramètres passés 
              Utilisé uniquement pour les groupe CSP_SUPPORT et CSP_SUBTENANT_MANAGER. On doit 
              quand même le passer en  paramètre dans le cas où la fonction devrait évoluer 
              dans le futur

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_SUBTENANT_MANAGER"
        IN  : $facultyName      -> Nom de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupName([string]$role, [string]$facultyName, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }

    [string] getEPFLRoleADGroupName([string]$role, [string]$facultyName)
    {
        return $this.getEPFLRoleADGroupName($role, $facultyName, $false)
    }

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 
              Utilisé uniquement pour les groupe CSP_SUPPORT et CSP_SUBTENANT_MANAGER. On doit 
              quand même le passer en  paramètre dans le cas où la fonction devrait évoluer 
              dans le futur

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_SUBTENANT_MANAGER"
        IN  : $facultyName      -> Nom de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName, [bool]$fqdn)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_AD, $fqdn)
        return $groupDesc
    }

    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName)
    {
        return $this.getEPFLRoleADGroupDesc($role, $facultyName, $false)
    }    

    
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group
        IN  : $unitName         -> Nom de l'unité
    #>
    [string] getEPFLRoleADGroupDesc([string]$role, [string]$facultyName, [string]$unitName)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", $unitName, "", $this.GROUP_TYPE_AD, $false)
        return $groupDesc
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group    
    #>
    [string] getEPFLRoleGroupsGroupName([string]$role, [string]$facultyName)
    {
        $groupName, $groupDesc = $this.getEPFLRoleGroupNameAndDesc($role, $facultyName, "", "", "", $this.GROUP_TYPE_GROUPS, $false)
        return $groupName
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_MANAGER"
        IN  : $facultyName      -> Le nom de la faculté du Business Group    
    #>
    [string] getEPFLRoleGroupsADGroupName([string]$role, [string]$facultyName)
    {
        $groupName = $this.getEPFLRoleGroupsGroupName($role, $facultyName)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe d'approbation pour les paramètres passés 
              Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.

        IN  : $facultyName -> Le nom court de la faculté
        IN  : $type             -> Le type du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom FQDN du groupe.
                                    $true|$false    

    #>
    hidden [string] getEPFLApproveGroupName([string]$facultyName, [string]$type, [bool]$fqdn)
    {
        # NOTE: Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.

        # vra_<envShort>_approval_<faculty>
        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $facultyName.ToLower()

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }
        return $groupName
    }

    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD ou GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group du tenant ITServices

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getEPFLApproveADGroupName([string]$facultyName, [bool]$fqdn)
    {
        return $this.getEPFLApproveGroupName($facultyName, $this.GROUP_TYPE_AD, $fqdn)
    }
    [string] getEPFLApproveADGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveADGroupName($facultyName, $false)
    }
    [string] getEPFLApproveGroupsGroupName([string]$facultyName, [bool]$fqdn)
    {
        return $this.getEPFLApproveGroupName($facultyName, $this.GROUP_TYPE_GROUPS, $fqdn)
    }
    [string] getEPFLApproveGroupsGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveGroupsGroupName($facultyName, $false)
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'adresse mail du groupe "groups" qui est utilisé pour faire les validations
              de la faculté $facultyName

        IN  : $facultyName      -> Le nom court de la faculté
       
        RET : Adresse mail du groupe
    #>
    [string] getEPFLApproveGroupsEmail([string]$facultyName)
    {
        $groupName = $this.getEPFLApproveGroupsGroupName($facultyName)
        return "{0}{1}" -f $groupName, [NameGenerator]::GROUPS_EMAIL_SUFFIX
    }
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD utilisé pour les approbations des demandes
              pour le tenant.

        IN  : $facultyName      -> Le nom court de la faculté
       
        RET : Description du groupe
    #>
    [string] getEPFLApproveADGroupDesc([string]$facultyName)
    {
        return "Approval group for Faculty: {0}" -f $facultyName
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé dans AD à utiliser pour le mécanisme 
              d'approbation des demandes pour un Business Group du tenant ITServices

        IN  : $facultyName      -> Le nom court de la faculté
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getEPFLApproveGroupsADGroupName([string]$facultyName, [bool]$fqdn)
    {
        $groupName = $this.getEPFLApproveGroupName($facultyName, $this.GROUP_TYPE_GROUPS, $fqdn)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }
    [string] getEPFLApproveGroupsADGroupName([string]$facultyName)
    {
        return $this.getEPFLApproveGroupsADGroupName($facultyName, $false)
    }

    
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# --------------------------------------------------------------------------- IT SERVICES ---------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    hidden [System.Collections.ArrayList] getITSRoleGroupNameAndDesc([string]$role, [string]$serviceShortName, [string]$serviceName, [string]$type, [bool]$fqdn)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        # Admin, Support
        if($role -eq "CSP_SUBTENANT_MANAGER" -or `
            $role -eq "CSP_SUPPORT")
        {
            # vra_<envShort>_adm_sup_its
            $groupName = "{0}{1}_adm_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
            $groupDesc = "Administrators/Support for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
            
        }
        # Shared, Users
        elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                $role -eq "CSP_CONSUMER")
        {
            # vra_<envShort>_<serviceShort>
            $groupName = "{0}{1}_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $serviceShortName.ToLower()
            # <serviceName>
            $groupDesc = $serviceName

        }
        # Autre EPFL
        else
        {
            Throw ("Incorrect value for role : '{0}'" -f $role)
        }

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return @($groupName, $groupDesc)


    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe à utiliser pour le Role $role du BG du service
              $serviceShortName au sein du tenant ITServices.
              En fonction du paramètre $type, on sait si on doit renvoyer un nom de groupe "groups"
              ou un nom de groupe AD.

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false  
        
		RET : Nom du groupe à utiliser pour le rôle.
    #>
    [string] getITSRoleADGroupName([string]$role, [string] $serviceShortName, [bool]$fqdn)
    {
        return $this.getITSRoleGroupNameAndDesc($role, $serviceShortName, "", $this.GROUP_TYPE_AD, $fqdn)
    }
    [string] getITSRoleADGroupName([string]$role, [string] $serviceShortName)
    {
        return $this.getITSRoleADGroupName($role, $serviceShortName, $false)
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceName      -> Le nom du service
    #>
    [string] getITSRoleADGroupDesc([string]$role, [string]$serviceName)
    {
        $groupName, $groupDesc = $this.getITSRoleGroupNameAndDesc($role, "", $serviceName, $this.GROUP_TYPE_AD, $false)
        return $groupDesc
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
    #>
    [string] getITSRoleGroupsGroupName([string]$role, [string]$serviceShortName)
    {
        $groupName, $groupDesc = $this.getITSRoleGroupNameAndDesc($role, $serviceShortName, "", $this.GROUP_TYPE_GROUPS, $false)
        return $groupName
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $serviceShortName -> Le nom court du service
    #>
    [string] getITSRoleGroupsADGroupName([string]$role, [string]$serviceShortName)
    {
        $groupName = $this.getITSRoleGroupsGroupName($role, $serviceShortName)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe d'approbation et sa description pour les paramètres passés 
              Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.

        IN  : $serviceShortName -> Le nom court du service
        IN  : $type             -> Le type du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom FQDN du groupe.
                                    $true|$false    

        RET : Nom du groupe
    #>
    hidden [string] getITSApproveGroupName([string]$serviceShortName, [string]$type, [bool]$fqdn)
    {
        # NOTE: Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.

        # vra_<envShort>_approval_<serviceShort>
        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $serviceShortName.ToLower()

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }

        return $groupName
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD ou GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group du tenant ITServices

        IN  : $serviceShortName -> Le nom court du service
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getITSApproveADGroupName([string]$serviceShortName, [bool]$fqdn)
    {
        return $this.getITSApproveGroupName($serviceShortName, $this.GROUP_TYPE_AD, $fqdn)
    }
    [string] getITSApproveADGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveADGroupName($serviceShortName, $false)
    }
    [string] getITSApproveGroupsGroupName([string]$serviceShortName, [bool]$fqdn)
    {
        return $this.getITSApproveGroupName($serviceShortName, $this.GROUP_TYPE_GROUPS, $fqdn)
    }
    [string] getITSApproveGroupsGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveGroupsGroupName($serviceShortName, $false)
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'adresse mail du groupe "groups" qui est utilisé pour faire les validations
              du service $serviceShortName

        IN  : $serviceShortName      -> Le nom court du service
       
        RET : Adresse mail du groupe
    #>
    [string] getITSApproveGroupsEmail([string]$serviceShortName)
    {
        $groupName = $this.getITSApproveGroupsGroupName($serviceShortName)
        return $groupName + $this.GROUPS_EMAIL_SUFFIX
    }    
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé dans AD à utiliser pour le mécanisme 
              d'approbation des demandes pour un Business Group du tenant ITServices

        IN  : $serviceShortName -> Le nom court du service
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getITSApproveGroupsADGroupName([string]$serviceShortName, [bool]$fqdn)
    {
        $groupName = $this.getITSApproveGroupName($serviceShortName, $this.GROUP_TYPE_GROUPS, $fqdn)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }
    [string] getITSApproveGroupsADGroupName([string]$serviceShortName)
    {
        return $this.getITSApproveGroupsADGroupName($serviceShortName, $false)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe utilisé pour approuver les demandes du service
              dont le nom est passé

        IN  : $serviceName      -> Le nom court du service
       
        RET : Description du groupe
    #>
    [string] getITSApproveADGroupDesc([string]$serviceName)
    {
        return "Approval group for Service: {0}" -f $serviceName
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# --------------------------------------------------------------------------- AUTRES --------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le DN de l'OU Active Directory à utiliser pour mettre les groupes 
              de l'environnement et du tenant courant.

		RET : DN de l'OU
    #>
    [string] getADGroupsOUDN()
    {
        $tenantOU = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT_DEFAULT { $tenantOU = "default"}
            $global:VRA_TENANT_EPFL { $tenantOU = "EPFL"}
            $global:VRA_TENANT_ITSERVICES { $tenantOU = "ITServices"}
        }

        $envOU = ""
        switch($this.env)
        {
            $global:TARGET_ENV_DEV {$envOU = "Dev"}
            $global:TARGET_ENV_TEST {$envOU = "Test"}
            $global:TARGET_ENV_PROD {$envOU = "Prod"}
        }

        # Retour du résultat 
        return ('OU={0},OU={1},OU=XaaS,OU=DIT-Services Communs,DC=intranet,DC=epfl,DC=ch' -f $tenantOU, $envOU)
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du serveur vRA à utiliser

		RET : Nom du serveur vRA
    #>
    [string] getvRAServerName()
    {
        switch($this.env)
        {
            $global:TARGET_ENV_DEV {return 'vsissp-vra-d-01.epfl.ch'}
            $global:TARGET_ENV_TEST {return 'vsissp-vra-test.epfl.ch'}
            $global:TARGET_ENV_PROD {write-warning "TO FILL"; return ""}
        }
        return ""
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court de l'environnement.
              Ceci est utilisé pour la génération des noms des groupes

		RET : Nom court de l'environnement
    #>
    hidden [string] getEnvShortName()
    {
        switch($this.env)
        {
            $global:TARGET_ENV_DEV {return 'd'}
            $global:TARGET_ENV_TEST {return 't'}
            $global:TARGET_ENV_PROD {return 'p'}
        }
        return ""
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court du tenant.
              Ceci est utilisé pour la génération des noms des groupes

		RET : Nom court du tenant
    #>
    hidden [string] getTenantShortName()
    {
        switch($this.tenant)
        {
            $global:VRA_TENANT_DEFAULT { return 'def'}
            $global:VRA_TENANT_EPFL { return 'epfl'}
            $global:VRA_TENANT_ITSERVICES { return 'its'}
        }
        return ""
    } 

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le préfixe de machine à utiliser pour une faculté ou un service

        IN  : $facultyNameOrServiceShortName -> Nom de la faculté ou nom court du service

		RET : Préfixe de machine
    #>
    [string] getVMMachinePrefix([string]$facultyNameOrServiceShortName)
    {
        return ("{0}-" -f $facultyNameOrServiceShortName.toLower())
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un BG du tenant EPFL

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description du BG
    #>
    [string] getEPFLBGDescription([string]$facultyName, [string]$unitName)
    {
        return ("Faculty: {0}`nUnit: {1}" -f $facultyName.toUpper(), $unitName.toUpper())
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 
              Au vu des paramètres, c'est pour le tenant EPFL que cette fonction sera utilisée.

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description du BG
    #>
    [string] getEntName([string]$facultyName, [string]$unitName)
    {
        return ("{0}_{1}_{2}" -f $this.getTenantShortName(), $facultyName.ToLower(), $unitName.ToLower())
    }    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 
              Au vu des paramètres, c'est pour le tenant ITServices que cette fonction sera utilisée.

        IN  : $serviceShortName -> Nom court du service

		RET : Description du BG
    #>
    [string] getEntName([string]$serviceShortName)
    {
        return ("{0}_{1}" -f $this.getTenantShortName(), $serviceShortName.ToLower())
    }    

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement
              Au vu des paramètres, cette méthode ne sera appelée que pour le tenant EPFL

        IN  : $facultyName  -> Nom de la faculté 
        IN  : $unitName     -> Nom de l'unité

		RET : Description du BG
    #>
    [string] getEntDescription([string]$facultyName, [string]$unitName)
    {
        return ("Faculty: {0}`nUnit: {1}" -f $facultyName.toUpper(), $unitName.toUpper())
    }    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement 
              Au vu des paramètres, cette méthode ne sera appelée que pour le tenant ITServices

        IN  : $serviceShortName -> Nom court du service

		RET : Description du BG
    #>
    [string] getEntDescription([string]$serviceShortName)
    {
        # Par défaut, pas de description mais on se laisse la porte "ouverte" avec l'existance de cette méthode
        return ""
    }     

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description d'un Entitlement pour le tenant courant

        IN  : $bgName       -> Le nom du BG

        RET : Tableau avec :
                - Nom de l'Entitlement
                - Description de l'entitlement
    #>
    [System.Collections.ArrayList] getBGEntNameAndDesc([string] $bgName)
    {
        if($this.tenant -eq $global:VRA_TENANT_EPFL)
        {
            # Extraction des infos pour construire les noms des autres éléments
            $dummy, $faculty, $unit = $bgName.Split("_")
    
            # Création du nom/description de l'entitlement
            $entName = $this.getEntName($faculty, $unit)
            $entDesc = $this.getEntDescription($faculty, $unit)
        }
        # Si Tenant ITServices
        elseif($this.tenant -eq $global:VRA_TENANT_ITSERVICES)
        {
            # Extraction des infos pour construire les noms des autres éléments
            $dummy, $serviceShortName = $bgName.Split("_")
    
            # Création du nom/description de l'entitlement
            $entName = $this.getEntName($serviceShortName)
            $entDesc = $this.getEntDescription($serviceShortName)
        }
        else # Autre Tenant (ex: vsphere.local)
        {
            Throw ("Unsupported Tenant ({0})" -f $this.tenant)
        }
    
        return @($entName, $entDesc)        
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Extrait et renvoie les informations d'un groupe AD en les récupérant depuis son nom. 
              Les informations renvoyées varient en fonction du Tenant courant.

        IN  : $groupName    -> Le nom du groupe depuis lequel extraire les infos

        RET : Pour tenant EPFL, tableau avec :
                - ID de la faculté
                - ID de l'unité
            
              Pour tenant ITServices, tableau avec :
                - Nom court du service
    #>
    [System.Collections.ArrayList] extractInfosFromADGroupName([string]$ADGroupName)
    {
        # Eclatement du nom pour récupérer les informations
        $partList = $ADGroupName.Split("_")

        # EPFL
        if($this.tenant -eq $global:VRA_TENANT_EPFL)
        {
            # Le nom du groupe devait avoir la forme :
            # vra_<envShort>_<facultyID>_<unitID>

            if($partList.Count -lt 4)
            {
                Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
            }

            return @($partList[2], $partList[3])
        }
        # ITServices
        elseif($this.tenant -eq $global:VRA_TENANT_ITSERVICES)
        {
            # Le nom du groupe devait avoir la forme :
            # vra_<envShort>_<serviceShortName>
            
            if($partList.Count -lt 3)
            {
                Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
            }

            return @($partList[2])
        }
        else # Autre Tenant (ex: vsphere.local)
        {
            Throw ("Unsupported Tenant ({0})" -f $this.tenant)
        }
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Extrait et renvoie les informations d'un groupe AD en les récupérant depuis sa description. 
              Les informations renvoyées varient en fonction du Tenant courant.

        IN  : $groupName    -> Le nom du groupe depuis lequel extraire les infos

        RET : Pour tenant EPFL, tableau avec :
                - Nom de la faculté
                - Nom de l'unité
            
              Pour tenant ITServices, tableau avec :
                - Nom long du service
    #>
    [System.Collections.ArrayList] extractInfosFromADGroupDesc([string]$ADGroupDesc)
    {
        # Eclatement du nom pour récupérer les informations
        $partList = $ADGroupDesc.Split(";")

        # EPFL
        if($this.tenant -eq $global:VRA_TENANT_EPFL)
        {
            # Le nom du groupe devait avoir la forme :
            # <facultyNam>;<unitName>

            if($partList.Count -lt 2)
            {
                Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
            }

            return $partList
        }
        # ITServices
        elseif($this.tenant -eq $global:VRA_TENANT_ITSERVICES)
        {
            # Le nom du groupe devait avoir la forme :
            # <serviceName>
            
            if($partList.Count -lt 1)
            {
                Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
            }

            return @($partList[0])
        }
        else # Autre Tenant (ex: vsphere.local)
        {
            Throw ("Unsupported Tenant ({0})" -f $this.tenant)
        }
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un BG en fonction des paramètres passés.
              Au vu des paramètres, cette fonction ne sera utilisée que pour le Tenant EPFL

        IN  : $facultyName  -> Nom de la faculté
        IN  : $unitName     -> Nom de l'unité

        RET : Le nom du BG à utiliser
    #>
    [string] getBGName([string]$facultyName, [string]$unitName)
    {
        return "{0}_{1}_{2}" -f $this.getTenantShortName(), $facultyName.ToLower(), $unitName.ToLower()
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un BG en fonction des paramètres passés.
              Au vu des paramètres, cette fonction ne sera utilisée que pour le Tenant ITService

        IN  : $serviceShortName -> Le nom court du service.

        RET : Le nom du BG à utiliser
    #>
    [string] getBGName([string]$serviceShortName)
    {
        return "{0}_{1}" -f $this.getTenantShortName(), $serviceShortName.ToLower()
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie la base du nom de Reservation à utiliser pour un BG
              
        IN  : $bgName       -> Le nom du BG
        IN  : $clusterName  -> Le nom du cluster pour lequel on veut la Reservation

        RET : Le nom de la Reservation
    #>
    [string] getBGResName([string]$bgName, [string]$clusterName)
    {
        # Extraction des infos pour construire les noms des autres éléments
        $partList = $bgName.Split("_")

        # Si Tenant EPFL
        if($this.tenant -eq $global:VRA_TENANT_EPFL)
        {
            # Le nom du BG a la structure suivante :
            # epfl_<faculty>_<unit>

            # Le nom de la Reservation est généré comme suit
            # <tenantShort>_<faculty>_<unit>_<cluster>

            return "{0}_{1}_{2}_{3}" -f $this.getTenantShortName(), $partList[1], $partList[2], $clusterName.ToLower()
        }
        # Si Tenant ITServices
        elseif($this.tenant -eq $global:VRA_TENANT_ITSERVICES)
        {
            # Le nom du BG a la structure suivante :
            # epfl_<serviceShortName>

            # Le nom de la Reservation est généré comme suit
            # <tenantShort>_<serviceShortName>_<cluster>
            
            return "{0}_{1}_{2}" -f $this.getTenantShortName(), $partList[1], $clusterName.ToLower()
        }
        else
        {
            Throw("Unsupported Tenant ({0})" -f $this.tenant)
        }

    }
    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le FQDN d'un group AD
              
        IN  : $groupShortName   -> Le nom court du groupe

        RET : Le nom avec FQDN
    #>
    [string] getADGroupFQDN([string]$groupShortName)
    {
        # On check que ça soit bien un nom court qu'on ai donné.
        if($groupShortName.EndsWith([NameGenerator]::AD_DOMAIN_SUFFIX))
        {
            return $groupShortName
        }
        else 
        {
            return $groupShortName += [NameGenerator]::AD_DOMAIN_SUFFIX   
        }
    }


}