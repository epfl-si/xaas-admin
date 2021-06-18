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

# Types d'OU qui peut se trouver dans une OU de tenant.
enum ADSubOUType
{
    Approval
    Support
    User
}

class NameGenerator: NameGeneratorBase
{
    

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
    NameGenerator([string]$env, [string]$tenant): base($env, $tenant)
    {
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
        BUT : Transforme et renvoie le nom de faculté passée pour qu'il corresponde
                aux attentes du nommage des groupes et autres. 
                Les - vont être supprimés et tout sera mis en minuscule

        IN  : $facultyName -> Le nom de la faculté

        RET : La chaine corrigée
    #>
    hidden [string]transformFacultyForGroupName([string]$facultyName)
    {
        return $this.sanitizeName($facultyName).ToLower()
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

        IN  : $role                 -> Le rôle
        IN  : $type                 -> Type du nom du groupe:
                                        $this.GROUP_TYPE_AD
                                        $this.GROUP_TYPE_GROUPS
        IN  : $fqdn                 -> Pour dire si on veut le nom avec le nom de domaine après.
                                        $true|$false  
        IN  : $additionalDetails    -> (optionel) tableau associatif avec les détails additionnels
                                        à ajouter au format JSON à la description du groupe    
        
                
        RET : Liste avec :
            - Nom du groupe à utiliser pour le rôle.
            - Description du groupe (si $type == 'ad', sinon, "")
    #>
    hidden [System.Collections.ArrayList] getRoleGroupNameAndDesc([UserRole]$role, [string]$type, [bool]$fqdn, [Hashtable]$additionalDetails)
    {
        # On initialise à vide car la description n'est pas toujours générée. 
        $groupDesc = ""
        $groupName = ""

        <# "Mais WTF? à quoi sert cette ligne?" me direz-vous? bah.. simplement quand on converti un tableau en JSON,
            le 'convertTo-Json ne créé pas simplement un tableau mais il fait un DICT avec un champ 'value' qui est le tableau
            et un champ 'count' avec le nombre d'éléments... 
            Exécuter la ligne de commande suivante permet d'avoir une "vraie" transformation en JSON.
            Ce workaround a été trouvé ici:
            https://stackoverflow.com/questions/20848507/why-does-powershell-give-different-result-in-one-liner-than-two-liner-when-conve/38212718#38212718
        #>
        Remove-TypeData System.Array

        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            {
                # Admin
                if($role -eq [UserRole]::Admin)
                {
                    # Même nom de groupe (court) pour AD et "groups"
                    # vra_<envShort>_adm_<tenantShort>
                    $groupName = "{0}{1}_adm_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                    $groupDesc = "Administrators for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
                }
                # Support
                elseif($role -eq [UserRole]::Support)
                {
                    # Même nom de groupe (court) pour AD et "groups"
                    # vra_<envShort>_sup_<facultyName>
                    $groupName = "{0}{1}_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName'))
                    $groupDesc = "Support for Faculty {0} on Tenant {1} on Environment {2}" -f $this.getDetail('facultyName').toUpper(), $this.tenant.ToUpper(), $this.env.ToUpper()
                }
                # Shared, Users
                elseif($role -eq [UserRole]::User)
                {
                    # Groupe AD
                    if($type -eq $this.GROUP_TYPE_AD)
                    {
                        # vra_<envShort>_<facultyID>_<unitID>
                        $groupName = "{0}{1}_{2}_{3}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getDetail('facultyID'), $this.getDetail('unitID')
                        # Informations encodées en JSON
                        $descStruct = @{
                            faculty = $this.getDetail('facultyName').toUpper()
                            unit = $this.getDetail('unitName').toUpper()
                        }
                        # Ajout des détails additionnels potentiels et encodage en JSON
                        $groupDesc =  ($descStruct + $additionalDetails) | ConvertTo-Json -Compress -Depth 20
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
                if($role -eq [UserRole]::Admin -or $role -eq [UserRole]::Support)
                {
                    # vra_<envShort>_adm_sup_its
                    $groupName = "{0}{1}_adm_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                    $groupDesc = "Administrators/Support for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
                    
                }
                # Shared, Users
                elseif($role -eq [UserRole]::User)
                {
                    # vra_<envShort>_<serviceId>
                    $groupName = "{0}{1}_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($this.getDetail('snowServiceId').toLower())

                    # Groupe AD
                    if($type -eq $this.GROUP_TYPE_AD)
                    {
                        # Information encodée en JSON
                        # On utilise uniquement le nom du service et pas une chaine de caractères avec d'autres trucs en plus comme ça, celui-ci peut être ensuite
                        # réutilisé pour d'autres choses dans la création des éléments dans vRA
                        $descStruct = @{
                            svcShortName = $this.getDetail('serviceShortName').toLower()
                            svcId = $this.getDetail('snowServiceId').ToUpper()
                            svcName = $this.getDetail('serviceName')
                        }
                        # Ajout des détails additionnels potentiels et encodage en JSON
                        $groupDesc =  ($descStruct + $additionalDetails) | ConvertTo-Json -Compress -Depth 20
                    }
                    # Groupe "groups"
                    else
                    {
                        $groupDesc = "To do requests for '{0}' service" -f $this.getDetail('serviceName')
                    }

                }
                # Autre EPFL
                else
                {
                    Throw ("Incorrect value for role : '{0}'" -f $role)
                }
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Admin, Support
                if($role -eq [UserRole]::Admin -or $role -eq [UserRole]::Support)
                {
                    # vra_<envShort>_adm_sup_rsrch
                    $groupName = "{0}{1}_adm_sup_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.getTenantShortName()
                    $groupDesc = "Administrators/Support for Tenant {0} on Environment {1}" -f $this.tenant.ToUpper(), $this.env.ToUpper()
                    
                }
                # Shared, Users
                elseif($role -eq [UserRole]::User)
                {
                    # vra_<envShort>_<projectId>
                    $groupName = "{0}{1}_{2}" -f [NameGenerator]::AD_GROUP_PREFIX, $this.getEnvShortName(), $this.transformForGroupName($this.getDetail('projectId'))

                    # Groupe AD
                    if($type -eq $this.GROUP_TYPE_AD)
                    {
                        # Structure en JSON
                        # On utilise uniquement le nom du service et pas une chaine de caractères avec d'autres trucs en plus comme ça, celui-ci peut être ensuite
                        # réutilisé pour d'autres choses dans la création des éléments dans vRA
                        $descStruct = @{
                            projectAcronym = $this.getDetail('projectAcronym')
                        }
                        # Ajout des détails additionnels potentiels et encodage en JSON
                        $groupDesc =  ($descStruct + $additionalDetails) | ConvertTo-Json -Compress -Depth 20
                    }
                    # Groupe "groups"
                    else
                    {
                        $groupDesc = "To do requests for project {0}" -f $this.getDetail('projectId')
                    }
                    

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
        BUT : Initialise les détails à l'aide d'un objet représentant un groupe AD. On s'attend
                à ce que l'objet contienne au moins les 2 propriétés suivantes:
                - Name
                - Description

        IN  : $adGroup   -> Objet représentant le groupe AD
    #>
    [void] initDetailsFromADGroup([PSCustomObject]$adGroup)
    {
        # Extraction des infos depuis le nom du groupe et la description
        $adGroupDescInfos = $this.extractInfosFromADGroupDesc($adGroup.Description)

        $allDetails = @{}

        # Consolidation de tous les détails
        switch($this.tenant)
        {
            # -- EPFL
            $global:VRA_TENANT__EPFL
            {
                $facultyID, $unitID = $this.extractInfosFromADGroupName($adGroup.Name)

                $allDetails.facultyName = $adGroupDescInfos.faculty
                $allDetails.facultyID = $facultyID
                $allDetails.unitName = $adGroupDescInfos.unit
                $allDetails.unitID = $unitID
            }

            # -- ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $allDetails.serviceShortName = $adGroupDescInfos.svcShortName
                $allDetails.serviceName = $adGroupDescInfos.svcName
                $allDetails.snowServiceId = $adGroupDescInfos.svcId
            }

            # -- Research
            $global:VRA_TENANT__RESEARCH
            {
                $projectId, $dummy = $this.extractInfosFromADGroupName($adGroup.Name)

                $allDetails.projectId = $projectId
                $allDetails.projectAcronym = $adGroupDescInfos.projectAcronym

            }
        }

        $this.initDetails($allDetails)
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les paramètres passés 
              
        IN  : $role             -> Le rôle
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false      
    #>
    [string] getRoleADGroupName([UserRole]$role, [bool]$fqdn)
    {   
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_AD, $fqdn, @{})
        return $groupName
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe AD pour les paramètres passés 

        IN  : $role                 -> Le rôle
        IN  : $additionalDetails    -> (optionel) tableau associatif avec les détails additionnels
                                        à ajouter au format JSON à la description du groupe
    #>
    [string] getRoleADGroupDesc([UserRole]$role)
    {
        return $this.getRoleADGroupDesc($role, @{})
    }
    [string] getRoleADGroupDesc([UserRole]$role, [Hashtable]$additionalDetails)
    {
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_AD, $false, $additionalDetails)
        return $groupDesc
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Le rôle
    #>
    [string] getRoleGroupsGroupName([UserRole]$role)
    {
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_GROUPS, $false, @{})
        return $groupName
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe "GROUPS" pour les paramètres passés 

        IN  : $role             -> Le rôle
    #>
    [string] getRoleGroupsGroupDesc([UserRole]$role)
    {
        $groupName, $groupDesc = $this.getRoleGroupNameAndDesc($role, $this.GROUP_TYPE_GROUPS, $false, @{})
        return $groupDesc
    }


    <# 
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe "GROUPS" dans Active Directory pour les paramètres passés 

        IN  : $role             -> Le rôle
    #>
    [string] getRoleGroupsADGroupName([UserRole]$role)
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
                            et les chefs de service DSI (level 2) qui approuvent les demandes.
        

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

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                if($level -eq 1)
                {
                    $last = "service_manager"
                    $onlyForTenant = $false
                }
                elseif($level -eq 2)
                {
                    $last = $this.getDetail('projectId')
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
        BUT : Renvoie le nom du groupe AD créé pour le mécanisme d'approbation des demandes
              pour un Business Group

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


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe GROUPS créé pour le mécanisme d'approbation des demandes
              pour un Business Group

        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
        IN  : $fqdn             -> Pour dire si on veut le nom avec le nom de domaine après.
                                    $true|$false  
                                    Si pas passé => $false 

        RET : Objet avec les données membres suivantes :
                .name           -> le nom du groupe ou "" si rien pour le $level demandé.    
                .onlyForTenant  -> $true|$false pour dire si c'est uniquement pour le tenant courant ($true) ou pas ($false =  tous les tenants)
    #>
    [PSCustomObject] getApproveGroupsGroupName([int]$level, [bool]$fqdn)
    {
        return $this.getApproveGroupName($level, $this.GROUP_TYPE_GROUPS, $fqdn)
    }

    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe AD pour les approbations en se basant sur un nom de
                groupe pour les utilisateurs qui peuvent faire des demandes. 
                Au vu des nomenclatures, ceci ne fonctionne que pour le tenant Research

        IN  : $ADUserGroupName  -> Nom du groupe contenant les utilisateurs pouvant faire des 
                                    demandes au sein du Business Group

        RET : Nom du groupe d'approbation
    #>
    [string] getApproveADGroupNameFromUserADGroups([string]$ADUserGroupName)
    {
        if($this.tenant -ne $global:VRA_TENANT__RESEARCH)
        {
            Throw ("Only supported for {0} tenant" -f $global:VRA_TENANT__RESEARCH)
        }

        # INFORMATION: Lorsque l'on utilise -match ou -notmatch, PowerShell initialise automatiquement une variable $matches avec les résultats du match
        $ADUserGroupName.ToLower() -match "([a-z_]+)_([0-9]+)" | Out-Null
        return ("{0}_approval_{1}" -f $matches[1], $matches[2])
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description du groupe Groups utilisé pour les approbations des demandes
              pour le tenant.

        IN  : $level            -> Le niveau d'approbation (1, 2, ...)
       
        RET : Description du groupe
    #>
    [string] getApproveGroupsGroupDesc([int]$level)
    {
        $desc = "vRA {0} approval group (level {1})" -f $this.env, $level

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                # Le premier niveau d'approbation est générique à toutes les facultés donc pas de description "précise" pour celui-ci
                if($level -gt 1)
                {
                    $desc = "{0} for Faculty {1}" -f $desc, $this.getDetail('facultyName').ToUpper()
                }
            }

            $global:VRA_TENANT__ITSERVICES
            {
                # NOTE: 15.02.2019 - On n'utilise plue le nom du service dans la description du groupe car c'est maintenant un seul groupe d'approbation
                # pour tous les services 
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Le premier niveau d'approbation est générique à toutes les facultés donc pas de description "précise" pour celui-ci
                if($level -gt 1)
                {
                    $desc = "{0} for Project {1}" -f $desc, $this.getDetail('projectId')
                }
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

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Le premier niveau d'approbation est générique à toutes les facultés donc pas de description "précise" pour celui-ci
                if($level -gt 1)
                {
                    $desc = "{0} for Project: {1}" -f $desc, $this.getDetail('projectId')
                }
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

        IN  : $approvalPolicyType   -> Type de la policy. Voir type enuméré dans "include/define.inc.ps1"
        IN  : $level                -> Le niveau de l'approval policy
       
        RET : Tableau avec:
            - Nom de la policy
            - Description de la policy
    #>
    [System.Collections.ArrayList] getApprovalPolicyNameAndDesc([ApprovalPolicyType]$approvalPolicyType, [int]$level)
    {
        
        $name = ""
        $desc = ""

        $typeDesc = ""
        $suffix = ""

        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                
                switch($approvalPolicyType)
                {
                    NewItem
                    {
                        $suffix = "newItems"
                        $typeDesc = "new items"
                    }

                    Day2Action
                    {
                        $suffix = "2ndDay"
                        $typeDesc = "2nd day actions"
                    }

                    default
                    {
                        Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType.toString()
                    }
                }
        
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $suffix
                $desc = "Approval policy for {0} for {1} Faculty" -f $typeDesc, $this.getDetail('facultyName').ToUpper()
            }


            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                switch($approvalPolicyType)
                {
                    NewItem
                    {
                        $suffix = "newItems"
                        $typeDesc = "new items"
                    }

                    Day2Action
                    {
                        $suffix = "2ndDay"
                        $typeDesc = "2nd day actions"
                    }

                    default
                    {
                        Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
                    }

                }
        
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName')), $suffix
                $desc = "Approval policy for {0} for Service: {1}" -f $typeDesc, $this.getDetail('serviceName')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                switch($approvalPolicyType)
                {
                    NewItem
                    {
                        $suffix = "newItems"
                        $typeDesc = "new items"
                    }

                    Day2Action
                    {
                        $suffix = "2ndDay"
                        $typeDesc = "2nd day actions"
                    }

                    default
                    {
                        Throw "Incorrect Approval Policy type ({0})" -f $approvalPolicyType
                    }

                }
        
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('projectId')), $suffix
                $desc = "Approval policy for {0} for Project: {1}" -f $typeDesc, $this.getDetail('projectId')
            }


            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        # Ajout des infos du level
        $name = "{0}_{1}" -f $name, $level
        $desc = "{0}`nLevel: {1}" -f $desc, $level

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
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                $name = "sg.epfl_{0}" -f $this.sanitizeName($this.getDetail('facultyName')).ToLower()
                $desc = "Tenant: {0}\nFaculty: {1}" -f $this.tenant, $this.getDetail('facultyName')
            }


            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $name = "sg.its_{0}" -f $this.getDetail('serviceShortName')
                $desc = "Tenant: {0}\nBusiness Group: {1}\nSNOWID: {2}" -f $this.tenant, $bgName, $this.getDetail('snowServiceId')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Pour ce tenant, il a été décidé de n'avoir qu'un seul NSGroup pour l'entièreté des éléments
                $name = "sg.rsrch"
                $desc = "Tenant: {0}" -f $this.tenant
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
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                $tagName = "st.epfl_{0}" -f $this.sanitizeName($this.getDetail('facultyName')).ToLower()
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $tagName = "st.its_{0}" -f $this.getDetail('serviceShortName')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Pour ce tenant, c'est le même "security tag" qui sera appliqué à tous les éléments.
                $tagName = "st.rsrch"
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
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                $name = "epfl_{0}" -f $this.sanitizeName($this.getDetail('facultyName'))
                $desc = "Section for Tenant {0} and Faculty {1}" -f $this.tenant, $this.getDetail('facultyName').toUpper()
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $name = "its_{0}" -f $this.getDetail('serviceShortName')
                $desc = "Section for Tenant {0} and Service {1}" -f $this.tenant, $this.getDetail('serviceShortName')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Pour ce tenant, il a été décidé d'avoir une seule section pour tous les projets.
                $name = "rsrch"
                $desc = "Section for Tenant {0}" -f $this.tenant
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
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                $ruleMiddle = $this.sanitizeName($this.getDetail('facultyName')).ToLower()
            }


            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                $ruleMiddle = $this.getDetail('serviceShortName')
            }


            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Pour ce tenant, il a été décidé qu'on avait qu'une seule section et donc des règles uniques pour tous les éléments
                $ruleMiddle = "rsrch"
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
                                        qui sera utilisé pour le tenant courant OU pour tous les tenants

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
                $global:VRA_TENANT__DEFAULT { $tenantOU += "default" }
                $global:VRA_TENANT__EPFL { $tenantOU += "EPFL" }
                $global:VRA_TENANT__ITSERVICES { $tenantOU += "ITServices" }
                $global:VRA_TENANT__RESEARCH { $tenantOU += "Research" }
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


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le DN de l'OU Active Directory à utiliser pour mettre les groupes d'un 
                type donnée dans l'environnement et le tenant courant.

        IN  : $finalOUType          -> (optionnel) Type de l'OU finale

		RET : DN de l'OU
    #>
    [string] getADGroupsOUDN([bool]$onlyForTenant, [ADSubOUType]$finalOUType)
    {
        $result = $this.getADGroupsOUDN($onlyForTenant)

        # Si on veut la chose avec le tenant
        if($onlyForTenant)
        {
            # Dans ce cas-là on peut ajouter la "sous-OU". Sinon, on ne la met pas
            $result = 'OU={0},{1}' -f  $finalOUType.ToString().ToLower(), $result
        }

        return $result
        
    }


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le template pour générer un nom de machine pour une faculté ou un service

		RET : Template pour générer le nom
    #>
    [string] getVMNameTemplate()
    {
        $suffix = "`${####}"

        $detailToUse = ""
        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            { 
                $detailToUse = $this.getDetail('facultyName')
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES 
            { 
                $shortName = $this.getDetail('serviceShortName')
                if($shortName.length -gt 8)
                {
                    # On diminue la longueur en prenant la première la dernière et la lettre du milieu
                    # NOTE: C'est comme ça que vRA 7.x générait visiblement un préfixe de VM
                    $shortName = "{0}{1}{2}" -f $shortName[0], $shortName[[Math]::Floor($shortName.length/2)], $shortName[-1]
                }
                # On utilise le nom du tenant (court) suivi du nom court du service
                # its<serviceShortName>
                $detailToUse = "{0}{1}" -f $this.getTenantShortName(), $shortName
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                $detailToUse = $this.getDetail('projectId')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        # Suppression de tous les caractères non alpha numériques
        $detailToUse = $detailToUse -replace '[^a-z0-9]', ''

        

        # Pour l'ID court de l'environnement 
        $envId = ""
        
        if($this.tenant -eq $global:VRA_TENANT__EPFL -or `
            $this.tenant -eq $global:VRA_TENANT__RESEARCH )
        {
            # On raccourci à 6 caractères pour ne pas avoir des préfixes trop longs
            $detailToUse = $detailToUse.Substring(0, [System.Math]::Min(6, $detailToUse.length)).toLower()

            # Si on n'est pas sur la prod, on ajoutera l'id cour de l'environnement
            if($this.env -ne $global:TARGET_ENV__PROD)
            {
                $envId = $this.getEnvShortName()
            }
            return "{0}{1}vm{2}" -f $detailToUse, $envId, $suffix
        }
        elseif($this.tenant -eq $global:VRA_TENANT__ITSERVICES)
        {
            return "{0}{1}{2}" -f $detailToUse, $envId, $suffix
        }

        return ""
        
    }

    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Project qui est de type "catalogue"

        IN  : $catalogName      -> Le nom du catalogue
        IN  : $catalogPrivacy   -> Niveau de visibilité du catalogue

		RET : Description 
    #>
    [string] getCatalogProjectDescription([string]$catalogName, [CatalogProjectPrivacy]$catalogPrivacy)
    {
        return "{0} CloudTemplates for {1}" -f $catalogPrivacy.toString(), $catalogName
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Project du tenant courant

		RET : Description du Project
    #>
    [string] getProjectDescription()
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
                $desc = $this.getDetail('svcName')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                $desc = $this.getDetail('projectAcronym')
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
        BUT : Renvoie l'expression régulière permettant d'isoler un nom d'entitlement d'un type donné

        IN  : $entType  -> Type de l'entitlement

		RET : Regex
    #>
    [string] getEntNameRegex([EntitlementType]$entType)
    {
       $reg = switch($entType)
        {
            User { '^.*?(?<!_adm)$' }

            Admin { '^.*?_adm$' }
        }

        return $reg
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 

        IN  : $entType  -> Type de l'entitlement

		RET : Description du BG
    #>
    [string] getEntName([EntitlementType]$entType)
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

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                $name = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('projectId')) 
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }

        }

        if($entType -eq [EntitlementType]::Admin)
        {
            $name = "{0}_adm" -f $name
        }

        return $name
    }    


    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>
    <# -------------------------------------------------------------------------------------------------------------------------------------------------------------------------- #>

    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la description d'un Entitlement
        
        IN  : $entType  -> Type de l'entitlement 

		RET : Description de l'entitlement
    #>
    [string] getEntDescription([EntitlementType]$entType)
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

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                $desc = "Project: {0}" -f $this.getDetail('projectId')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        $desc = "{0}`nType: {1}" -f $desc, $entType.toString()
        
        return $desc
    }    


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom à utiliser pour un Projet en fonction des paramètres passés.

        RET : Le nom du Project à utiliser
    #>
    [string] getProjectName()
    {
        $name = ""
        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL
            {
                # epfl_<fac>_<unit>
                $name = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $this.transformForGroupName($this.getDetail('unitName'))
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES
            {
                # its_<serviceShortName>
                $name = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName'))
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # <tenantShort>_<projectId>
                $name = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('projectId'))
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

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Le nom du groupe devait avoir la forme :
                # vra_<envShort>_<projectId>
                
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

        RET : Objet avec un contenu différent selon le tenant
                EPFL:
                    .deniedVRASvc
                    .faculty
                    .unit
                    .financeCenter
                    .hasApproval
                ITServices
                    .deniedVRASvc
                    .svcShortName
                    .svcName
                    .svcId
                    .hasApproval
                Research
                    .projectAcronym
                    .financeCenter
    #>
    [PSCustomObject] extractInfosFromADGroupDesc([string]$ADGroupDesc)
    {
        # Eclatement du nom pour récupérer les informations
        $descStruct = $ADGroupDesc | ConvertFrom-Json

        # On regarde combien il y a d'éléments (au premier niveau uniquement)
        $nbElements = ($descStruct | Get-Member -Type NoteProperty).count

        # Contrôle si les éléments sont OK
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                if($nbElements -lt 5)
                {
                    Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
                }
            }

            $global:VRA_TENANT__ITSERVICES
            {
                if($nbElements -lt 5)
                {
                    Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
                }
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                if($nbElements -lt 2)
                {
                    Throw ("Incorrect group description ({0}) for Tenant {1}" -f $ADGroupDesc, $this.tenant)
                }
            }

            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $descStruct

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
                # its_<serviceShortName>_<cluster>
                
                $resName = "{0}_{1}" -f $bgName, $this.transformForGroupName($clusterName)
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # Le nom du BG a la structure suivante :
                # rsrch_<projectId>

                # Le nom de la Reservation est généré comme suit
                # rsrch_<projectId>_<cluster>
                
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


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom du groupe de https://groups.epfl.ch permettant d'avoir un 
                accès ADMIN Full pour Tableau.

        RET : Le nom du groupe
    #>
    [string] getTableauAdminEPFLADGroup()
    {
        return ("vra_{0}_tableau_epfl_AppGrpU" -f $this.getEnvShortName())
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom de l'entité à utiliser pour identifier le BG dans la facturation

        RET : Le nom de l'entité pour la facturation
    #>
    [string] getBillingEntityName()
    {
        $entityName = ""

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $entityName = $this.getDetail('unitName').ToUpper()
            }

            $global:VRA_TENANT__ITSERVICES
            {   
                $entityName = $this.getDetail('serviceName').ToUpper()
            }

            $global:VRA_TENANT__RESEARCH
            {
                $entityName = $this.getDetail('projectId')
            }

            default
            {
                Throw("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        return $entityName
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le chemin à utiliser dans GitHub pour stocker des éléments de 
                catalogue

        IN  : $catalogName      -> Le nom du catalogue

        RET : Le chemin
    #>
    [string] getGitHubCatalogPath([string]$catalogName)
    {
        return ("CloudTemplates/{0}" -f $catalogName)
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un "Content Source" pour un projet "catalogue" donné

        IN  : $catalogProjectName      -> Le nom du projet "Catalogue"

        RET : Le nom

    #>
    [string] getCatalogProjectContentSourceName([string]$catalogProjectName)
    {
        # On utilise le même nom que le "Catalog Project" comme ça on pourra filtrer facilement par 
        # la suite pour les services "denied"
        return $catalogProjectName
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom d'un Entitlement en fonction du tenant défini. 

        IN  : $policyType   -> Type de la policy
        IN  : $policyRole   -> Role auquel la policy s'applique

		RET : Tableau avec: 
                - Nom de la Policy
                - Description de la Policy
    #>
    [Array] getPolicyNameAndDesc([PolicyType]$policyType, [PolicyRole]$policyRole)
    {
        $nameStart = ""
        $descStart = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            { 
                $nameStart = "{0}_{1}_{2}" -f $this.getTenantShortName(), $this.transformFacultyForGroupName($this.getDetail('facultyName')), $this.transformForGroupName($this.getDetail('unitName'))
                $descStart = "Faculty: {0}`nUnit: {1}" -f $this.getDetail('facultyName').toUpper(), $this.getDetail('unitName').toUpper()
            }

            $global:VRA_TENANT__ITSERVICES 
            {
                $nameStart = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('serviceShortName')) 
                $descStart = "Service: {0}" -f $this.getDetail('serviceName')
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                $nameStart = "{0}_{1}" -f $this.getTenantShortName(), $this.transformForGroupName($this.getDetail('projectId')) 
                $descStart = "Project: {0}" -f $this.getDetail('projectId')
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }

        }

        $typeShortName = ""
        switch($policyType)
        {
            Approval 
            { 
                $typeShortName = "approval" 
            }
            
            Action 
            { 
                $typeShortName = "day2" 
            }

            Lease 
            { 
                $typeShortName = "lease" 
            }
        }

        $nameEnd = ""
        $descEnd = ""
        switch($policyRole)
        {
            Administrator 
            { 
                $nameEnd = "_admin"
                $descEnd = "administrators"
            }

            Member
            { 
                $nameEnd = ""
                $descEnd = "members"
            }

            Infrastructure_Administrator 
            {
                $nameEnd = "_infradmin" 
                $descEnd = "infrastructure administrators"
            }
        }

        return @(
            ("{0}_{1}{2}" -f $nameStart, $typeShortName, $nameEnd),
            ("{0}`nType: {1}`nApplies to: {2}" -f $descStart, $typeShortName, $descEnd)
        )
    }    

}