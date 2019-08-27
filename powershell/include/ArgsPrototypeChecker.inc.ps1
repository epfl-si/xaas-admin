
<#
   BUT : Contient une classe permetant de contrôler que l'utilisation d'un script corresponde
         aux arguments passés pour l'exécuter. Ce fichier doit juste être inclus dans un script
         à contrôler, juste après le header qui décrit les paramètres.
         Ce header doit se trouver entre < # et # >  (sans les espaces les espaces entre les 
         caractères) et il peut contenir plusieurs lignes de possibilités d'utilisation du 
         script. Les règles pour noter les utilisations sont les suivantes :
         - Chaque utilisation doit commencer par le nom du script seul (pas de ./ avant)
         - Il est possible de mettre une utilisation sur plusieurs lignes
         - Ne pas ajoute des espaces inutiles, même si ça augmente la lisibilité
         
         Exemple:

         test.ps1 -action setBackupTag -tag (<tag>|"")
         test.ps1 -action new -name <name> [-verbose]
         [-newLineSwitch]
         test.ps1 -action list
         test.ps1 -action get -name <name>

         Ce qui n'est PAS SUPPORTÉ:
         - Les groupes "OR" d'arguments. Dans ce cas-là, il faut faire X ligne de possibilité d'utilisation
         ... (-arg1 <value1>|-arg2 <value2>)

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2019

   TODO: 
   - Stocker quelque part la dernière erreur rencontrée puis l'ajouter dans l'exception propagée

   ----------
   HISTORIQUE DES VERSIONS
   20.08.2019 - 1.0 - Version de base
#>
class ArgsPrototypeChecker
{
    hidden [Array]$allowedUsages    # Utilisations possibles du scripts avec les arguments 
    hidden [String]$usages          # Chaine de caractères des "usages" telle que présente dans le header
    hidden [Array]$scriptCallUsage  # Manière dont le script est appelé

    # Informations sur le script 
    hidden [String]$scriptCallName  # Nom du script
    hidden [String]$scriptCallPath  # Chemin jusqu'au script
    hidden [String]$scriptCallArgs  # Arugments passés pour l'appel

    # Pour le nom du groupe d'argument courant. Cela permet de gérer un argument qui est un "ou". Ex:
    # (-arg1 <value1>|-arg2 <value2>)
    # TODO: Utiliser les données membres suivantes car pour le moment, ça a été laissé en suspend
    hidden [String]$currentArgGroupName
    hidden [int]$nbArgGroupFound
    

