<#
   BUT : Permet d'accéder de manière aisée aux informations contenues dans le fichier JSON décrivant
        les 2nd day actions à ajouter dans vRA. Si le fichier change de structure, il n'y aura besoin
        de modifier qu'ici et non pas à plusieurs endroits dans le code.

   AUTEUR : Lucien Chaboudez
   DATE   : Janvier 2019



	REMARQUES :
	

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class SecondDayActions
{
    hidden [PSCustomObject]$JSONData
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Charge les données du fichier JSON passé en paramètre
        
        IN  : $JSONFilename     -> Nom court du fichier JSON à charger
    #>
    SecondDayActions([string]$JSONFilename)
    {
        $filepath = (Join-Path $global:RESOURCES_FOLDER $JSONFilename)
	
        try 
        {
            # Chargement de la liste des actions depuis le fichier JSON
            $this.JSONData = (Get-Content -Path $filepath) -join "`n" | ConvertFrom-Json
        }
        catch
        {
            Throw (("2nd day action file error : {0}" -f $_.Exception.Message))
            exit
        }

    }

    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'objet qui représente un élément cible (dont le nom est donné) sur lequel
                des actions sont appliquées

        IN  : $elementName      -> Le nom de l'élément pour lequel on veut les détails

        RET : Objet représentant l'élément
            $null si pas trouvé
    #>
    hidden [PSCustomObject]getTargetElementInfos([string]$elementName)
    {
        ForEach($targetElement in $this.JSONData)
        {
            if($targetElement.appliesTo -eq $elementName)
            {
                return $targetElement
            }
        }
        # Si l'élément n'est pas trouvé, exception
        Throw ("2nd day action target element '{0}' not found" -f $elementName)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie les informations d'une action (par son nom) donnée en fonction du nom de 
                l'élément auquel elle s'applique 
        
        IN  : $elementName  -> Nom de l'élément auquel appartient l'action
        IN  : $actionName   -> Nom de l'action

        RET : Objet avec l'action
                $null si pas trouvé
    #>
    hidden [PSCustomObject]getActionInfos([string]$elementName, [string]$actionName)
    {
        $targetElement = $this.getTargetElementInfos($elementName)

        ForEach($actionInfos in $targetElement.actions)
        {
            if($actionInfos.name -eq $actionName)
            {
                return $actionInfos
            }
        }

        # Si l'élément n'est pas trouvé, exception
        Throw ("2nd day action '{0}' not found for element '{1}'" -f $actionName, $elementName)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie la liste des fichiers JSON décrivant des approval policies étant utilisées
                pour les 2nd day actions
        
        IN  : $targetTenant     -> Nom du tenant pour lequel on veut la liste des fichiers.
    #>
    [Array]getJSONApprovalPoliciesFiles([string]$targetTenant)
    {
        
        $JSONFiles = @()

        Foreach($targetElement in $this.JSONData) 
        {
            # Parcours des actions sur l'élément courant
            Foreach($actionInfos in $targetElement.actions)
            {
                # Parcours des approvals définis (par tenant)
                ForEach($tenantApproval in $actionInfos.approvals)
                {
                    # Si le tenant recherché correspond et si le fichier JSON à utiliser pour créer l'approval 
                    # policy courante pour le Tenant sur lequel on doit le faire est déjà dans la liste de ceux à traiter.
                    if(($tenantApproval.tenant -eq $targetTenant) -and ($JSONFiles -notcontains $tenantApproval.json))
                    {
                        $JSONFiles += $tenantApproval.json
                    }
                }
            }
        }

        return $JSONFiles
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Retourne la liste des éléments cibles auxquels les 2nd day actions s'appliquent
    #>
    [Array]getTargetElementList()
    {
        $elementList = @()
        ForEach($appliesToInfos in $this.JSONData)
        {
            $elementList += $appliesToInfos.appliesTo
        }

        return $elementList
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Retourne la liste des noms d'actions pour un élément donné.

        IN  : $elementName      -> Nom de l'élément pour lequel on veut les actions
    #>
    [Array]getElementActionList([string]$elementName)
    {
        $targetElement = $this.getTargetElementInfos($elementName)

        
        # Récupération de la liste des actions. 
        $actionList = @()

        ForEach($actionInfos in $targetElement.actions)
        {
            $actionList += $actionInfos.name
        }

        return $actionList
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Retourne la liste des noms d'actions pour un élément donné.

        IN  : $elementName      -> Nom de l'élément concerné
        IN  : $actionName       -> Nom de l'action concernée
        IN  : $tenantName       -> Nom du tenant pour lequel on veut le fichier JSON car 
                                    ils sont définis par tenant

        RET : Le nom du fichier JSON
    #>
    [String]getApprovePolicyJSONFilename([string]$elementName, [string]$actionName, [string]$tenantName)
    {
        $actionInfos = $this.getActionInfos($elementName, $actionName)

        ForEach($tenantApproval in $actionInfos.approvals)
        {
            if($tenantApproval.tenant -eq $tenantName)
            {
                return $tenantApproval.json
            }
        }

        return $null
    }


}