

class ClassTester
{
    hidden [Counter] $counter # Pour compter les erreurs et succès des tests
    hidden [PSCustomObject] $targetObject # Objet sur lequel on fait les tests

    ClassTester([Counter]$counter)
    {
        $this.counter = $counter
    }


    <#
        BUT : Exécute les tests qui sont présents dans un fichier JSON dont le chemin est passé en paramètre

        IN  : $jsonTestFile -> Chemin jusqu'au fichier JSON contenant les tests
        IN  : $onObject     -> Objet (intance de classe) sur lequelle effectuer les tests.   
    #>
    [void] execTests([string]$jsonTestFile, [PSCustomObject]$onObject)
    {
        $this.targetObject = $onObject
        try {
            $testList = (Get-Content -Path $jsonTestFile -raw) | ConvertFrom-Json    
        }
        catch {
            Write-Error ("Error loading JSON file {0}" -f $jsonTestFile)
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

        BUT : Contrôle que l'appel à une fonction de l'objet $this.targetObject, avec les informations de tests donnée, se déroule correctement

        IN  : $funcName     -> Nom de la fonction à tester 
        IN  : $testInfos    -> Dictionnaire avec les informations du test à effectuer
        IN  : $testNo       -> No du test à effectuer pour la fonction courante

        RET :   $true   -> Test réussi
                $false  -> Test lamentablement foiré, tel une tartine qui tombe du côté de la confiture
    #>
    hidden [bool] checkFuncCall([string]$funcName, [PSCustomObject]$testInfos, [int]$testNo)
    {
        # Création de la liste des paramètres 
        $formattedParams = @()
    
        Foreach($param in $testInfos.params)
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
    
        # Rendu de l'appel à la fonction 
        $cmd = "`$this.targetObject.{0}({1})" -f $funcName, ($formattedParams -join ",")
    
        $returnedValue = Invoke-Expression $cmd
    
        $allOK = $true
    
        # Si c'est un tableau associatif
        if($returnedValue.GetType().Name -eq 'Hashtable')
        {
            # On compare les dictionnaires (un au format Hashtable et l'autre en PSCustomObject )
            $allOK = identicalDicts -hashtable $returnedValue -object $testInfos.expected
    
        }
        # C'est un tableau
        elseif($returnedValue.getType().Name -eq "Object[]")
        {
            $allOK = identicalArrays -arrayA $returnedValue -arrayB $testInfos.expected
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

    
}