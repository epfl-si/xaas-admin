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

 

# ------------------------------------------------------------------------------

$counters = [Counters]::new()
$counters.add('ok', 'Passed')
$counters.add('ko', 'Errors')



# Création de l'objet sur lequel exécuter les tests.
$nameGenerator = [NameGenerator]::new('test', 'epfl')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-epfl.json"))
execTests -jsonTestFile $jsonFile -onObject $nameGenerator

$nameGenerator = [NameGenerator]::new('test', 'itservices')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-itservices.json"))
execTests -jsonTestFile $jsonFile -onObject $nameGenerator

$counters.display("Test results")
