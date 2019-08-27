
<#
   BUT : Contient une classe permetant de contrôler que l'utilisation d'un script corresponde
         aux arguments passés pour l'exécuter. Ce fichier doit juste être inclus dans un script
         à contrôler, juste après le header qui décrit les paramètres.
         Ce header doit se trouver entre < # et # >  (sans les espaces les espaces entre les 
         caractères) et il peut contenir plusieurs lignes de possibilités d'utilisation du 
         script. Les règles pour noter les utilisations sont les suivantes :
         - Chaque utilisation doit commencer par le nom du script seul (pas de ./ avant)
         - Il est possible de mettre une utilisation sur plusieurs lignes
         
         Exemple:

         test.ps1 -action setBackupTag -tag (<tag>|"")
         test.ps1 -action new -name <name> [-verbose]
         [-newLineSwitch]
         test.ps1 -action list
         test.ps1 -action get -name <name>

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2019

   ----------
   HISTORIQUE DES VERSIONS
   20.08.2019 - 1.0 - Version de base
#>
class ArgsChecker
{
    hidden [Array]$allowedUsages    # Utilisations possibles du scripts avec les arguments 
    hidden [String]$usages          # Chaine de caractères des "usages" telle que présente dans le header
    hidden [Array]$scriptCallUsage  # Manière dont le script est appelé

    # Informations sur le script 
    hidden [String]$scriptCallName  # Nom du script
    hidden [String]$scriptCallPath  # Chemin jusqu'au script
    hidden [String]$scriptCallArgs  # Arugments passés pour l'appel

    <#
	-------------------------------------------------------------------------------------
      BUT : Créer une instance de l'objet.
            On n'a pas besoin d'informations explicites sur le script à contrôler car
            elles sont toutes trouvables en regardant l'appel qui a été fait.
	#>
    ArgsChecker()
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
                          isSwitch = $false       # Pour dire si c'est un switch
                          Mandatory = $true}       # Pour dire si obligatoire
                          
            
            $arg = $usageArgs[$argIndex].Trim(@(" ", "`t"))

            # Si c'est un argument optionnel
            if($arg.StartsWith("["))
            {
                $argInfos.Mandatory = $false

                # On nettoie l'argument pour enlever les [ ]
                $arg = $arg.trim(@("[", "]"))

                # Si c'est optionnel, ça peut être un switch, donc on regarde s'il y a un espace dans la chaine
                $argInfos.isSwitch = $arg -notlike "* *"
            }
            
            # Si c'est un argument (et pas une valeur )
            if($arg.StartsWith("-"))
            {
                $argInfos.Name = $arg

                $usageArgsInfos.args += $argInfos

                # Si c'est un argument obligatoire
                if($argInfos.Mandatory)
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

        return $usageArgsInfos
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


    hidden [bool] callArgIsCorrect($allowedUsageArgInfos)
    {
        # Parcours des arguments utilisés pour appeler le script
        ForEach($callArg in $this.scriptCallUsage.Args)
        {
            # Si on tombe sur un argument d'une utilisation du script qui correspond 
            if($callArg.Name -eq $allowedUsageArgInfos.Name)
            {
                # Si l'argument est un switch, pas besoin de faire plus de check, on est bon
                if($allowedUsageArgInfos.isSwitch)
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

$argsChecker = [ArgsChecker]::New()
$argsChecker.parseScriptHeader()


<# Arrivé ici, le paramètre $usages contient un descritif des possibilités d'utilisation du script telle que définies dans le header de celui-ci
   On peut maintenant passer à la partie où on parcours ces Usages afin de voir si l'utilisation qui est faite du script est correcte ou pas #>


$argsChecker.parseScriptCall()
$argsChecker.validateScriptCall()

