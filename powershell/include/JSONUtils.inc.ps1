<#
   BUT : Offre une série de méthodes permettant d'accéder aux données se trouvant dans un fichier JSON
        qui aura été chargé à la construction de l'objet.

   AUTEUR : Lucien Chaboudez
   DATE   : Février 2019



	REMARQUES :
	

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class JSONUtils
{
    hidden [string]$sourceFilename
    hidden [PSCustomObject]$JSONData


    <#
        -------------------------------------------------------------------------------------
        BUT : Charge les données du fichier JSON passé en paramètre
        
        IN  : $JSONFilename     -> Nom court du fichier JSON à charger
    #>
    JSONUtils([string]$JSONFilename) 
    {
        $this.sourceFilename = $JSONFilename
        $filepath = (Join-Path $global:RESOURCES_FOLDER $JSONFilename)
	
        try 
        {
            # Chargement de la liste des actions depuis le fichier JSON
            $this.JSONData = (Get-Content -Path $filepath) -join "`n" | ConvertFrom-Json
        }
        catch
        {
            Throw (("New items file error : {0}" -f $_.Exception.Message))
        }
    }

    <#
        -------------------------------------------------------------------------------------
        BUT : Cherche un Noeud JSON dans $startNode et qui a un champ $filterField avec la valeur $filterValue.
        
        REMARQUES :
            - On ne fait la recherche quand dans le permier niveau.

        IN  : $startNode    -> Noeud de départ pour la recherche 
        IN  : $filterField  -> Nom du champ à chercher dans les enfants de $startNode
        IN  : $filterValue  -> Valeur que le champ $filterField doit avoir.

        RET : Objet représentant le noeud rechercher 
                $null si pas trouvé
    #>
    [PSObject] getJSONNode([PSObject]$startNode, [String]$filterField, [string]$filterValue)
    {
        ForEach($element in $startNode)
        {
            # Si le champ que l'on recherche existe, 
            if([bool]($element.PSobject.Properties.name -match $filterField))
            {
                if($element.$filterField -eq $filterValue)
                {
                    return $element
                }
            }
            else # Le champ que l'on recherche n'existe pas
            {
                Throw (("JSON Node field not found ({0}) {1}" -f $this.sourceFilename, $filterField))
            }
        }
        return $null;
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la valeur demandée ($valueField) pour un Noeud JSON qui aura été cherché dans
                $startNode et qui aura un champ $filterField avec la valeur $filterValue

        IN  : $startNode    -> Noeud de départ pour la recherche 
        IN  : $filterField  -> Nom du champ à chercher dans les enfants de $startNode
        IN  : $filterValue  -> Valeur que le champ $filterField doit avoir.
        IN  : $valueField   -> Nom du champ contenant la valeur que l'on désire récupérer.
        
        RET : Valeur demandée. Si pas trouvé, une exception est générée.
    #>
    [PSObject] getJSONNodeValue([PSObject]$startNode, [String]$filterField, [string]$filterValue, [string]$valueField)
    {
        # Recherche du noeud avec les critères donnés
        $node = $this.getJSONNode($startNode, $filterField, $filterValue)

        # Si le noeud n'a pas été trouvé, 
        if($null -eq $node)
        {
            Throw (("JSON Node not found ({0}). {1}={2}" -f $this.sourceFilename, $filterField, $filterValue))
        }

        # Si la cleft demandée existe
        if([bool]($node.PSobject.Properties.name -match $valueField))
        {
            return $node.$valueField
        }
        else  # La clef demandée n'existe pas 
        {
            Throw (("JSON Node value error ({0}). {1}={2}, wanted field: {3}" -f $this.sourceFilename, $filterField, $filterValue, $valueField))
        }
    }




}