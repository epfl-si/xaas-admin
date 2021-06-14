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
function displayJSONOutput
{
    param([psobject]$output)

    Write-Host ($output | ConvertTo-Json -Depth 100)
}



<#
    -------------------------------------------------------------------------------------
    BUT : Renvoie les groupes d'accès à utiliser pour donner les droits sur un cluster

    IN  : $vra          -> Objet permettant d'accéder à vRA
    IN  : $bg           -> Objet représentant le Business Group auquel le cluster est lié
    IN  : $targetTenant -> Tenant sur lequel se trouve le BusinessGroup

    RET : Tableau avec la liste des groupes d'accès à utiliser
        $null si pas trouvé
#>
function getBGAccessGroupList([vRAAPI]$vra, [PSObject]$bg, [string]$targetTenant)
{
    if($null -eq $bg)
    {
        Throw "Business Group cannot be NULL"
    }
    <# On explose l'infos <group>@intranet.epfl.ch pour n'extraire que le nom du groupe
        Récupération des utilisateurs qui ont le droit de demander des cluster, ça sera ceux
        qui pourront gérer le cluster #>
        # FIXME: Trouver par quoi remplacer "CSP_CONSUMER"
    $userAndGroupList = $vra.getBGRoleContent($bg.id, "CSP_CONSUMER")
    $groupName, $null = $userAndGroupList[0] -split '@'

    # Si on est dans le tenant ITS
    if($targetTenant -eq $global:VRA_TENANT__ITSERVICES)
    {
        # Récupération de la liste des groupes qui sont présents dans le 1er groupe qui est dans les CONSUMER du BusinessGroup
        # NOTE: On fait ceci car TKGI/Harbor ne gèrent pas les groupes nested... 
        # FIXME: A supprimer une fois que TKGI/Harbor pourra gérer le groupes nested
        $accessGroupList = Get-ADGroupMember $groupName | Where-Object { $_.objectClass -eq "group"} | Select-Object -ExpandProperty name

    }
    else # Autres tenants
    {
        # On prent le groupe tel quel
        $accessGroupList = @($groupName)
    }

    return $accessGroupList
}