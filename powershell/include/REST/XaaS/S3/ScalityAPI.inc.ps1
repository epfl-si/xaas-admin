<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière simple.

         La classe parente est APIUtils et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.

         Cette classe aura besoin d'un profil de credential pour fonctionner. De la 
         documentation pour créer un profil peut être trouvée ici : 
         https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
       
         Pour trouver de la documentation sur un CMDLet, on peut exécuter la méthode 
         'generateHTMLDocumentation' ou alors forger l'URL de la documentation en mettant le 
         nom du cmdLet (en respectant la casse):
         https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/<cmdLetCaseSensitive>.html


        http://forum.zenko.io/

   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019    
#>

# Chargement du module PowerShell
Import-Module AWSPowerShell

$global:XAAS_S3_STATEMENT_KEYWORD = "s3:Get*"

class ScalityAPI: APIUtils
{
	hidden [string]$s3EndpointUrl
    hidden [PSObject]$credentials
    hidden [ScalityWebConsoleAPI]$scalityWebConsole

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server               -> Nom du serveur Scality. Sera utilisé pour créer l'URL du endpoint
        IN  : $credProfileName      -> Nom du profile à utiliser pour les credentials
                                        de connexion.
        IN  : $s3WebConsoleUser     -> Nom d'utilisateur pour se connecter à la console Web
        IN  : $s3WebConsolePassword -> Mot de passe pour se connecter à la console Web
	#>
	ScalityAPI([string]$server, [string]$credProfileName, [string]$s3WebConsoleUser, [string]$s3WebConsolePassword)
	{
        
        $this.s3EndpointUrl = "https://{0}" -f $server

        # Création de l'objet pour accéder à la console S3
        $this.scalityWebConsole = [ScalityWebConsoleAPI]::new($server, $s3WebConsoleUser, $s3WebConsolePassword )

        # On tente de charger le profil pour voir s'il existe
        $this.credentials = Get-AWSCredential -ProfileName $credProfileName
        if($null -eq $this.credentials)
        {
            Throw "AWS Credential profile not found ({0})" -f $credProfileName
        }
    }
    

    <#
	-------------------------------------------------------------------------------------
        BUT : Cette fonction sert juste à générer un fichier de documentation (nom passé en paramètre)
                contenant la liste des fonctions existantes dans le module AWSPowerShell avec
                un lien sur la documentation officielle.
        
        IN  : $endpointUrl          -> URL du endpoint Scality
	#>
    [void] generateHTMLDocumentation([string]$outputFile)
    {
        Get-Module AWSPowerShell  | ForEach-Object {
            "<h1>AWSPowerShell documentation</h1>"
            Get-Command -Module $_.name -CommandType cmdlet, function | Select-Object name | ForEach-Object {
                '<a href="https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/{0}.html">{0}</a><br>' -f $_.Name
            }
        } | Out-File $outputFile
    }


    <#
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
                                        BUCKETS 
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
    #>


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un bucket
        
        IN  : $bucketName   -> Le nom du bucket        

