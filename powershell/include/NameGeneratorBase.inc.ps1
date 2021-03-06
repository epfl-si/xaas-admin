<#
   BUT : Classe fournissant quelques fonctions de base pour l'infrastructure vRA et ayant pour but d'être
            dérivée par d'autres classe pour vRA ou des éléments XaaS spécifiques
         

   AUTEUR : Lucien Chaboudez
   DATE   : Octobre 2020

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - include/define.inc.ps1
   - vra-config.inc.ps1



#>

enum DeploymentTag 
{
    Production
    Test
    Development
    # On n'a pas la possibilité de mettre $null à une variable de ce type pour dire qu'elle n'est pas 
    # initialisée. Donc on ajoute cette possibilité au type
    UnInitialized
}

class NameGeneratorBase
{
    hidden [string]$tenant  # Tenant sur lequel on est en train de bosser 
    hidden [string]$env     # Environnement sur lequel on est en train de bosser.
    
    # Détails pour la génération des différents noms. Sera initialisé via 'initDetails' pour mettre à jour
    # les informations en fonction des noms à générer.
    hidden [System.Collections.IDictionary]$details 

    hidden [DeploymentTag]$deploymentTag

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
                           $VRA_TENANT_RESEARCH

		RET : Instance de l'objet
	#>
    NameGeneratorBase([string]$env, [string]$tenant)
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

