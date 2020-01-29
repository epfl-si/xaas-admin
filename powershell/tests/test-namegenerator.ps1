. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ClassTester.inc.ps1"))






 

# ------------------------------------------------------------------------------

$counters = [Counters]::new()
$counters.add('ok', 'Passed')
$counters.add('ko', 'Errors')

$classTester = [ClassTester]::new($counters)

# Création de l'objet sur lequel exécuter les tests.
$nameGenerator = [NameGenerator]::new('test', 'epfl')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-epfl.json"))
$classTester.runTests($jsonFile, $nameGenerator)

$nameGenerator = [NameGenerator]::new('test', 'itservices')
$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-itservices.json"))
$classTester.runTests($jsonFile, $nameGenerator)

$classTester.getCounters().display("Test results")
