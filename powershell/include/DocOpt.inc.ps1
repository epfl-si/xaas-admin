
class ParamChecker
{
    hidden [Array]$allowedUsages
    hidden [String]$scriptName
    hidden [String]$scriptPath
    hidden [String]$scriptParams

    ParamChecker()
    {
        # On extrait les informations depuis la ligne de commande 
        $scriptCall = (Get-Variable MyInvocation -Scope 0).Value.Line.TrimStart(@(".")).Trim()

        # Extraction du nom du script 
        $this.scriptPath = [Regex]::Match($scriptCall, "'.*?'")
        $this.scriptParams = ($scriptCall -Replace [Regex]::Escape($this.scriptPath), "").Trim()
        # On nettoie le chemin jusqu'au script (car il contient toujours des ')
        $this.scriptPath = $this.scriptPath.Trim(@("'"))

        $this.scriptName = Split-Path $this.scriptPath -leaf
        # Tableau avec les paramètres passés au script 
        
        $this.allowedUsages = @()
    }


    hidden [Array] parseUsage([string]$usage)
    {
        $currentUsageParams = @()

        # Extraction des paramètres (et des valeurs potentielles)
        $params = $usage.Split(" ") 

        $currentGroup = $null

        # Parcours des paramètres du Usage courant
        For($i=0; $i -lt $params.Count; $i++)
        {
            $paramInfos = @{Name = ""               # Nom du paramètre 
                            Values = @()          # Tableau avec valeurs possibles, si harcodée: "-param value"  ou alors "-param value1|value2"
                                                # $null = n'importe quelle valeur sauf chaine vide.
                            isSwitch = $false       # Pour dire si c'est un switch
                            mandatory = $true       # Pour dire si obligatoire
                            orGroupName = $null}    # Nom du groupe OR dans le cas de (-param1 <value1> | -param2 <value2>)

            
            $param = $params[$i].Trim(@(" ", "`t"))

            # Si c'est un paramètre optionnel
            if($param.StartsWith("["))
            {
                $paramInfos.mandatory = $false

                # On nettoie le paramètre pour enlever les [ ]
                $param = $param.trim(@("[", "]"))

                # Si c'est optionnel, ça peut être un switch, donc on regarde s'il y a un espace dans la chaine
                $paramInfos.isSwitch = $param -notlike "* *"
            }

            # Si c'est un paramètre (et pas une valeur )
            if($param.StartsWith("-"))
            {
                $paramInfos.Name = $param

                $currentUsageParams += $paramInfos
            }
            else # C'est une valeur 
            {
                # Si plusieurs valeurs possible et que celles-ci ont été mises entre ( )
                if($param.StartsWith("("))
                {
                    # On fait un peu de nettoyage 
                    $param = $param.Trim(@("(", ")"))
                }

                # Parcours des valeurs possibles (s'il y en a plusieurs )
                $param.Split("|") | ForEach-Object {
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

                    # On l'assigne au paramètre précédemment rencontré 
                    $currentUsageParams[$currentUsageParams.Count -1].Values += $allowedValue

                }# FIN BOUCLE de parcours des valeurs possibles 

            }# FIN SI c'est une valeur

        }# FIN BOUCLE de parcours des paramètres du Usage courant

        return $currentUsageParams
    }


    [void] parseScriptHeader()
    {
        # Lecture de l'entête du script et parcours des "usages"
        ([Regex]::Matches((Get-content $this.scriptPath), "<#.*?#>"))[0] -Split $this.scriptName | ForEach-Object {
            
            # Nettoyage de la ligne du usage courant
            $cleanedUsage = ([String]$_).Trim(@("<", ">", "#", " ", "`t"))

            # Si après nettoyage il reste quelque chose du Usage... 
            if($cleanedUsage -ne "" )
            {
                
                <# On ajoute les informations du Usage courant à la liste. La virgule n'est pas une faute de frappe,
                elle permet d'ajouter le nouvel élément comme étant un nouvel élément du tableau $usages. Si on ne
                la met pas, ça va simplement fusionner le tableaux $usages et $currentUsageParams, et on ne veut pas ça...#>
                $this.allowedUsages += , $this.parseUsage($cleanedUsage)

            }# FIN SI il reste quelque chose du Usage après nettoyage 

        }# FIN BOUCLE de parcours des Usages
    }


    [void] check()
    {

    }

}

$paramChecker = [ParamChecker]::New()
$paramChecker.parseScriptHeader()
<# Arrivé ici, le paramètre $usages contient un descritif des possibilités d'utilisation du script telle que définies dans le header de celui-ci
        On peut maintenant passer à la partie où on parcours ces Usages afin de voir si l'utilisation qui est faite du script est correcte ou pas #>
$paramChecker.check()

