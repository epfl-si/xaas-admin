<#
   BUT : Classe permettant de donner des informations sur les noms à utiliser pour :
         - Groupes utilisés dans Active Directory et l'application "groups" (https://groups.epfl.ch). Les noms utilisés pour 
           ces groupes sont identiques mais le groupe AD généré pour le groupe de l'application "groups" est différent.
         - OU Active Directory dans laquelle les groupes doivent être mis.
         - Noms des éléments dans vRA

         Avant d'être utilisé, l'objet instancié devra être configuré via la fonction 'initDetails()'.
         Il y a cependant quelques fonctions (à la fin du fichier) qui peuvent être utilisées sans que la 
         classe soit initialisée.
         

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2018

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/define.inc.ps1
   - vra-config.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base
   0.2 - Suppression des fonctions spécifiques aux tenant, configuration de la classe via 'initDetails' et appel
        ensuite de fonctions plus génériques

#>
class NameGenerator
{
    hidden [string]$tenant  # Tenant sur lequel on est en train de bosser 
    hidden [string]$env     # Environnement sur lequel on est en train de bosser.

    # Détails pour la génération des différents noms. Sera initialisé via 'initDetails' pour mettre à jour
    # les informations en fonction des noms à générer.
    hidden [System.Collections.IDictionary]$details 

    hidden $GROUP_TYPE_AD = 'adGroup'
    hidden $GROUP_TYPE_GROUPS = 'groupsGroup'

    static [string] $AD_GROUP_PREFIX = "vra_"
    static [string] $AD_DOMAIN_NAME = "intranet.epfl.ch"
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

        $this.tenant = $tenant.ToLower()
        $this.env    = $env.ToLower()

        $this.details = @{}
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : initialise les détails nécessaires pour utiliser les fonctions ci-dessous.
                On devra ensuite passer par la fonction 'getDetails' pour récupérer une des valeurs.

        IN  : $details          -> Dictionnaire avec les détails nécessaire. Le contenu varie en fonction du tenant 
                                    passé lors de l'instanciation de l'objet.

                                    EPFL:
                                        financeCenter    -> no du centre financier de l'unité
                                        facultyName      -> Le nom de la faculté du Business Group
                                        facultyID        -> ID de la faculté du Business Group
                                        unitName         -> Nom de l'unité
                                        unitID           -> ID de l'unité du Business Group
                                    