        RET : Le bucket créé
	#>
    [PSObject] addBucket([string]$bucketName)
    {
        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/New-S3Bucket.html
        return New-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -BucketName $bucketName 
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un bucket
        
        IN  : $bucketName   -> Le nom du bucket        

        RET : Le bucket que l'on veut ou $null si pas trouvé
	#>
    [PSObject] getBucket([string]$bucketName)
    {
        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-S3Bucket.html
        return Get-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                             -BucketName $bucketName 
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Permet de savoir si un bucket existe
        
        IN  : $bucketName   -> Le nom du bucket        

        RET : $true|$false
	#>
    [bool] bucketExists([string]$bucketName)
    {
        return ($null -ne $this.getBucket($bucketName))
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un bucket. 
        
        IN  : $bucketName   -> Le nom du bucket        
	#>
    [void] deleteBucket([string]$bucketName)
    {
        # On n'efface que si le bucket existe, bien évidemment.
        if($this.bucketExists($bucketName))
        {
            # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Remove-S3Bucket.html
            Remove-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -BucketName $bucketName -DeleteBucketContent:$false -Confirm:$false
        }
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Active ou désactive le versioning sur un Bucket
        
        IN  : $bucketName   -> Le nom du bucket        
        IN  : $enabled      -> $true|$false pour dire si activé ou pas
	#>
    [void] setBucketVersioning([string]$bucketName, [bool]$enabled)
    {
        # Si le status demandé est déjà celui qui est actif, on sort.
        if(($this.bucketVersioningEnabled($bucketName)) -eq $enabled)
        {
            return
        }

        # En fonction du statut demandé
        if($enabled)
        {
            $status = "Enabled"
        }
        else # On doit désactiver 
        {
            # Une fois qu'il a été activé, on ne peut plus mettre sur "Off", on ne peut que mettre sur "Suspended"
            $status = "Suspended"
        }

        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Write-S3BucketVersioning.html
        Write-S3BucketVersioning -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -BucketName $bucketName -VersioningConfig_Status $status
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Dit si le versioning est activé pour un bucket
        
        
        IN  : $bucketName   -> Le nom du bucket 
        
        RET : $true|$false
	#>
    [bool] bucketVersioningEnabled([string]$bucketName)
    {
        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-S3BucketVersioning.html
        $currentStatus = (Get-S3BucketVersioning -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -BucketName $bucketName).status

        return ($currentStatus -eq "Enabled")
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des policies dans lequel le bucket se trouve
        
        IN  : $bucketName   -> Le nom du bucket 
        
        RET : Liste des policies. Ce sont des objets complets S3 qui sont renvoyés, pas juste les noms.
	#>
    [Array] getBucketPolicyList([string]$bucketName)
    {
        # Récupération de la liste des policies et filtre si le bucket est contenu dedans
        return Get-IAMPolicyList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object { $this.getPolicyBucketList($_.PolicyName) -contains $bucketName }
    }


    <#
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
                                        USERS 
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
    #>


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un utilisateur
        
        IN  : $username     -> Nom de l'utilisateur

        RET : L'utilisateur ajouté
    #>
    [PSObject] addUser([string]$username)
    {
        # Recherche si l'utilisateur existe 
        $user = $this.getUser($username)

        # S'il existe déjà, on le retourne
        if($null -ne $user)
        {
            return $user
        }

        return New-IAMUser -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -UserName $username
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un utilisateur de Scality
        
        IN  : $username     -> Nom de l'utilisateur

        RET : L'utilisateur recherché ou $null si pas trouvé
	#>
    [PSObject] getUser([string]$username)
    {
        return Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object {$_.Username -eq $username}
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un utilisateur
        
        IN  : $username     -> Nom de l'utilisateur
	#>
    [void] deleteUser([string]$username)
    {
        Remove-IAMUser -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                         -UserName $username -Confirm:$false
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des utilisateurs présents dans une policy
        
        IN  : $policyName     -> Nom de la policy

        RET : Tableau avec la liste des utilisateurs (objet venant de Scality, avec plusieurs infos dedans.)
	#>
    [Array] getPolicyUserList([string]$policyName)
    {
        $userList = @()

        # Parcours de tous les utilisateurs du système
        Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | ForEach-Object {

            # Recherche si l'utilisateur courant est attaché à la policy recherchée 
            # https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-IAMAttachedUserPolicyList.html
            if($null -ne (Get-IAMAttachedUserPolicyList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                          -UserName $_.UserName | Where-Object { $_.PolicyName -eq $policyName}  ))
            {
                $userList += $_
            }
        }

        return $userList
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Permet de savoir si un utilisateur est présent dans une policy 
        
        IN  : $username     -> Nom de l'utilisateur  
        IN  : $policyName   -> Nom de la policy

        RET : $true|$false
	#>
    hidden [bool] userIsInPolicy([string]$username, [string]$policyName)
    {
        return  ($this.getPolicyUserList($policyName) | Where-Object {$_.UserName -eq $username} ).Count -gt 0
    }

    <#
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
                                    ACCESS KEYS
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
    #>

    <#
	-------------------------------------------------------------------------------------
        BUT : regénère une nouvelle combinaison AccessKey et SecretAccessKey pour 
                un utilisateur

        IN  : $username    -> Nom de l'utilisateur pour lequel générer les clefs d'accès

        RET : Objet avec les infos de l'access key générée
	#>
    [PSObject] regenerateUserAccessKey([string]$username)
    {
        # On commence par supprimer les clefs existantes afin de toujours en avoir qu'une seule de valide
        $this.deleteUserAccessKeys($username)
        # Génération de nouvelles clefs
        return New-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                -UserName $username
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des clefs pour un utilisateur

        IN  : $username    -> Nom de l'utilisateur

        RET : Tableau avec les objets contenant les infos des access keys.
                $null si aucune access key n'existe
	#>
    [Array] getUserAccessKeys([string]$username)
    {
        return Get-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                -UserName $username
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime toutes les access keys d'un utilisateur

        IN  : $username    -> Nom de l'utilisateur
	#>
    [void] deleteUserAccessKeys([string] $username)
    {
        Get-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username | ForEach-Object {
             Remove-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                -UserName $username -AccessKeyId $_.AccessKeyId -Confirm:$false
        }
    }

    <#
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
                                        POLICIES 
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
    #>


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime les anciennes versions d'une policy. On a un max de 5 versions 
                autorisées par le système et si on y arrive, on ne peux plus modifier 
                la policy. Il faut donc nettoyer les vielles versions.

        IN  : $policyName       -> ARN de la policy pour laquelle il faut virer les anciennes versions
	#>
    hidden [void] cleanOldPolicyVersions([string]$policyArn)
    {
        # Recherche de la liste des versions de la policy
        Get-IAMPolicyVersionList -endpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                 -PolicyArn $policyArn | ForEach-Object {
        
            # Si ce n'est pas la version active, on la supprime
            if(!($_.IsDefaultVersion))
            {
                Remove-IAMPolicyVersion -endpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                        -PolicyArn $policyArn -VersionId $_.VersionId -Confirm:$false
            }
        }
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un tableau avec les noms des ressources pour référencer un bucket 
                dans une policy.

        IN  : $bucketName   -> nom du bucket pour lequel on veut le nom des resources

        RET : Tableau avec les noms à utiliser
	#>
    hidden [Array] getPolicyResourcesNames([string]$bucketName)
    {
        return  @(
                    ("arn:aws:s3:::{0}" -f $bucketName) 
                    ("arn:aws:s3:::{0}/*" -f $bucketName)
                )
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie l'ARN d'une policy donnée 

        IN  : $policyName   -> Nom de la policy

        RET : Arn de la policy
                $null si pas trouvé
	#>
    hidden [string] getPolicyArn([string]$policyName)
    {
        $pol = Get-IAMPolicies -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object { $_.PolicyName -eq $policyName}

        if($null -eq $pol)
        {
            return $null
        }
        return $pol.Arn
    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Créé une policy pour un bucket

        IN  : $policyName       -> Le nom de la policy à créer
        IN  : $bucketName       -> Le nom du bucket lié à la policy
        IN  : $accessType       -> Le type d'accès pour la Policy. Celui-ci doit se trouver dans 
                                    $global:XAAS_S3_ACCESS_TYPES

        RET : L'objet représentant la policy
	#>
    [PSObject] addPolicy([string]$policyName, [string]$bucketName, [string]$accessType)
    {
        if($global:XAAS_S3_ACCESS_TYPES -notcontains $accessType)
        {
            Throw "Unknown access type ({0})" -f $accessType
        }

        $replace = @{
            bucketName = $bucketName
        }

        $jsonFile = "xaas-s3-policy-{0}.json" -f $accessType.ToLower()

        $body = $this.createObjectFromJSON($jsonFile, $replace)

        # Ajout de la nouvelle policy
        $pol = New-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -PolicyName $policyName -PolicyDocument (ConvertTo-Json -InputObject $body -Depth 20)

        return $pol
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie une policy de Scality
        
        IN  : $policyName     -> Nom de la policy

	#>
    [PSObject] getPolicy([string]$policyName)
    {
        # Recherche de l'Arn de la policy
        $polArn = $this.getPolicyArn($policyName)

        # Si on n'a pas trouvé, pas besoin d'aller plus loin.
        if($null -eq $polArn) 
        {
            return $null
        }

        # Retour des informations complètes en cherchant avec l'Arn
        return Get-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -PolicyArn $polArn
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Efface une policy de Scality
        
        IN  : $policyName     -> Nom de la policy

	#>
    [void] deletePolicy([string]$policyName)
    {
        # Recherche de l'Arn de la policy
        $polArn = $this.getPolicyArn($policyName)

        # Si on n'a pas trouvé, pas besoin d'aller plus loin.
        if($null -eq $polArn) 
        {
            Throw "Policy '{}' doesn't exists" -f $policyName
        }

        # Selon la documentation, il faut supprimer les anciennes versions de la policy avant de pouvoir
        # effacer celle-ci: https://docs.aws.amazon.com/IAM/latest/APIReference/API_DeletePolicy.html
        $this.cleanOldPolicyVersions($polArn)

        Remove-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -PolicyArn $polArn -Confirm:$false
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un bucket à une policy. Une nouvelle version de la policy sera ajoutée
                et on garde la version précédente pour avoir un historique.
                Si le bucket se trouve déjà dans la policy, on ne fait rien.
        
        IN  : $policyName   -> Nom de la policy
        IN  : $bucketName   -> Nom du bucket à ajouter.

        RET : L'objet représentant la policy modifiée 

	#>
    [PSObject] addBucketToPolicy([string]$policyName, [string]$bucketName)
    {

        # Récupération des informations de la policy
        $policy = $this.getPolicy($policyName)

        # Avec l'ARN et la version de la Policy, on peut récupérer le contenu de celle-ci.
        # Celui-ci, si on le converti en JSON, est exactement le même que celui utilisé par la fonction 'addPolicy'
        $polContent = $this.scalityWebConsole.getPolicyContent($policy.Arn, $policy.DefaultVersionId)

        $updateNeeded = $false

        # On parcours les statements pour trouver celui qui donne les accès
        ForEach($statement in $polContent.Statement)
        {
            # Si on est sur le statement qui donne les droits autre que lister le bucket,
            if($statement.Action -contains $global:XAAS_S3_STATEMENT_KEYWORD)
            {
                $nbBucketsInList = $statement.Resource.Count
                # Ajout des éléments en virant ce qui est à double
                $statement.Resource = (($statement.Resource + $this.getPolicyResourcesNames($bucketName)) | Select-Object -Unique)

                $updateNeeded = ($statement.Resource.count -ne $nbBucketsInList)
                
                # On sort de la boucle
                break
            }
        }

        # S'il y a besoin de mettre à jour, 
        if($updateNeeded)
        {
            <# On commence par nettoyer les vieilles versions pour ne pas arriver au max de 5 (défini dans S3).
            Seule la version active va rester. Et on va ensuite modifier la policy, ce qui fait que la version
            active passera en 'inactive' et on aura l'historique de la version précédente #>
            $this.cleanOldPolicyVersions($policy.Arn)

            # Ajout de la nouvelle version de policy
            $dummy = New-IAMPolicyVersion -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -PolicyArn $policy.Arn -PolicyDocument (ConvertTo-Json -InputObject $polContent -Depth 20) `
                                    -SetAsDefault $true
            
            $policy = $this.getPolicy($policyName)
        }

        return $policy

    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un bucket d'une policy. Une nouvelle version de la policy sera ajoutée
                et on garde la version précédente pour avoir un historique.
                Si le bucket se trouve déjà dans la policy, on ne fait rien.
        
        IN  : $policyName   -> Nom de la policy
        IN  : $bucketName   -> Nom du bucket à supprimer

        RET : L'objet représentant la policy modifiée 

	#>
    [PSObject] removeBucketFromPolicy([string]$policyName, [string]$bucketName)
    {
        <# Si c'est le dernier bucket de la policy, on génère une erreur parce qu'on ne peut pas le supprimer, 
            il faut virer la policy à la place. Normalement, on ne devrait pas arriver dans ce cas de figure si 
            on code correctement mais ça fait garde fou au moins #> 
        if($this.onlyOneBucketInPolicy($policyName))
        {
            Throw "Cannot remove last Bucket from Policy '{0}', delete policy instead!" -f $policyName
        }

        # Récupération des informations de la policy
        $policy = $this.getPolicy($policyName)

        # Avec l'ARN et la version de la Policy, on peut récupérer le contenu de celle-ci.
        # Celui-ci, si on le converti en JSON, est exactement le même que celui utilisé par la fonction 'addPolicy'
        $polContent = $this.scalityWebConsole.getPolicyContent($policy.Arn, $policy.DefaultVersionId)

        # Liste des ressources à ajouter 
        $resourceList = $this.getPolicyResourcesNames($bucketName)

        $updateNeeded = $false

        # On parcours les statements pour trouver celui qui donne les accès
        ForEach($statement in $polContent.Statement)
        {
            # Si on est sur le statement qui donne les droits autre que lister le bucket,
            if($statement.Action -contains $global:XAAS_S3_STATEMENT_KEYWORD)
            {
                $nbBucketsInList = $statement.Resource.Count
                # Ajout des éléments en virant ce qui est à double
                $statement.Resource = $statement.Resource | Where-Object { $resourceList -notcontains $_ }

                # Si vide (donc $null), on remet un tableau vide sinon la requête va partir en erreur
                if($null -eq $statement.Resource)
                {
                    $statement.Resource = @()
                }

                $updateNeeded = ($statement.Resource.count -ne $nbBucketsInList)
                
                # On sort de la boucle
                break
            }
        }

        # S'il y a besoin de mettre à jour, 
        if($updateNeeded)
        {
            <# On commence par nettoyer les vieilles versions pour ne pas arriver au max de 5 (défini dans S3).
            Seule la version active va rester. Et on va ensuite modifier la policy, ce qui fait que la version
            active passera en 'inactive' et on aura l'historique de la version précédente #>
            $this.cleanOldPolicyVersions($policy.Arn)

            # Ajout de la nouvelle version de policy
            $dummy = New-IAMPolicyVersion -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -PolicyArn $policy.Arn -PolicyDocument (ConvertTo-Json -InputObject $polContent -Depth 20) `
                                    -SetAsDefault $true
            
            $policy = $this.getPolicy($policyName)
        }

        return $policy
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Permet de savoir si la policy n'a plus qu'un seul bucket de référencé
        
        IN  : $policyName   -> Nom de la policy

        RET : $true|$false
	#>
    [bool] onlyOneBucketInPolicy([string]$policyName)
    {
        # Avec l'ARN et la version de la Policy, on peut récupérer le contenu de celle-ci.
        # Celui-ci, si on le converti en JSON, est exactement le même que celui utilisé par la fonction 'addPolicy'
        return ($this.getPolicyBucketList($policyName)).Count -eq 1
    }

    
    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des buckets qui se trouvent dans une policy
        
        IN  : $policyName   -> Nom de la policy

        RET : Tableau avec la liste des noms des buckets
	#>
    [Array] getPolicyBucketList([string]$policyName)
    {
        # Récupération des informations de la policy
        $policy = $this.getPolicy($policyName)

        return $this.scalityWebConsole.getPolicyBuckets($policy.Arn, $policy.DefaultVersionId)
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un utilisateur à une policy
        
        IN  : $policyArn    -> Nom de la policy
        IN  : $username     -> Nom d'utilisateur        
	#>
    [void] addUserToPolicy([string]$policyName, [string]$username)
    {
        # Si l'utilisateur n'est pas encore dans la policy, 
        if(!($this.userIsInPolicy($username, $policyName)))
        {
            # Récupération des informations de la policy
            $policy = $this.getPolicy($policyName)

            # Documentation : https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Register-IAMUserPolicy.html
            Register-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -UserName $username -PolicyArn $policy.Arn 
        }
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un utilisateur d'une policy
        
        IN  : $policyArn    -> Nom de la policy
        IN  : $username     -> Nom d'utilisateur    
	#>
    [void] removeUserFromPolicy([string]$policyName, [string]$username)
    {
        # Si l'utilisateur est effectivement dans la policy 
        if($this.userIsInPolicy($username, $policyName))
        {
            # Récupération des informations de la policy
            $policy = $this.getPolicy($policyName)

            # Documentation : https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Unregister-IAMUserPolicy.html
            Unregister-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                        -UserName $username -PolicyArn $policy.Arn 
        }
    }    

}