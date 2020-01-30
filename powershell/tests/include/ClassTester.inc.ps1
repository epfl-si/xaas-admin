<#
   BUT : Permet d'effectuer des tests sur une autre classe en appelant ses fonctions avec 
        des paramètres donnés et en regardant si le résultat correspond à ce qui est attendu.
        Les tests à effectuer sont décrits dans un fichier JSON dont la structure est la suivante :

        [
            {
                "name": "<nomDeLaFonctionATester>",
                "tests": [
                    {
                        "params": ["<strParam>", <intParam>, <boolParam>],
                        "expected": "<retourStr>"
                    },
                    {
                        "params": ["<strParam>", <intParam>, <boolParam>],
                        "expected": [ "<retourStr>", <retourInt> ]
                    },
                    {
                        "params": ["<strParam>", <intParam>, <boolParam>],
                        "expected": { 
                            "<key1>": "<retourStr>",
                            "<key2>": <retourInt>
                            }
                    },
                    ...

                ]
            },
            ...
        ]

        On peut passer des paramètres Int, Bool ou String pour le moment, le tout, dans une liste.
        Au niveau des valeurs de retour, on gère les valeurs "simples" (Int, String, Bool) ou les
        éléments plus complexes comme des listes (Array) ou des Dictionnaires (Hashtable ou IDictionary).
        Plusieurs tests peuvent être mis pour une fonction donnée.
         

   AUTEUR : Lucien Chaboudez
   DATE   : Janvier 2020

   Prérequis:
   Les fichiers doivent avoir été inclus au programme principal avant que le fichier courant puisse être inclus.
   - ../include/define.inc.ps1
   - ../include/functions.inc.ps1
   - ../include/NameGenerator.inc.ps1
   - ../include/Counters.inc.ps1

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class ClassTester
{
    hidden [Counters] $counters # Pour compter les erreurs et succès des tests
    hidden [PSCustomObject] $targetObject # Objet sur lequel on fait les tests

    ClassTester()
    {
        $this.counters = [Counters]::new()
        $this.counters.add('ok', 'Passed')
        $this.counters.add('ko', 'Errors')
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'objet Counters permettant de savoir combien de tests ont passé/échoué
    #>
    [Counters]getResults()
    {
        return $this.counters
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Exécute les tests qui sont présents dans un fichier JSON dont le chemin est passé en paramètre.
                Les résultats de chaque test seront affichés à l'écran et un compteur de test
                réussi/échoués sera mis à jour. Celui-ci pourra être interrogé via la fonction
                getResults()

        IN  : $jsonTestFile -> Chemin jusqu'au fichier JSON contenant les tests
        IN  : $onObject     -> Objet (intance de classe) sur lequelle effectuer les tests.   
    #>
    [void] runTests([string]$jsonTestFile, [PSCustomObject]$onObject)
    {
        $this.targetObject = $onObject
        try {
            $testList = (Get-Content -Path $jsonTestFile -raw) | ConvertFrom-Json    
        }
        catch {
            Write-Error ("Error loading JSON file {0}`n{1}" -f $jsonTestFile, $_)
            exit
        }
        
        # Parcours des fonction à contrôler
        foreach($funcInfos in $testList)
        {
            Write-Host $funcInfos.name
            $testNo = 1
            foreach($test in $funcInfos.tests)
            {
                if($this.checkFuncCall($funcInfos.name, $test, $testNo))
                {
                    $this.counters.inc('ok')
                }
                else
                {
                    $this.counters.inc('ko')
                }
                $testNo++
            }
            Write-Host ""
        }
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Formate les paramètres pour qu'ils puissent être directement inclus dans la 
                génération d'une commande (string) qui sera appelée via Invoke-Expression

        IN  : $paramList    -> Tableau avec la liste des paramètres

        RET : Tableau avec la liste des paramètres pouvant être directement mis dans un string.
    #>
    hidden [Array] formatParameters([Array]$paramList)
    {
        # Création de la liste des paramètres 
        $formattedParams = @()
    
        Foreach($param in $paramList)
        {
            if($param.GetType().Name -eq 'Boolean')
            {
                $formattedParams += ("`${0}" -f $param.ToString().toLower() )
            }
            elseif ($param.GetType().Name -eq 'String')
            {
                $formattedParams += ("'{0}'" -f $param)
            }
            elseif($param.GetType().Name -eq 'Int32')
            {
                $formattedParams += ("{0}" -f $param)
            }
            else 
            {
                Throw ("Param type ({0}) not handled" -f $param.GetType().Name)    
            }
        }
        return $formattedParams
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Contrôle que l'appel à une fonction de l'objet $this.targetObject, avec les informations de tests donnée, se déroule correctement

        IN  : $funcName     -> Nom de la fonction à tester 
        IN  : $testInfos    -> Dictionnaire avec les informations du test à effectuer
        IN  : $testNo       -> No du test à effectuer pour la fonction courante

        RET :   $true   -> Test réussi
                $false  -> Test lamentablement foiré, tel une tartine qui tombe du côté de la confiture
    #>
    hidden [bool] checkFuncCall([string]$funcName, [PSCustomObject]$testInfos, [int]$testNo)
    {
        $formattedParams = $this.formatParameters($testInfos.params)
    
        # Rendu de l'appel à la fonction 
        $cmd = "`$this.targetObject.{0}({1})" -f $funcName, ($formattedParams -join ",")
    
        $returnedValue = Invoke-Expression $cmd
    
        $allOK = $true
    
        # Si c'est un tableau associatif
        if($returnedValue.GetType().Name -eq 'Hashtable')
        {
            # On compare les dictionnaires (un au format Hashtable et l'autre en PSCustomObject )
            $allOK = $this.identicalDicts($returnedValue, $testInfos.expected)
    
        }
        # C'est un tableau
        elseif($returnedValue.getType().Name -eq "Object[]")
        {
            $allOK = $this.identicalArrays($returnedValue, $testInfos.expected)
        }
        else # Int, String, Bool
        {
    
            if($returnedValue -ne $testInfos.expected)
            {
                $allOK = $false
            }
        }
    
        # Affichage du résultat
        if($allOK)
        {
            $msg = "[{0}] (returned) {1} == {2} (expected)" -f $testNo, ($returnedValue | Convertto-json), ($testInfos.expected | convertto-json)
            Write-Host -ForegroundColor:DarkGreen $msg
        }
        else
        {
            $msg = "[{0}] (returned) {1} != {2} (expected)" -f $testNo, ($returnedValue | Convertto-json), ($testInfos.expected | convertto-json)
            Write-Host -ForegroundColor:Red $msg
        }
    
        return $allOK
    }


    <#
        -------------------------------------------------------------------------------------
        BUT: Permet de savoir si une hashtable et un PSCustomObject (qui est traité de la même manière qu'une
            hashtable) sont identiques

        IN  : $fromFunc    -> Element renvoyé par la fonction que l'on est en train de tester.
        IN  : $fromJSON    -> Element présent dans le fichier JSON avec les valeurs pour les tests.

        RET : $true -> identiques
            $false -> différents
    #>
    hidden [bool] identicalDicts([Hashtable]$fromFunc, [PSCustomObject]$fromJSON)
    {
        $allOK = $true

        # On contrôle que les infos présentes dans le retour attendu soit également
        # présentes dans la valeur retournée
        ForEach($property in $fromJSON.PSObject.Properties)
        {
            
            if($fromFunc.Keys -notcontains $property.name)
            {
                $allOK = $false
                break
            }
            # La propriété existe, on check donc sa valeur
            elseif ($fromFunc[$property.Name] -ne $property.value)
            {
                $allOK = $false
                break
            }
        }
        
        # On ne fait les check qui suivent que si on est bon jusqu'à présent
        if($allOK)
        {
            ForEach($key in $fromFunc.keys)
            {
                # Si la propriété n'existe pas dans l'objet, 
                if( ($fromJSON.PSObject.Properties | Where-Object { $_.name -eq $key} ).count -eq 0)
                {
                    $allOK = $false
                    break
                }
                # La propriété existe, on check donc sa valeur
                elseif ($fromFunc[$key] -ne $fromJSON.$key)
                {
                    $allOK = $false
                    break
                }
            }
        }
        return $allOK
    }


    <#
        -------------------------------------------------------------------------------------
        BUT: Permet de savoir si deux tableaux d'objets sont identiques

        IN  : $fromFunc    -> Element renvoyé par la fonction que l'on est en train de tester.
        IN  : $fromJSON    -> Element présent dans le fichier JSON avec les valeurs pour les tests.

        RET : $true -> identiques
            $false -> différents
    #>
    hidden [bool] identicalArrays([Object[]]$fromFunc, [Object[]]$fromJSON)
    {
        $allOK = $true

        # Si les tailles des tableaux sont différentes, on n'est déjà pas bien.
        if($fromFunc.Count -ne $fromJSON.Count)
        {
            $allOK = $false
        }

        if($allOK)
        {
            $index = 0
            While($index -lt $fromFunc.Count)
            {
                # Si l'élément courant est un dictionnaire, 
                if($fromFunc[$index].GetType().name -eq 'Hashtable')
                {
                    # On compare au niveau "dictionnaire"
                    $allOK = $this.identicalDicts($fromFunc[$index], $fromJSON[$index])
                }
                # Valeur simple de type Int, Bool, String
                elseif ($fromFunc[$index] -ne $fromJSON[$index])
                {
                    $allOK = $false
                }

                if(!$allOK)
                {
                    break
                }
                $index++
            }
        }
        return $allOk
    } 
}