        $this.deploymentTag = [DeploymentTag]::UnInitialized
    }


    <#
      -------------------------------------------------------------------------------------
        BUT : Initialise le tag de déploiement

        IN  : $deploymentTag -> Environnement du cluster, au niveau logique, pas au niveau 
                              infrastructure
                              prod|test|dev
    #>
    [void] initDeploymentTag([DeploymentTag]$deploymentTag)
    {
        $this.deploymentTag = $deploymentTag
    }


    <#
      -------------------------------------------------------------------------------------
        BUT : Renvoie le deployment tag en contrôlant s'il est initialisé

        RET : valeur du deployment tag
    #>
    hidden [DeploymentTag] getDeploymentTag()
    {
        if($this.deploymentTag -eq [DeploymentTag]::UnInitialized)
        {
            Throw "DeploymentTag not initialized!"
        }
        return $this.deploymentTag
    }


    <#
      -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court du tag de déploiement

        RET : caractère représentant le nom court
    #>
    [string] getDeploymentTagShortname()
    {
        return $this.getDeploymentTag().ToString().ToLower()[0]
    }


    <#
    -------------------------------------------------------------------------------------
        BUT : Renvoie les détails d'un élément en fonction du nom du BG passé en paramètre

        IN  : $bgName   -> Nom du BG

        RET : Objet avec un contenu différent en fonction du tenant sur lequel on est:

            EPFL:
                .faculty
                .unit
            ITServices
                .serviceShortName
            Research
                .projectId
    #>
    [PSObject] getDetailsFromBGName([string]$bgName)
    {   
        $result = $null

        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            {
                # Le nom du BG est au format: epfl_<fac>_<unit>
                $dummy, $faculty, $unit = [regex]::Match($bgName, '^epfl_([a-z]+)_([a-z0-9_]+)').Groups | Select-Object -ExpandProperty value
                
                if($null -eq $faculty -or $null -eq $unit)
                {
                    Throw ("Wrong BG name given ({0}) for {1} Tenant" -f $bgName, $this.tenant)
                }

                $result = @{
                    faculty = $faculty.toLower()
                    # On remet les "-" dans le nom d'unité si besoin
                    unit = ($unit -replace "_", "-").toLower()
                }
            }
            

            $global:VRA_TENANT__ITSERVICES
            {
                # Le nom du BG est au format: its_<serviceShortName>
                $dummy, $serviceShortName = [regex]::Match($bgName, '^its_([a-z0-9]+)').Groups | Select-Object -ExpandProperty value

                if($null -eq $serviceShortName)
                {
                    Throw ("Wrong BG name given ({0}) for {1} Tenant" -f $bgName, $this.tenant)
                }

                $result = @{
                    serviceShortName = $serviceShortName
                }
            }


            $global:VRA_TENANT__RESEARCH
            {
                # Le nom du BG est au format: rsrch_<projectId>
                $dummy, $projectId = [regex]::Match($bgName, '^rsrch_([0-9]+)').Groups | Select-Object -ExpandProperty value

                if($null -eq $projectId)
                {
                    Throw ("Wrong BG name given ({0}) for {1} Tenant" -f $bgName, $this.tenant)
                }

                $result = @{
                    projectId = $projectId
                }
            }


            default 
            {
                Throw ("Tenant not handled ({0})" -f $this.tenant)
            }
        }

        return $result
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : initialise UNE PARTIE des détails depuis le nom du business group passé.
                Ceci permet d'utiliser UNIQUEMENT un sous ensemble des fonctions définies
                dans cette classe car d'autres détails manqueront. A la base, on peut initialiser
                les détails depuis le nom du BG pour pouvoir utiliser les fonctions suivante 
                mais peut-être que d'autres peuvent aussi fonctionner:
                - getVMMachinePrefix 
                - getApprovalPolicyNameAndDesc

        IN  : $bg           -> Objet représentant le BG
    #>
    [void] initDetailsFromBG([PSCustomObject]$bg)
    {
        $bgCustomId = getBGCustomPropValue -bg $bg -customPropName $global:VRA_CUSTOM_PROP_EPFL_BG_ID

        $bgDetails = $this.getDetailsFromBGName($bg.name)

        $withDetails = @{}
        switch($this.tenant)
        {
            # Tenant EPFL
            $global:VRA_TENANT__EPFL 
            { 
                
                # le nom du BG est au format <tenantShort>_<faculty>_<unit>
                $withDetails = @{
                    facultyName = $bgDetails.faculty
                    facultyID = ''
                    unitName = $bgDetails.unit
                    unitID = $bgCustomId
                }
            }

            # Tenant ITServices
            $global:VRA_TENANT__ITSERVICES 
            { 
                # le nom du BG est au format <tenantShort>_<serviceShort>
                $withDetails = @{
                    serviceShortName = $bgDetails.serviceShortName
                    serviceName = $bg.description
                    snowServiceId = $bgCustomId
                }
            }

            # Tenant Research
            $global:VRA_TENANT__RESEARCH
            {
                # le nom du BG est au format <tenantShort>_<projectId>
                $withDetails = @{
                    projectId = $bgDetails.projectId
                    projectAcronym = $bg.description
                }
            }

            # Tenant pas géré
            default
            {
                Throw ("Unsupported Tenant ({0})" -f $this.tenant)
            }
        }

        $this.initDetails($withDetails)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : initialise les détails nécessaires pour utiliser les fonctions ci-dessous.
                On devra ensuite passer par la fonction 'getDetails' pour récupérer une des valeurs.
                Les informations passées ici ne sont QUE celles qui sont utilisées pour la génération 
                des noms. Pour les autres fonctions comme la génération de descriptions textuelles, 
                là, on admettra que des informations complémentaires peuvent être passées directement
                à la fonction qui génère la description.

        IN  : $details          -> Dictionnaire avec les détails nécessaire. Le contenu varie en fonction du tenant 
                                    passé lors de l'instanciation de l'objet.

                                    EPFL:
                                        facultyName      -> Le nom de la faculté du Business Group
                                        facultyID        -> ID de la faculté du Business Group
                                        unitName         -> Nom de l'unité
                                        unitID           -> ID de l'unité du Business Group
                                    
                                    ITServices:
                                        serviceShortName    -> Nom court du service
                                        serviceName         -> Nom long du service
                                        snowServiceId       -> ID du service dans ServiceNow
                                    
                                    Research:
                                        projectId       -> Id du projet
                                        projectAcronym  -> Acronyme du projet
    #>
    [void] initDetails([System.Collections.IDictionary]$details)
    {
        $keysToCheck = @()
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL 
            {
                $keysToCheck = @('facultyName', 'facultyID', 'unitName', 'unitID')
            }

            $global:VRA_TENANT__ITSERVICES
            {
                $keysToCheck = @('serviceShortName', 'serviceName', 'snowServiceId')
            } 

            $global:VRA_TENANT__RESEARCH
            {
                $keysToCheck = @('projectId', 'projectAcronym')
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
                        Voir l'entête de la fonction 'initDetails' pour savoir quels sont les
                        possibilités pour le paramètre $name

        RET : La valeur du détail
    #>
    hidden [PSObject] getDetail([string]$name)
    {
        if(!$this.details.ContainsKey($name))
        {
            Throw ("Asked detail ({0}) doesn't exists in list" -f $name)
        }
        elseif($this.details.$name -eq "")
        {
            Throw ("Asked detail ({0}) has empty value" -f $name)
        }

        return $this.details.$name
    }


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


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie le nom court du tenant.
              Ceci est utilisé pour la génération des noms des groupes

		RET : Nom court du tenant
    #>
    hidden [string] getTenantShortName()
    {
        $res = switch($this.tenant)
        {
            $global:VRA_TENANT__DEFAULT { 'def' }
            $global:VRA_TENANT__EPFL { 'epfl' }
            $global:VRA_TENANT__ITSERVICES { 'its' }
            $global:VRA_TENANT__RESEARCH { 'rsrch'}
            default { '' }
        }
        
        return $res
    } 
    

    <#
        -------------------------------------------------------------------------------------
        BUT : Transforme et renvoie une chaîne de caractère (un nom) pour supprimer les caractères indésirables
                Les - vont être supprimés

        IN  : $name     -> chaîne de caractères à "nettoyer"
        IN  : $maxChars -> Le nombre max de caractères de la chaine

        RET : La chaine corrigée
    #>
    hidden [string]sanitizeName([string]$name)
    {
        return $name.replace("-", "")
    }
    hidden [string]sanitizeName([string]$name, [int]$maxChars)
    {
        $name = $this.sanitizeName($name)
        return (truncateString -str $name -maxChars $maxChars)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la lettre de début pour un tenant

        RET : La lettre de début
    #>
    hidden [string] getTenantStartLetter()
    {
        $start = ""
        switch($this.tenant)
        {
            $global:VRA_TENANT__EPFL
            {
                $start = "u"
            }

            $global:VRA_TENANT__RESEARCH
            {
                $start = "p"
            }
        }

        return $start
    }
}