                                    ITServices:
                                        financeCenter       -> no du centre financier du service
                                        serviceShortName    -> Nom court du service
                                        serviceName         -> Nom long du service
                                        snowServiceId       -> ID du service dans ServiceNow
    #>
    [void] initDetails([System.Collections.IDictionary]$details)
    {
        $keysToCheck = @()
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            {
                $keysToCheck = @('financeCenter', 'facultyName', 'facultyID', 'unitName', 'unitID')
            }

            $global:VRA_TENANT__ITSERVICES
            {
                $keysToCheck = @('financeCenter', 'serviceShortName', 'serviceName', 'snowServiceId')
            } 

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        # Contrôle que toutes les infos sont là.
        $missingKeys = @()
        Foreach($key in $keysToCheck)
        {
            if(! $details.ContainsKey($key))
            {
                $missingKeys += $key
            }
        }

        # Si des infos sont manquantes...
        if($missingKeys.Count -gt 0)
        {
            Throw ("Following keys are missing: {0}" -f ($missingKeys -join ', '))
        }

        $this.details = $details
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la valeur d'un détail, donné par son nom. Si pas trouvé, une exception
                est levée.

        IN  : $name -> Nom du détail que l'on désire.

        RET : La valeur du détail
    #>
    hidden [String] getDetail([string]$name)
    {
        if(!$this.details.ContainsKey($name))
        {
            Throw ("Asked detail ({0}) doesn't exists in list" -f $name)
        }

        return $this.details.$name
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Transforme et renvoie la chaine de caractères passée pour qu'elle corresponde
                aux attentes du nommage des groupes. 
                Les - vont être transformés en _ par exemple et tout sera mis en minuscule

        IN  : $str -> la chaine de caractères à transformer

        RET : La chaine corrigée
    #>
    hidden [string]transformForGroupName([string]$str)
    {
        return $str.replace("-", "_").ToLower()
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Transforme et renvoie le nom de faculté pour supprimer les caractères indésirables
                Les - vont être supprimés

        IN  : $facultyName -> Le nom de la faculté

        RET : La chaine corrigée
    #>
    hidden [string]sanitizeFacultyName([string]$facultyName)
    {
        return $facultyName.replace("-", "")
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Transforme et renvoie le nom de faculté passée pour qu'il corresponde
                aux attentes du nommage des groupes et autres. 
                Les - vont être supprimés et tout sera mis en minuscule

        IN  : $facultyName -> Le nom de la faculté

        RET : La chaine corrigée
    #>
    hidden [string]transformFacultyForGroupName([string]$facultyName)
    {
        return $this.sanitizeFacultyName($facultyName).ToLower()
    }
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'expression régulière permettant de définir si un nom de groupe est 
              un nom pour le rôle passé.

        IN  : $role     -> Nom du rôle pour lequel on veut la RegEX
                            "CSP_SUBTENANT_MANAGER"
							"CSP_SUPPORT"
							"CSP_CONSUMER_WITH_SHARED_ACCESS"
                            "CSP_CONSUMER"

        RET : L'expression régulières
    #>
    [string] getADGroupNameRegEx([string]$role)
    {
        
        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            {
                if($role -eq "CSP_SUBTENANT_MANAGER")
                {
                    # vra_<envShort>_adm_<tenantShort>
                    return "^{0}{1}_adm_{2}$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                }
                # Support
                elseif($role -eq "CSP_SUPPORT")
                {
                    # vra_<envShort>_sup_<facultyName>
                    return "^{0}{1}_sup_\d+$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
                }
                # Shared, Users
                elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                        $role -eq "CSP_CONSUMER")
                {
                    # vra_<envShort>_<facultyID>_<unitID>
                    return "^{0}{1}_\d+_\d+$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName()
                }  
                else
                {
                    Throw ("Incorrect role given ({0})" -f $role)
                }
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                if($role -eq "CSP_SUBTENANT_MANAGER" -or `
                    $role -eq "CSP_SUPPORT")
                {
                    # vra_<envShort>_adm_sup_<tenantShort>
                    return "^{0}{1}_adm_sup_{2}$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                }
                # Shared, Users
                elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                        $role -eq "CSP_CONSUMER")
                {
                    # vra_<envShort>_<serviceShort>
                    # On ajoute une exclusion à la fin pour être sûr de ne pas prendre aussi les éléments qui sont pour les 2 rôles ci-dessus
                    return "^{0}{1}(?!_approval)_\w+(?<!_adm_sup_{2})$" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                }  
                else
                {
                    Throw ("Incorrect role given ({0})" -f $role)
                }
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        return $null
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
        IN  : $type             -> Type du nom du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
        
                
        RET : Liste avec :
            - Nom du groupe à utiliser pour le rôle.
            - Description du groupe (si $type == 'ad', sinon, "")
    #>
    hidden [System.Collections.ArrayList] getRoleGroupNameAndDesc([string]$role, [string]$type, [bool]$fqdn)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        $groupName = ""

        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            {
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
                    $groupName = "{0}{1}_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName'))
                    $groupDesc = "Support for Faculty {0} on Tenant {1} on Environment {2}" -f $this.getDetail('facultyName').toUpper(), $this.tenant.ToUpper(), $this.env.ToUpper()
                }
                # Shared, Users
                elseif($role -eq "CSP_CONSUMER_WITH_SHARED_ACCESS" -or `
                        $role -eq "CSP_CONSUMER")
                {
                    # Groupe AD
                    if($type -eq $this.GROUP_TYPE_AD)
                    {
                        # vra_<envShort>_<facultyID>_<unitID>
                        $groupName = "{0}{1}_{2}_{3}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getDetail('facultyID'), $this.getDetail('unitID')
                        # <facultyName>;<unitName>;<financeCenter>
                        $groupDesc = "{0};{1};{2}" -f $this.getDetail('facultyName').toUpper(), $this.getDetail('unitName').toUpper(), $this.getDetail('financeCenter')
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
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
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
                    $groupName = "{0}{1}_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($this.getDetail('serviceShortName'))
                    # <snowServiceId>;<serviceName>
                    # On utilise uniquement le nom du service et pas une chaine de caractères avec d'autres trucs en plus comme ça, celui-ci peut être ensuite
                    # réutilisé pour d'autres choses dans la création des éléments dans vRA
                    $groupDesc = "{0};{1};{2}" -f $this.getDetail('snowServiceId').ToUpper(), $this.getDetail('serviceName'), $this.getDetail('financeCenter')

                }
                # Autre EPFL
                else
                {
                    Throw ("Incorrect value for role : '{0}'" -f $role)
                }
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }

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
              
        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
							        "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getRoleADGroupName([string]$role, [bool]$fqdn)
    {   
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_AD, $fqdn)
        return $groupName
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
    #>
    [string] getRoleADGroupDesc([string]$role)
    {
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_AD, $false)
        return $groupDesc
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUBTENANT_MANAGER"
							        "CSP_SUPPORT"
							        "CSP_CONSUMER_WITH_SHARED_ACCESS"
                                    "CSP_CONSUMER"
    #>
    [string] getRoleGroupsGroupName([string]$role)
    {
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_GROUPS, $false)
        return $groupName
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Nom du rôle pour lequel on veut le groupe. 
                                    "CSP_SUPPORT"
                                    "CSP_MANAGER"
    #>
    [string] getRoleGroupsADGroupName([string]$role)
    {
        $groupName = $this.getRoleGroupsGroupName($role)
        return $groupName + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }

    
    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe d'approbation pour les paramètres passés 
              Cette méthode est cachée et est le point d'appel central pour d'autres méthodes publiques.
              S'il n'y a pas d'information pour le niveau demandé ($level), on renvoie une chaine vide, 
              ce qui permettra à l'appelant de savoir qu'il n'y a plus de groupe à partir du niveau demandé.

        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $type             -> Le type du groupe:
                                    $this.GROUP_TYPE_AD
                                    $this.GROUP_TYPE_GROUPS
        IN  : $fqdn             -> Pour dire si on veut le nom FQDN du groupe.
                                    $true|$false  
                                    
        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)

    #>
    hidden [PSCustomObject] getApproveGroupName([int]$level, [string]$type, [bool]$fqdn)
    {
        <# 
        == Tenant EPFL ==

        NOTE 06.2018: Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.
        NOTE 02.2019: Le paramètre $facultyName ne sera utilisé que quand àlevel == 2 car le premier niveau, c'est le service manager de IaaS
                         qui va s'occuper de le valider.
        

        Ancienne nomenclature plus utilisée depuis 14.02.2019
        vra_<envShort>_approval_<faculty>
        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformFacultyForGroupName($facultyName)

        Level 1 -> vra_<envshort>_approval_iaas
        Level 2 -> vra_<envShort>_approval_<faculty>


        == Tenant ITServices ==

        NOTE 06.2018 : Pour le moment, on n'utilise pas le paramètre $type car c'est le même nom de groupe qui est utilisé pour AD et GROUPS.
        NOTE 02.2019 : On n'utilise maintenant plus le paramètre $serviceShortName car ce sont maintenant le service manager IaaS (level 1)
                            et les chefs de service VPSI (level 2) qui approuvent les demandes.
        

        Mis en commentaire le 14.02.2019 (c'est la St-Valentin!) car plus utilisé pour le moment. Mais on garde au cas où.
        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($serviceShortName)

        Level 1 -> vra_<envShort>_approval_iaas
        Level 2 -> vra_<envShort>_approval_vpsi
        #>

        $onlyForTenant = $true
        $groupName = ""
        $last = ""

        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            {
                if($level -eq 1)
                {
                    $last = "service_manager"
                    $onlyForTenant = $false
                }
                elseif($level -eq 2)
                {
                    $last = $this.transformFacultyForGroupName($this.getDetail('facultyName'))
                }
                else 
                {
                    return $null   
                }
            }


            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                if($level -eq 1)
                {
                    $last = "service_manager"
                    $onlyForTenant = $false
                }
                elseif($level -eq 2)
                {
                    $last = "service_chiefs"
                }
                else 
                {
                    return $null
                }
            }


            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
            
        }

        $groupName = "{0}{1}_approval_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $last

        if($fqdn)
        {
            $groupName = $this.getADGroupFQDN($groupName)
        }
        return @{ name = $groupName
                  onlyForTenant = $onlyForTenant }
    }
    

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD ou GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group du tenant ITServices

        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)
    #>
    [PSCustomObject] getApproveADGroupName([int]$level, [bool]$fqdn)
    {
        return $this.getApproveGroupName($level, $this.GROUP_TYPE_AD, $fqdn)
    }
    

    [PSCustomObject] getApproveGroupsGroupName([int]$level, [bool]$fqdn)
    {
        return $this.getApproveGroupName($level, $this.GROUP_TYPE_GROUPS, $fqdn)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'adresse mail du groupe "groups" qui est utilisé pour faire les validations
              de la faculté $facultyName

        IN  : $level            -> Niveau d'approbation (1, 2, ...)
       
        RET : Adresse mail du groupe
    #>
    [string] getApproveGroupsEmail([int]$level)
    {
        $groupInfos = $this.getApproveGroupsGroupName($level, $false)
        return "{0}{1}" -f $groupInfos.name, [NameGenerator]::GROUPS_EMAIL_SUFFIX
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD utilisé pour les approbations des demandes
              pour le tenant.

        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
       
        RET : Description du groupe
    #>
    [string] getApproveADGroupDesc([int]$level)
    {
        $desc = "Approval group (level {0})" -f $level

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                # Le premier niveau d'approbation est générique à toutes les facultés donc pas de description "précise" pour celui-ci
                if($level -gt 1)
                {
                    $desc = "{0} for Faculty: {1}" -f $desc, $this.getDetail('facultyName').ToUpper()
                }
            }

            $global:VRA_TENANT__ITSERVICES
            {
                # NOTE: 15.02.2019 - On n'utilise plue le nom du service dans la description du groupe car c'est maintenant un seul groupe d'approbation
                # pour tous les services 
                # return "Approval group (level {0}) for Service: {1}" -f $level, $serviceName

            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $desc
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé dans AD à utiliser pour le mécanisme 
              d'approbation des demandes pour un Business Group du tenant ITServices

        IN  : $level            -> Niveau de l'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Le nom du groupe à utiliser pour l'approbation
    #>
    [string] getApproveGroupsADGroupName([int]$level, [bool]$fqdn)
    {
        $groupInfos = $this.getApproveGroupName($level, $this.GROUP_TYPE_GROUPS, $fqdn)
        return $groupInfos.name + [NameGenerator]::AD_GROUP_GROUPS_SUFFIX
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau vec le nom et la description de la policy d'approbation à utiliser

        IN  : $approvalPolicyType   -> Type de la policy :
                                        $global:APPROVE_POLICY_TYPE__ITEM_REQ
                                        $global:APPROVE_POLICY_TYPE__ACTION_REQ
       
        RET : Tableau avec:
            - Nom de la policy
            - Description de la policy
    #>
    [System.Collections.ArrayList] getApprovalPolicyNameAndDesc([string]$approvalPolicyType)
    {
        
        $name = ""
        $desc = ""

        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                if($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ITEM_REQ)
                {
                    $name_suffix = "newItems"
                    $type_desc = "new items"
                }
                elseif($approvalPolicyType -eq $global:APPROVE_POLICY_TYPE__ACTION_REQ)
                {
                    $name_suffix = "2ndDay"
                    $type_desc = "2nd day actions"
                }
                else 
                {
                    Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
                }
        
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $name_suffix
                $desc = "Approval policy for {0} for {1} Faculty" -f $type_desc, $this.getDetail('facultyName').ToUpper()
            }


            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $type_desc = ""
                $suffix = ""
                switch($approvalPolicyType)
                {
                    $global:APPROVE_POLICY_TYPE__ITEM_REQ
                    {
                        $suffix = "newItems"
                        $type_desc = "new items"
                    }

                    $global:APPROVE_POLICY_TYPE__ACTION_REQ
                    {
                        $suffix = "2ndDay"
                        $type_desc = "2nd day actions"
                    }

                    default
                    {
                        Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
                    }

                }
        
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName')), $suffix
                $desc = "Approval policy for {0} for Service: {1}" -f $type_desc, $this.getDetail('serviceName')
            }


            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return @($name, $desc)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description d'un Entitlement pour le tenant

        RET : Tableau avec :
                - Nom de l'Entitlement
                - Description de l'entitlement
    #>
    [System.Collections.ArrayList] getBGEntNameAndDesc()
    {
        $name = $this.getEntName()
        $desc = $this.getEntDescription()

        return @($name, $desc)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description du Security Group (NSX) pour une faculté donnée

        IN  : $bgName   -> Le nom du BG lié au Business Group

        RET : Tableau avec :
                - Le nom du NS Group
                - La description du NS Group
    #>
    [System.Collections.ArrayList] getSecurityGroupNameAndDesc([string]$bgName)
    {
        $name = ""
        $desc = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $name = "sg.epfl_{0}" -f $this.sanitizeFacultyName($this.getDetail('facultyName')).ToLower()
                $desc = "Tenant: {0}\nFaculty: {1}" -f $this.tenant, $this.getDetail('facultyName')
            }


            $global:VRA_TENANT__ITSERVICES
            {
                $name = "sg.its_{0}" -f $this.getDetail('serviceShortName')
                $desc = "Tenant: {0}\nBusiness Group: {1}\nSNOWID: {2}" -f $this.tenant, $bgName, $this.getDetail('snowServiceId')
            }


            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        
        return @($name, $desc)
    }
    

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du security tag (NSX) pour une faculté donnée

        IN  : $facultyName      -> Le nom court de la faculté
        
        RET : Le nom du NS Group
    #>
    [string] getSecurityTagName()
    {
        $tagName = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $tagName = "st.epfl_{0}" -f $this.sanitizeFacultyName($this.getDetail('facultyName')).ToLower()
            }

            
            $global:VRA_TENANT__ITSERVICES
            {
                $tagName = "st.its_{0}" -f $this.getDetail('serviceShortName')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $tagName

    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom et la description de la section de firewall (NSX)

        RET : Tableau avec :
                - Le nom de la section de firewall
                - La description de la section de firewall
    #>
    [System.Collections.ArrayList] getFirewallSectionNameAndDesc()
    {
        $name = ""
        $desc = ""

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $name = "epfl_{0}" -f $this.sanitizeFacultyName($this.getDetail('facultyName'))
                $desc = "Section for Tenant {0} and Faculty {1}" -f $this.tenant, $this.getDetail('facultyName').toUpper()
            }


            $global:VRA_TENANT__ITSERVICES
            {
                $name = "its_{0}" -f $this.getDetail('serviceShortName')
                $desc = "Section for Tenant {0} and Service {1}" -f $this.tenant, $this.getDetail('serviceShortName')
            }


            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }

        }

        return @($name.ToLower(), $desc)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la liste des noms de "rules" pour une section de firewall
        
        RET : Tableau avec :
                - Tableau associatif pour la Rule "in"
                - Tableau associatif pour la Rule "intra"¨
                - Tableau associatif pour la Rule "out"
                - Tableau associatif pour la Rule "deny"
    #>
    [System.Collections.ArrayList] getFirewallRuleNames()
    {
        $ruleMiddle = ""

        switch($this.tenant)
        {

            $global:VRA_TENANT__EPFL
            {
                $ruleMiddle = $this.sanitizeFacultyName($this.getDetail('facultyName')).ToLower()
            }


            $global:VRA_TENANT__ITSERVICES
            {
                $ruleMiddle = $this.getDetail('serviceShortName')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        # Création des noms de règles
        $ruleNameList = @()

        $ruleNameList += "allow-{0}-in" -f $ruleMiddle
        $ruleNameList += "allow-intra-{0}-comm" -f $ruleMiddle        
        $ruleNameList += "allow-{0}-out" -f $ruleMiddle
        $ruleNameList += "deny-{0}-all" -f $ruleMiddle

        # Création de la liste avec nom et Tag (qui est le nom mais tronqué)
        $ruleList = @()
        Foreach($ruleName in $ruleNameList)
        {
            $ruleList += @{name   = $ruleName
                           tag    = truncateString -str $ruleName -maxChars 32}    
        }

        return $ruleList
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le DN de l'OU Active Directory à utiliser pour mettre les groupes 
              de l'environnement et du tenant courant.

        IN  : $onlyForTenant -> $true|$false pour dire si on veut l'OU pour un groupe
                                    qui sera utilisé par tous les tenants et pas qu'un seul.  

		RET : DN de l'OU
    #>
    [string] getADGroupsOUDN([bool]$onlyForTenant)
    {
        
        $tenantOU = ""
        # Si le groupe que l'on veut créer dans l'OU doit être dispo pour le tenant courant uniquement, 
        if($onlyForTenant)
        {
            $tenantOU = "OU="
            switch($this.tenant)
            {
                $global:VRA_TENANT__DEFAULT { $tenantOU += "default"}
                $global:VRA_TENANT__EPFL { $tenantOU += "EPFL"}
                $global:VRA_TENANT__ITSERVICES { $tenantOU += "ITServices"}
            }
            # On a donc : OU=<tenant>, 
            $tenantOU += ","
        }

        $envOU = ""
        switch($this.env)
        {
            $global:TARGET_ENV__DEV {$envOU = "Dev"}
            $global:TARGET_ENV__TEST {$envOU = "Test"}
            $global:TARGET_ENV__PROD {$envOU = "Prod"}
        }

        # Retour du résultat 
        return '{0}OU={1},OU=XaaS,OU=DIT-Services Communs,DC=intranet,DC=epfl,DC=ch' -f $tenantOU, $envOU
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
            $global:TARGET_ENV__DEV {return 'd'}
            $global:TARGET_ENV__TEST {return 't'}
            $global:TARGET_ENV__PROD {return 'p'}
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
            $global:VRA_TENANT__DEFAULT { return 'def'}
            $global:VRA_TENANT__EPFL { return 'epfl'}
            $global:VRA_TENANT__ITSERVICES { return 'its'}
        }
        return ""
    } 

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le préfixe de machine à utiliser pour une faculté ou un service

		RET : Préfixe de machine
    #>
    [string] getVMMachinePrefix()
    {
        $facultyNameOrServiceShortName = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                $facultyNameOrServiceShortName = $this.getDetail('facultyName')
            }

            $global:VRA_TENANT__ITSERVICES 
            { 
                $facultyNameOrServiceShortName = $this.getDetail('serviceShortName')
            }
        }

        # Suppression de tous les caractères non alpha numériques
        $facultyNameOrServiceShortName = $facultyNameOrServiceShortName -replace '[^a-z0-9]', ''

        # On raccourci à 6 caractères pour ne pas avoir des préfixes trop longs
        $facultyNameOrServiceShortName = $facultyNameOrServiceShortName.Substring(0, [System.Math]::Min(6, $facultyNameOrServiceShortName.length))

        # Pour l'ID court de l'environnement 
        $envId = ""
        
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                # Si on n'est pas sur la prod, on ajoutera l'id cour de l'environnement
                if($this.env -ne $global:TARGET_ENV__PROD)
                {
                    $envId = $this.getEnvShortName()
                }
                return "{0}{1}vm" -f $this.transformFacultyForGroupName($facultyNameOrServiceShortName), $envId
            }
            
            $global:VRA_TENANT__ITSERVICES 
            { 
                # Si on n'est pas sur la prod, on ajoutera l'id cour de l'environnement
                if($this.env -ne $global:TARGET_ENV__PROD)
                {
                    $envId = "-{0}" -f $this.getEnvShortName()
                }
                return "{0}{1}-" -f $this.transformForGroupName($facultyNameOrServiceShortName) , $envId
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        return ""
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un BG du tenant EPFL

		RET : Description du BG
    #>
    [string] getBGDescription()
    {
        $desc = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                $desc = "Faculty: {0}`nUnit: {1}" -f $this.getDetail('facultyName').toUpper(), $this.getDetail('unitName').toUpper()
            }

            $global:VRA_TENANT__ITSERVICES 
            {
                $desc = "" 
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        return $desc
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 

		RET : Description du BG
    #>
    [string] getEntName()
    {
        $name = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $this.transformForGroupName($this.getDetail('unitName'))
            }

            $global:VRA_TENANT__ITSERVICES 
            {
                $name = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName')) 
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }

        }
        return $name
    }    


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement
              
		RET : Description de l'entitlement
    #>
    [string] getEntDescription()
    {
        $desc = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                $desc = "Faculty: {0}`nUnit: {1}" -f $this.getDetail('facultyName').toUpper(), $this.getDetail('unitName').toUpper()
            }

            $global:VRA_TENANT__ITSERVICES 
            {
                $desc = "Service: {0}" -f $this.getDetail('serviceName')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        return $desc
    }    


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un BG en fonction des paramètres passés.

        RET : Le nom du BG à utiliser
    #>
    [string] getBGName()
    {
        $name = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $this.transformForGroupName($this.getDetail('unitName'))
            }

            $global:VRA_TENANT__ITSERVICES
            {
                $name = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName'))
            }

            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $name
    }

    
    <# ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
                                                        FONCTIONS UTILISABLES SANS CONFIGURATION DE LA CLASSE VIA LA FONCTION 'initDetails()'
       ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------#>

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
        $result = @()
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                # Le nom du groupe devait avoir la forme :
                # vra_<envShort>_<facultyID>_<unitID>

                if($partList.Count -lt 4)
                {
                    Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
                }

                $result = @($partList[2], $partList[3])
            }

            # ITServices 
            $global:VRA_TENANT__ITSERVICES
            {
                # Le nom du groupe devait avoir la forme :
                # vra_<envShort>_<serviceShortName>
                
                if($partList.Count -lt 3)
                {
                    Throw ("Incorrect group name ({0}) for Tenant {1}" -f $ADGroupName, $this.tenant)
                }

                $result = @($partList[2])
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }
        return $result
    }

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

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                # Le nom du groupe devait avoir la forme :
                # <facultyNam>;<unitName>;<financeCenter>

                if($partList.Count -lt 3)
                {
                    Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
                }

            }

            $global:VRA_TENANT__ITSERVICES
            {
                # Le nom du groupe devait avoir la forme :
                # <snowServiceId>;<serviceName>;<financeCenter>
                
                if($partList.Count -lt 3)
                {
                    Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
                }

                $partList = @($partList)
            }

            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $partList

    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie la base du nom de Reservation à utiliser pour un BG
              
        IN  : $bgName       -> Le nom du BG
        IN  : $clusterName  -> Le nom du cluster pour lequel on veut la Reservation

        RET : Le nom de la Reservation
    #>
    [string] getBGResName([string]$bgName, [string]$clusterName)
    {
        $resName = ""

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                # Le nom du BG a la structure suivante :
                # epfl_<faculty>_<unit>[_<info1>[_<info2>...]]

                # Le nom de la Reservation est généré comme suit
                # <tenantShort>_<faculty>_<unit>[_<info1>[_<info2>...]]_<cluster>

                $resName = "{0}_{1}" -f $bgName, $this.transformForGroupName($clusterName)
            }

            $global:VRA_TENANT__ITSERVICES
            {
                # Le nom du BG a la structure suivante :
                # its_<serviceShortName>

                # Le nom de la Reservation est généré comme suit
                # <tenantShort>_<serviceShortName>_<cluster>
                
                $resName = "{0}_{1}" -f $bgName, $this.transformForGroupName($clusterName)
            }

            default
            {
                Throw("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $resName
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
        if($groupShortName.EndsWith([NameGenerator]::AD_DOMAIN_NAME))
        {
            return $groupShortName
        }
        else 
        {
            return $groupShortName += ("@{0}" -f [NameGenerator]::AD_DOMAIN_NAME)
        }
    }

    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du directory qui permet de faire la synchro des groupes AD
                dans vRA

        RET : Le nom du directory
    #>
    [string]getDirectoryName()
    {
        return [NameGenerator]::AD_DOMAIN_NAME
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le préfix utilisé pour les Templates de Reservation pour le tenant 
              courant

        RET : Le préfix
    #>
    [string] getReservationTemplatePrefix()
    {
        return "template_{0}_" -f $this.getTenantShortName()
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin d'accès (UNC) pour aller dans le dossier des ISO privées
              d'un BG dont le nom est donné en paramètre.
              On reprend simplement le nom du serveur et le share CIFS qui sont définis dans
              define.inc.ps1 et on y ajoute le nom du tenant et le nom du BG.

        IN  : le nom du BG pour lequel on veut le dossier de stockage des ISO

        RET : Le chemin jusqu'au dossier NAS des ISO privée. Si pas dispo, on retourne une chaîne vide.
    #>
    [string] getNASPrivateISOPath([string]$bgName)
    {
        switch($this.env)
        {
            $global:TARGET_ENV__PROD
            {
                return ([IO.Path]::Combine($global:NAS_PRIVATE_ISO_PROD, $this.tenant, $bgName))    
            }

            $global:TARGET_ENV__TEST
            {
                return ([IO.Path]::Combine($global:NAS_PRIVATE_ISO_TEST, $this.tenant, $bgName))
            }

            $global:TARGET_ENV__DEV
            {
                return ""
            }
        }
       return ""
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin d'accès (UNC) pour aller dans le dossier racine des ISO privées
              de l'environnement courant

        RET : Le chemin jusqu'au dossier racine NAS des ISO privée. Si pas dispo, on retourne une chaîne vide.
    #>
    [string] getNASPrivateISORootPath()
    {
        return $this.getNASPrivateISOPath("")
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du BG qui est lié au chemin UNC passé en paramètre. A savoir que l'utilisateur
              peut créer des sous-dossiers dans le dossier du BG.

        IN  : Le chemin UNC depuis lequel il faut récupérer le nom du BG. ça peut être le chemin jusqu'à un dossier
              ou simplement jusqu'à un fichier ISO

        RET : Le nom du BG
    #>
    [string] getNASPrivateISOPathBGName([string]$path)
    {
        # Le chemin a le look suivant \\<server>\<share>\<tenant>\<bg>[\<subfolder>[\<subfolder>]...][\<isoFilename>]

        # On commence par virer le début du chemin d'accès
        $cleanPath = $path -replace [regex]::Escape($this.getNASPrivateISORootPath()), ""

        # Split du chemin
        $pathParts = $cleanPath.Split("\")

        # Retour du premier élément de la liste qui n'est pas vide, ça sera d'office le nom du BG
        ForEach($part in $pathParts)
        {
            if($part -ne "")
            {
                return $part
            }
        }

        # Si on arrive ici, c'est qu'on n'a pas trouvé donc erreur 
        Throw ("Error extracting BG name from given path '{0}'" -f $path)
    }

}