. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "Counters.inc.ps1"))


<#
    BUT: Permet de savoir si une hashtable et un PSCustomObject (qui est traité de la même manière qu'une
        hashtable) sont identiques

    IN  : $hashtable    -> Hashtable à comparer
    IN  : $object       -> Objet à comparer        

    RET : $true -> identiques
        $false -> différents
#>
function identicalDicts([Hashtable]$hashtable, [PSCustomObject]$object)
{
    $allOK = $true

    # On contrôle que les infos présentes dans le retour attendu soit également
    # présentes dans la valeur retournée
    ForEach($property in $object.PSObject.Properties)
    {
        
        if($hashtable.Keys -notcontains $property.name)
        {
            $allOK = $false
            break
        }
        # La propriété existe, on check donc sa valeur
        elseif ($hashtable[$property.Name] -ne $property.value)
        {
            $allOK = $false
            break
        }

    }
    
    # On ne fait les check qui suivent que si on est bon jusqu'à présent
    if($allOK)
    {
        ForEach($key in $hashtable.keys)
        {
            if( ($object.PSObject.Properties | Where-Object { $_.name -eq $key} ).count -eq 0)
            {
                $allOK = $false
                break
            }
            # La propriété existe, on check donc sa valeur
            elseif ($hashtable[$key] -ne $object.$key)
            {
                $allOK = $false
                break
            }

        }
    }

    return $allOK
    
}


function identicalArrays([Object[]]$arrayA, [Object[]]$arrayB)
{
    $allOK = $true

    if($arrayA.Count -ne $arrayB.Count)
    {
        $allOK = $false
    }

    if($allOK)
    {
        $index = 0
        While($index -lt $arrayA.Count)
        {

            if($arrayA[$index].GetType().name -eq 'Hashtable')
            {
                $allOK = identicalDicts -hashtable $arrayA[$index] -object $arrayB[$index]
            }
            elseif ($arrayA[$index] -ne $arrayB[$index])
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
    
    return $allOK
    
} 


function checkFuncCall([string]$funcName, [PSCustomObject]$testInfos, [int]$testNo, [PSCustomObject]$onObject)
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
    $cmd = "`$onObject.{0}({1})" -f $funcName, ($formattedParams -join ",")

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

# ------------------------------------------------------------------------------

$counters = [Counters]::new()
$counters.add('ok', 'Passed')
$counters.add('ko', 'Errors')

<#
    BUT : Exécute les tests qui sont présents dans un fichier JSON dont le chemin est passé en paramètre

    IN  : $jsonTestFile -> Chemin jusqu'au fichier JSON contenant les tests
    IN  : $onObject     -> Objet (intance de classe) sur lequelle effectuer les tests.   
#>
function execTests([string]$jsonTestFile, [PSCustomObject]$onObject)
{
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
            if(checkFuncCall -funcName $funcInfos.name -testInfos $test -testNo $testNo -onObject $onObject)
            {
                $counters.inc('ok')
            }
            else
            {
                $counters.inc('ko')
            }
            $testNo++
        }
        Write-Host ""
    }
}

# Création de l'objet sur lequel exécuter les tests.
$nameGenerator = [NameGenerator]::new('test', 'epfl')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-epfl.json"))
execTests -jsonTestFile $jsonFile -onObject $nameGenerator

$nameGenerator = [NameGenerator]::new('test', 'itservices')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-itservices.json"))
execTests -jsonTestFile $jsonFile -onObject $nameGenerator

$counters.display("Test results")
