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
    # Utiliser pour stocker au fur et à mesure les ID des approval policies créées pour les actions en nécessitant
    # Les clefs de la table sont créées dans la fonction getJSONApprovalPoliciesFilesInfos()
    hidden [Hashtable]$actionToApprovalPolicyId
    
    <#
        -------------------------------------------------------------------------------------
        BUT : Charge les données du fichier JSON passé en paramètre
    #>
    SecondDayActions()
    {
        $this.actionToApprovalPolicyId = @{}
        
        try 
        {
            $this.JSONData = @()

            # Parcours des fichier JSON qui sont dans le dossier des 2nd day actions
            Get-ChildItem -Path $global:JSON_2ND_DAY_ACTIONS_FOLDER -Filter "*.json" | ForEach-Object {
            
                # Chargement de la liste des actions depuis le fichier JSON et ajout à la liste de toutes les actions
                $this.JSONData += (Get-Content -Path (Join-Path $global:JSON_2ND_DAY_ACTIONS_FOLDER $_.name)) -join "`n" | ConvertFrom-Json
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
        BUT : Renvoie la liste des objets qui représentent un élément cible (dont le nom est donné) sur lequel
                des actions sont appliquées. On a une liste car ces éléments (en particulier les actions EPFL)
                peuvent être présents dans plusieurs fichiers JSON.

        IN  : $elementName      -> Le nom de l'élément pour lequel on veut les détails

        RET : Liste des objets représentant l'élément
    #>
    hidden [Array]getTargetElementList([string]$elementName)
    {
        # Recherche des éléments
        $elementList = $this.JSONData | Where-Object { $_.appliesTo -eq $elementName}

        if($elementList.Count -eq 0 )
        {
            # Si l'élément n'est pas trouvé, exception
            Throw ("2nd day action target element '{0}' not found" -f $elementName)
        }
        return $elementList
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
        $targetElementList = $this.getTargetElementList($elementName)

        # Parcours des éléments cibles renvoyés (VM, XaaS, ...)
        ForEach($targetElement in $targetElementList)
        {
            # Parcours des actions pour 
            ForEach($actionInfos in $targetElement.actions)
            {
                if($actionInfos.name -eq $actionName)
                {
                    return $actionInfos
                }
            }
        }

        # Si l'élément n'est pas trouvé, exception
        Throw ("2nd day action '{0}' not found for element '{1}'" -f $actionName, $elementName)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Génère et renvoie un hash unique pour un élément cible d'une 2nd day action
                et la 2nd day action associée.
        
        IN  : $elementName  -> Nom de l'élément auquel appartient l'action
        IN  : $actionName   -> Nom de l'action

        RET : Hash unique
    #>
    hidden [string]getElementActionUniqHash([string]$elementName, [string]$actionName)
    {
        return getStringHash -string ("{0}{1}" -f $elementName, $actionName) 
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie un tableau de tableaux avec la liste des fichiers JSON décrivant des approval policies étant utilisées
                pour les 2nd day actions ainsi que les éléments qu'il faut remplacer dans le JSON s'il y en a.
        
        IN  : $targetTenant     -> Nom du tenant pour lequel on veut la liste des fichiers.

        RET : Tableau avec des objets contenant les infos.
    #>
    [Array]getJSONApprovalPoliciesFilesInfos([string]$targetTenant)
    {
        $JSONList = @()

        Foreach($targetElement in $this.JSONData) 
        {
            # Parcours des actions sur l'élément courant
            Foreach($actionInfos in $targetElement.actions)
            {
                # Parcours des approvals définis (par tenant) s'il y en a
                ForEach($tenantApproval in $actionInfos.approvals)
                {
                    # Si le tenant recherché correspond et si le fichier JSON à utiliser pour créer l'approval 
                    # policy courante pour le Tenant sur lequel on doit le faire est déjà dans la liste de ceux à traiter.
                    if(($tenantApproval.tenant -eq $targetTenant))
                    {
                        # Création d'une entrée dans la table de mapping pour ensuite stocker l'ID de la policies qui aura été créée
                        # avec les informations contenues ici. Pour la clef de mapping, on va simplement crééer un hash unique qui 
                        # sera composé du nom de l'élément auquel s'applique l'action suivi du nom de l'action.
                        # On créé avec une valeur $null et ça sera ensuite rempli par l'intermédiaire de la fonction
                        # setActionApprovalPolicyId()
                        $uniqHash = $this.getElementActionUniqHash($targetElement.appliesTo, $actionInfos.name) 
                        $this.actionToApprovalPolicyId.Add($uniqHash, $null)

                        # Récupération de la structure telle quel
                        $el = $tenantApproval
                        # Ajout de l'information du hash unique 
                        $el | Add-Member -NotePropertyName actionHash -NotePropertyValue $uniqHash
                        $JSONList += $el
                    }
                }
            }
        }

        return $JSONList
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Initialise l'ID de l'approval policy qui a été créée (ou qui existait déjà) pour une
                2nd day action présente dans la liste (et définie par un hash).
                L'information pourra ensuite être récupérée via : getActionApprovalPolicyId

        IN  : $actionHash       -> hash de la 2nd day action concernée
        IN  : $approvalPolicyId -> ID de l'approval Policy qui a été créée pour cette action.
    #>
    [void]setActionApprovalPolicyId([string]$actionHash, [string]$approvalPolicyId)
    {
        $this.actionToApprovalPolicyId.$actionHash = $approvalPolicyId
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Efface le contenu de la liste de mapping entre les hash (element, action) et 
                l'approval policy liée. Pourquoi on devrait faire ça? simplement parce que 
                d'un business group à l'autre, on va avoir le même hash pour le même tuple
                "element/action" et donc on aura une erreur si on essaie de l'ajouter à la
                liste de mapping. On pourrait mettre à jour mais on aurait toujours des 
                relicas du business group précédent.. donc faire un clean est plus approrié
    #>
    [void]clearApprovalPolicyMapping()
    {
        $this.actionToApprovalPolicyId = @{}
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie l'ID de l'approval policy qui existe dans vRA pour l'action $actionName
                qui est appliquée sur l'élément $elementName

        IN  : $elementName  -> Nom de l'élément auquel appartient l'action
        IN  : $actionName   -> Nom de l'action

        RET : ID de l'approval policy
    #>
    [string]getActionApprovalPolicyId([string]$elementName, [string]$actionName)
    {
        # Génération du hash pour l'élement et l'action
        $actionHash = $this.getElementActionUniqHash($elementName, $actionName)

        # Si on a des infos pour le hash 
        if($this.actionToApprovalPolicyId.keys -contains $actionHash)
        {
            return $this.actionToApprovalPolicyId.$actionHash
        }
        # Si pas trouvé, on retourne $null 
        return $null
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Retourne la liste des éléments cibles auxquels les 2nd day actions s'appliquent
    #>
    [Array]getTargetElementList()
    {
        # Retour du champs (unique) 'appliesTo' de tous les éléments présents dans $this.JSONData
        return ($this.JSONData | Select-Object -Property "appliesTo" -Unique ).appliesTo

    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Retourne la liste des noms d'actions pour un élément donné.

        IN  : $elementName      -> Nom de l'élément pour lequel on veut les actions
    #>
    [Array]getElementActionList([string]$elementName)
    {
        $targetElementList = $this.getTargetElementList($elementName)

        # Récupération de la liste des actions. 
        $actionList = @()

        ForEach($targetElement in $targetElementList)
        {
            ForEach($actionInfos in $targetElement.actions)
            {
                $actionList += $actionInfos.name
            }
        }

        return $actionList
    }

}