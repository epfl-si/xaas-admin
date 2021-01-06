<#
USAGES:
	test-namegenerator.ps1
#>
<#
	BUT 		: Teste la classe NameGenerator

	DATE 		: Janvier 2020
	AUTEUR 	    : Lucien Chaboudez

	REMARQUE : Avant de pouvoir exécuter ce script, il faudra changer la ExecutionPolicy
				  via Set-ExecutionPolicy. Normalement, si on met la valeur "Unrestricted",
				  cela suffit à correctement faire tourner le script. Mais il se peut que
				  si le script se trouve sur un share réseau, l'exécution ne passe pas et
				  qu'il soit demandé d'utiliser "Unblock-File" pour permettre l'exécution.
				  Ceci ne fonctionne pas ! A la place il faut à nouveau passer par la
				  commande Set-ExecutionPolicy mais mettre la valeur "ByPass" en paramètre.
#>
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "define.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "functions.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGeneratorBase.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "NameGenerator.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "..", "include", "Counters.inc.ps1"))
. ([IO.Path]::Combine("$PSScriptRoot", "include", "ClassTester.inc.ps1"))

# Objet pour effectuer les tests
$classTester = [ClassTester]::new()

# ------------------------------------------
# Tests pour le tenant EPFL

$nameGenerator = [NameGenerator]::new('test', 'epfl')

$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-epfl.json"))
$classTester.runTests($jsonFile, $nameGenerator)

# # ------------------------------------------
# # Tests pour le tenant ITServices

$nameGenerator = [NameGenerator]::new('test', 'itservices')

$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-itservices.json"))
$classTester.runTests($jsonFile, $nameGenerator)

# # # ------------------------------------------
# # # Tests pour le tenant Reserach

$nameGenerator = [NameGenerator]::new('test', 'research')

$jsonFile = ([IO.Path]::Combine("$PSScriptRoot", "test-namegenerator-research.json"))
$classTester.runTests($jsonFile, $nameGenerator)

# Affichage des résultats
$classTester.getResults().display("Test results")
