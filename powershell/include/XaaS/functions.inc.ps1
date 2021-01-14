<#
   BUT : Contient les fonctions utilisées par les différents scripts XaaS

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2019

   ----------
   HISTORIQUE DES VERSIONS
   28.08.2019 - 1.0 - Version de base
#>
<#
-------------------------------------------------------------------------------------
    BUT : Renvoie l'objet à utiliser pour effectuer l'affichage du résultat d'exécution 
            du script
#>
function getObjectForOutput
{
    return @{
            error = ""
            results = @()
        }
}

<#
-------------------------------------------------------------------------------------
    BUT : Affiche le résultat de l'exécution en JSON
    
    IN  : $output -> objet (créé à la base avec getObjectForOutput) contenant le 
                        résultat à afficher
#>
function displayJSONOutput([psobject]$output)
{
    Write-Host ($output | ConvertTo-Json -Depth 100)
}