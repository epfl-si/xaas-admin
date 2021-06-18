<#
   BUT : Permet d'accéder de manière aisée aux informations contenues dans le fichier JSON décrivant
        les 2nd day actions à ajouter dans vRA.

   AUTEUR : Lucien Chaboudez
   DATE   : Juin 2021

	REMARQUES :
	

#>
class SecondDayActions
{
    hidden [PSCustomObject]$JSONData
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Charge les données du fichier JSON passé en paramètre

        IN  : $entType  -> Type d'entitlement pour lequel on veut les actions day-2
    #>
    SecondDayActions([EntitlementType]$entType)
    {
        try 
        {
            $this.JSONData = @()

            # Définition du dossier où aller chercher les infos en fonction du type d'entitlement pour lequel on doit ajouter des actions
            $JSONFolder = ([IO.Path]::Combine($global:JSON_2ND_DAY_ACTIONS_FOLDER, $entType.toString().toLower()))

            # Parcours des fichier JSON qui sont dans le dossier des 2nd day actions
            Get-ChildItem -Path $JSONFolder -Filter "*.json" | ForEach-Object {
            
                # Chargement de la liste des actions depuis le fichier JSON et ajout à la liste de toutes les actions
                $this.JSONData += ((Get-Content -Path (Join-Path $JSONFolder $_.name) -Raw)  -replace '(?m)\s*//.*?$' -replace '(?ms)/\*.*?\*/') | ConvertFrom-Json
            }
            
        }
        catch
        {
            Throw (("2nd day action file error : {0}" -f $_.Exception.Message))
            exit
        }

    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la liste des actions

        RET : Tableau avec la liste des actions
    #>
    [Array] getActionList()
    {
        return $this.JSONData
    }
}