    <#
	-------------------------------------------------------------------------------------
      BUT : Créer une instance de l'objet.
            On n'a pas besoin d'informations explicites sur le script à contrôler car
            elles sont toutes trouvables en regardant l'appel qui a été fait.
	#>
    ArgsPrototypeChecker()
    {
        # On extrait les informations depuis la ligne de commande 
        $scriptCall = (Get-Variable MyInvocation -Scope 0).Value.Line.TrimStart(@(".")).Trim()

        # Extraction du nom du script (il se trouve entre ' dans la chaîne $scriptCall)
        $this.scriptCallPath = [Regex]::Match($scriptCall, "'.*?'")
        # Extraction des arguments avec lesquels le script a été appelé
        $this.scriptCallArgs = ($scriptCall -Replace [Regex]::Escape($this.scriptCallPath), "").Trim()
        # On nettoie le chemin jusqu'au script (car il contient toujours des ')
        $this.scriptCallPath = $this.scriptCallPath.Trim(@("'"))

        # Extraction du nom du script
        $this.scriptCallName = Split-Path $this.scriptCallPath -leaf
        
        $this.allowedUsages = @()

        $this.currentArgGroupName = $null
        $this.nbArgGroupFound = 0
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse les arguements possibles pour l'utilisation (usage) passée en paramètre

      IN  : $usage  -> Chaîne de caractères représentant une utilisation possible du script.
                        Celle-ci provient du heander du script.

      RET : Tableau avec la liste des arguments    
	#>
    hidden [Array] parseUsageArgs([string]$usage)
    {
        # Pour les informations que l'on va retourner
        $usageArgsInfos = @{nbMandatoryArgs = 0
                            Args = @()}

        # Extraction des arguments (et des valeurs potentielles)
        $usageArgs = $usage.Split(" ") 

        # Parcours des arguments du Usage courant
        For($argIndex=0; $argIndex -lt $usageArgs.Count; $argIndex++)
        {
            $argInfos = @{Name = ""               # Nom de l'argument 
                          Values = @()          # Tableau avec valeurs possibles, si harcodée: "-arg value"  ou alors "-arg value1|value2"
                                                # $null = n'importe quelle valeur sauf chaine vide.
                                                # Si ce tableau est vide, c'est que c'est un switch
                          Mandatory = $true       # Pour dire si obligatoire
                          groupName = $null}      # Nom du groupe de paramètre 
                          
            
            $arg = $usageArgs[$argIndex].Trim(@(" ", "`t"))

            # Si c'est un argument optionnel
            # Ex [-targetEnv
            if($arg.StartsWith("["))
            {
                $argInfos.Mandatory = $false

                # On nettoie l'argument pour enlever les [ ]
                # [-targetEnv] -> -targetEnv
                # [-targetEnv  -> -targetEnv  (si pas Switch)
                $arg = $arg.trim(@("[", "]"))
            }
            
            # TODO: Code volontairement commenté car on ne gère pas encore ceci pour le moment, c'est un peu trop complexe
            # à mettre en place à première vue
            # Si on tombe sur groupe d'arguments,
            # Ex: (-targetEnv 
            # if($arg.StartsWith("(-"))
            # {
            #     # Si on est déjà dans un groupe d'arguments, on propage une exception
            #     if($this.currentArgGroupName -ne "")
            #     {
            #         Throw ("Nested argument groups not supported ({0})" -f $arg)
            #     }
            #     # Initialisation du nom du groupe 
            #     $this.currentArgGroupName = "argGroup{0}" -f $this.nbArgGroupFound
            #     $this.nbArgGroupFound +=1

            #     # Nettoyage
            #     # (-targetEnv  -> -targetEnv
            #     $arg = $arg.trim(@("("))
            # }

            # Si c'est un argument (et pas une valeur )
            # Ex: -targetEnv
            if($arg.StartsWith("-"))
            {
                $argInfos.Name = $arg
                # Mise à jour du groupe potentiel dans lequel se trouve l'argument
                $argInfos.groupName = $this.currentArgGroupName             

                $usageArgsInfos.args += $argInfos

                # Si c'est un argument obligatoire et qu'on n'est pas dans un groupe d'arguments
                if($argInfos.Mandatory -and ($this.currentArgGroupName -eq ""))
                {
                    $usageArgsInfos.nbMandatoryArgs += 1   
                }

            }
            else # C'est une valeur 
            {
                # Si plusieurs valeurs possible et que celles-ci ont été mises entre ( )
                if($arg.StartsWith("("))
                {
                    # On fait un peu de nettoyage 
                    $arg = $arg.Trim(@("(", ")"))
                }

                # Parcours des valeurs possibles (s'il y en a plusieurs )
                $arg.Split("|") | ForEach-Object {
                    # Si c'est une valeur hardcodée
                    if(!($_.StartsWith("<")))
                    {
                        # Initialisation de la valeur autorisée
                        $allowedValue = $_
                    }
                    else
                    {
                        # On initialise avec $null pour dire que n'importe quelle valeur (sauf chaine vide) est autorisée
                        $allowedValue = $null
                    }

                    # On l'assigne à l'argument précédemment rencontré 
                    $usageArgsInfos.Args[$usageArgsInfos.Args.Count -1].Values += $allowedValue

                }# FIN BOUCLE de parcours des valeurs possibles 

            }# FIN SI c'est une valeur


        }# FIN BOUCLE de parcours des arguments du Usage courant

        # Mise à jour du nombre d'arguments obligatoires en additionnant le nombre de groupes rencontrés aux arguments obligatoires rencontrés
        $usageArgsInfos.nbMandatoryArgs += $this.nbArgGroupFound

        return $usageArgsInfos
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Détermine si l'argument d'utilisation passé (pour une utilisation donnée) 
            est OK par rapport aux arguments passés au script pour son exécution

      IN  : $allowedUsageArgInfos  -> Informations sur l'argument (d'une utilisation donnée) 
                                        que l'on veut contrôler

      RET : $true|$false pour dire si c'est OK ou pas.
	#>
    hidden [bool] callArgIsCorrect($allowedUsageArgInfos)
    {
        # Parcours des arguments utilisés pour appeler le script
        ForEach($callArg in $this.scriptCallUsage.Args)
        {
            # Si on tombe sur un argument d'une utilisation du script qui correspond 
            if($callArg.Name -eq $allowedUsageArgInfos.Name)
            {
                # Si l'argument est un switch, pas besoin de faire plus de check, on est bon
                if($allowedUsageArgInfos.Values.Count -eq 0)
                {
                    return $true
                }

                # Arrivé ici, c'est que l'argument n'est pas un switch, il faut donc
                # contrôler les valeurs autorisées pour celui-ci s'il y en a

                # Parcours des valeurs autorisées 
                ForEach($allowedValue in $allowedUsageArgInfos.Values)
                {
                    # Si on peut mettre n'importe quelle valeur sauf "" et que
                    # la valeur de l'argument (index 0 de .Values) n'est pas ""
                    # OU 
                    # Si la valeur de l'appel correspond à une autorisée
                    if( (($null -eq $allowedValue) -and ($callArg.Values[0] -ne "")) -or 
                        ($callArg.Values[0] -eq $allowedValue))
                    {
                        return $true
                        Break
                    }

                }# FIN BOUCLE de parcours des valeurs autorisées
                
            }# FIN SI on tombe sur l'arguement qui a le même nom 

        }# FIN BOUCLE de parcours des arguments utilisés pour l'appel du script

        # Si on arrive ici, c'est qu'on n'a pas trouvé l'argument de l'appel dans ceux autorisé pour l'utilisation possible donnée
        return $false
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse le header du script afin d'extraire les différentes utilisations qui y sont
            mentionnées et analyse ensuite celles-ci
	#>
    [void] parseScriptHeader()
    {
        # Extraction du header
        $this.usages = ([Regex]::Matches((Get-content $this.scriptCallPath), "<#.*?#>"))[0]

        # Lecture de l'entête du script et parcours des "usages"
        $this.usages -Split $this.scriptCallName | ForEach-Object {
            
            # Nettoyage de la ligne du usage courant
            $cleanedUsage = ([String]$_).Trim(@("<", ">", "#", " ", "`t"))

            # Si après nettoyage il reste quelque chose du Usage... 
            if($cleanedUsage -ne "" )
            {
                
                <# On ajoute les informations du Usage courant à la liste. La virgule n'est pas une faute de frappe,
                elle permet d'ajouter le nouvel élément comme étant un nouvel élément du tableau $usages. Si on ne
                la met pas, ça va simplement fusionner le tableaux $usages et $currentUsageParams, et on ne veut pas ça...#>
                $this.allowedUsages += , $this.parseUsageArgs($cleanedUsage)

            }# FIN SI il reste quelque chose du Usage après nettoyage 

        }# FIN BOUCLE de parcours des Usages
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Parse l'appel du script pour extraire les informations
	#>
    [void] parseScriptCall()
    {
        $this.scriptCallUsage = $this.parseUsageArgs($this.scriptCallArgs)
    }


    <#
	-------------------------------------------------------------------------------------
      BUT : Valide que l'appel au script est correct
	#>
    [void] validateScriptCall()
    {
        $callOk = $false

        # Parcours des utilisations possibles
        ForEach($allowedUsage in $this.allowedUsages)
        {

            $nbArgsOK = 0

            # Parcours des arguments possibles pour l'utilisation courante 
            Foreach($allowedUsageArgInfos in $allowedUsage.Args) 
            {
                # Si l'argument est OK dans l'appel qui a été fait au script
                if($this.callArgIsCorrect($allowedUsageArgInfos))
                {
                    $nbArgsOK += 1
                }
            } # FIN boucle parcours des arguments possibles 

            # Si on a trouvé un match pour l'appel du script
            if($nbArgsOK -ge $allowedUsage.nbMandatoryArgs)
            {
                $callOk = $true
                # on peut sortir de la boucle 
                Break
            }

        }# FIN BOUCLE parcours des utilisations possibles 


        if(!$callOk)
        {
            Throw ("Incorrect arguments given. Usage is: {0}" -f $this.usages)
        }
    }

}

$argsChecker = [ArgsPrototypeChecker]::New()
$argsChecker.parseScriptHeader()


<# Arrivé ici, le paramètre $usages contient un descritif des possibilités d'utilisation du script telle que définies dans le header de celui-ci
   On peut maintenant passer à la partie où on parcours ces Usages afin de voir si l'utilisation qui est faite du script est correcte ou pas #>


$argsChecker.parseScriptCall()
$argsChecker.validateScriptCall()

