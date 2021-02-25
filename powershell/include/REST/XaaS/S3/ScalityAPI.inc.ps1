<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière simple.
         A la base, c'est uniquement pour faire des requêtes dans Scality que cette classe a été créée
         mais il se peut qu'à l'avenir on doive aussi interagir avec Amazon S3 par exemple. Dans ce 
         cas-là, il faudra un peu adapter la classe pour qu'elle fonctionne aussi avec Amazon S3.

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

   VERSION : 1.0.1
#>

<# On regarde si le module PowerShell est chargé. S'il ne l'est pas, on propage une erreur. 
Le module doit être chargé dans le script principal et pas dans ce fichier. Si on le fait ailleurs, le
contenu de la variable $PSScriptRoot est modifiée avec le chemin jusqu'au dossier où on a fait le 
Import-Module... ce qui peut avoir des effets de bords indésirables... #>
if( $null -eq (Get-Module | Where-Object {$_.Name -eq "AWSPowerShell"}) )
{
    Throw "Please load AWSPowerShell module (Import-Module) in main script before including this file."
}

$global:XAAS_S3_STATEMENT_KEYWORD = "s3:Get*"

class ScalityAPI: APIUtils
{
	hidden [string]$s3EndpointUrl
    hidden [PSObject]$credentials
    # Utilisée uniquement dans le cas où le backend est effectivement Scality
    hidden [ScalityWebConsoleAPI]$scalityWebConsole

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server               -> Nom du serveur Scality. Sera utilisé pour créer l'URL du endpoint
        IN  : $credProfileName      -> Nom du profile à utiliser pour les credentials
                                        de connexion.
        IN  : $s3WebConsoleUser     -> Nom d'utilisateur pour se connecter à la console Web
        IN  : $s3WebConsolePassword -> Mot de passe pour se connecter à la console Web
        IN  : $isScality            -> Pour dire si on est sur une infra Scality ou pas.
	#>
	ScalityAPI([string]$server, [string]$credProfileName, [string]$s3WebConsoleUser, [string]$s3WebConsolePassword, [bool]$isScality)
	{
        
        # Initialisation du sous-dossier où se trouvent les JSON que l'on va utiliser
		$this.setJSONSubPath(@("XaaS", "S3") )

        $this.s3EndpointUrl = "https://{0}" -f $server

        if($isScality)
        {
            # Création de l'objet pour accéder à la console S3
            <# FIXME: Faire en sorte de rendre ceci paramétrable car la console doit être utilisée (à priori) uniquement 
                    si on est à l'EPFL et pas avec Amazon. Est-ce qu'on peut aussi utiliser une console ou est-ce que
                    certaines opérations devront être effectuées d'une autre manière car implémentées dans l'API Amazon
                    (contrairement à l'absence d'implémentation dans l'API Scality) ?!? #>
            $this.scalityWebConsole = [ScalityWebConsoleAPI]::new($server, $s3WebConsoleUser, $s3WebConsolePassword )
        }
        else # ce n'est pas une infra Scality
        {
            $this.scalityWebConsole = $null    
        }

        # On tente de charger le profil pour voir s'il existe
        $this.credentials = Get-AWSCredential -ProfileName $credProfileName
        if($null -eq $this.credentials)
        {
            Throw ("AWS Credential profile not found ({0}) for user {1}, see https://confluence.epfl.ch:8443/display/SIAC/%5BXaaS%5D+xaas-s3-endpoint.ps1" -f $credProfileName, $env:UserName)
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
        $this.debugLog("New-S3Bucket -bucketName $($bucketName)")
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
        $this.debugLog("Get-S3Bucket -bucketName $($bucketName)")
        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-S3Bucket.html
        return Get-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                             -BucketName $bucketName 
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des buckets

        RET : la liste des buckets
	#>
    [PSObject] getBucketList()
    {
        $this.debugLog("Get-S3Bucket (all)")
        # Documentation: https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-S3Bucket.html
        return Get-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials 
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
            $this.debugLog("Remove-S3Bucket -bucketName $($bucketName)")
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

        $this.debugLog("Write-S3BucketVersioning -bucketName $($bucketName) -VersioningConfig_Status $($status)")
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
        $this.debugLog("Get-S3BucketVersioning -bucketName $($bucketName)")
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
        $this.debugLog("Get-IAMPolicyList (all)")
        # Récupération de la liste des policies et filtre si le bucket est contenu dedans
        return Get-IAMPolicyList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object { $this.getPolicyBucketList($_.PolicyName) -contains $bucketName }
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la policy RO ou RW d'un bucket donné
        
        IN  : $bucketName   -> Le nom du bucket 
        IN  : $accessType   -> Le type d'accès géré par la policy que l'on veut: $global:XAAS_S3_ACCESS_TYPES
        
        RET : Objet avec la policy
	#>
    [PSObject] getBucketPolicyForAccess([string]$bucketName, [string]$accessType)
    {
        $policyList = $this.getBucketPolicyList($bucketName)  
        $policy = $policyList| Where-Object { $_.PolicyName -like ("*-{0}" -f $accessType) }

        # Si on a plus d'un objet, c'est qu'il y a une erreur quelque part
        if($policy.Count -gt 1)
        {
            Throw ("More than one '{0}' policy defined for bucket '{1}':`n{2}" -f $accessType, $bucketName, ($policy | ConvertTo-Json))
        }
        # SI pour une raison ou une autre on n'a trouvé aucune policy
        elseif($policy.count -eq 0)
        {
            # S'il y avait des policies (mais pas forcément avec le bon nom)
            if($policyList.count -gt 0)
            {
                Throw ("No '{0}' policy found for bucket '{1}'. But {2} policy was/were found:`n{3}" -f $accessType, $bucketName, $policyList.count, (($policyList|Select-Object -ExpandProperty PolicyName) -join "`n"))
            }
            else # Aucune policy n'existe pour les accès
            {
                return $null
            }
        }
         return $policy[0]
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

        $this.debugLog("New-IAMUser -username $($username)")
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
        $this.debugLog("Get-IAMUserList")
        return Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object {$_.Username -eq $username}
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un utilisateur
        
        IN  : $username     -> Nom de l'utilisateur
	#>
    [void] deleteUser([string]$username)
    {
        $this.debugLog("Remove-IAMUser -UserName $($username)")
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

        $this.debugLog("Get-IAMUserList")
        # Parcours de tous les utilisateurs du système
        Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | ForEach-Object {

            $this.debugLog("Get-IAMAttachedUserPolicyList -UserName $($_.UserName)")
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
        $this.debugLog("Get-IAMAttachedUserPolicyList -UserName $($username)")
        # Recherche si l'utilisateur courant est attaché à la policy recherchée 
        # https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-IAMAttachedUserPolicyList.html
        return ($null -ne (Get-IAMAttachedUserPolicyList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                          -UserName $username | Where-Object { $_.PolicyName -eq $policyName}  ))
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

        $this.debugLog("New-IAMAccessKey -UserName $($username)")
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
        $this.debugLog("Get-IAMAccessKey -UserName $($username)")
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
        $this.debugLog("Get-IAMAccessKey -UserName $($username)")
        Get-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username | ForEach-Object {

            $this.debugLog("Remove-IAMAccessKey -UserName $($username) -AccessKeyId $($_.AccessKeyId)")
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
        $this.debugLog("Get-IAMPolicyVersionList -PolicyArn $($policyArn)")
        # Recherche de la liste des versions de la policy
        Get-IAMPolicyVersionList -endpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                 -PolicyArn $policyArn | ForEach-Object {
        
            # Si ce n'est pas la version active, on la supprime
            if(!($_.IsDefaultVersion))
            {
                $this.debugLog("Remove-IAMPolicyVersion -PolicyArn $($policyArn) -VersionId $($_.VersionId)")
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
        $this.debugLog("Get-IAMPolicies")
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

        $policyDocument = (ConvertTo-Json -InputObject $body -Depth 20)
        $this.debugLog("New-IAMPolicy -PolicyName $($policyName) -policyDocument $($policyDocument)")
        # Ajout de la nouvelle policy
        $pol = New-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -PolicyName $policyName -PolicyDocument $policyDocument

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

        $this.debugLog("Get-IAMPolicy -PolicyArn $($polArn)")
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

        $this.debugLog("Remove-IAMPolicy -PolicyArn $($polArn)")
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

        # Si on a une Infra Scality, on récupère les infos d'une certaine manière
        if($null -ne $this.scalityWebConsole)
        {
            # Avec l'ARN et la version de la Policy, on peut récupérer le contenu de celle-ci.
            # Celui-ci, si on le converti en JSON, est exactement le même que celui utilisé par la fonction 'addPolicy'
            $polContent = $this.scalityWebConsole.getPolicyContent($policy.Arn, $policy.DefaultVersionId)
        }
        else # Ce n'est pas une infra Scality
        {
            Throw "Other infrastructure than Scality must be implemented"    
        }

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

            $policyDocument = (ConvertTo-Json -InputObject $polContent -Depth 20)

            $this.debugLog("New-IAMPolicyVersion -PolicyArn $($policy.Arn) -SetAsDefault true -policyDocument $($policyDocument)")
            # Ajout de la nouvelle version de policy
            New-IAMPolicyVersion -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -PolicyArn $policy.Arn -PolicyDocument $policyDocument `
                                    -SetAsDefault $true | Out-Null
            
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

        # Si on a une Infra Scality, on récupère les infos d'une certaine manière
        if($null -ne $this.scalityWebConsole)
        {
            # Avec l'ARN et la version de la Policy, on peut récupérer le contenu de celle-ci.
            # Celui-ci, si on le converti en JSON, est exactement le même que celui utilisé par la fonction 'addPolicy'
            $polContent = $this.scalityWebConsole.getPolicyContent($policy.Arn, $policy.DefaultVersionId)
        }
        else # Ce n'est pas une infra Scality
        {
            Throw "Other infrastructure than Scality must be implemented"    
        }

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

            $policyDocument = (ConvertTo-Json -InputObject $polContent -Depth 20)

            $this.debugLog("New-IAMPolicyVersion -PolicyArn $($policy.Arn) -SetAsDefault true -policyDocument $($policyDocument)")
            # Ajout de la nouvelle version de policy
            New-IAMPolicyVersion -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -PolicyArn $policy.Arn -PolicyDocument $policyDocument `
                                    -SetAsDefault $true | Out-Null
            
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

        # Si on a une Infra Scality, on récupère les infos d'une certaine manière
        if($null -ne $this.scalityWebConsole)
        {
            return $this.scalityWebConsole.getPolicyBuckets($policy.Arn, $policy.DefaultVersionId)
        }
        else # Ce n'est pas une infra Scality
        {
            Throw "Other infrastructure than Scality must be implemented"    
        }
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

            $this.debugLog("Register-IAMUserPolicy -PolicyArn $($policy.Arn) -UserName $($username)")

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

            $this.debugLog("Unregister-IAMUserPolicy -PolicyArn $($policy.Arn) -UserName $($username)")

            # Documentation : https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Unregister-IAMUserPolicy.html
            Unregister-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                        -UserName $username -PolicyArn $policy.Arn 
        }
    } 
    
    
    <#
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
                                        OBJECTS 
    -------------------------------------------------------------------------------------
    -------------------------------------------------------------------------------------
    #>


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des objets d'un bucket
        
        IN  : $bucketName   -> Le nom du bucket        

        RET : Liste des objets
	#>
    [PSObject] getBucketObjectList([string]$bucketName)
    {
        $this.debugLog("Get-S3Object -bucketName $($bucketName)")
        # https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-S3Object.html
        return Get-S3Object -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                             -BucketName $bucketName
    }


    
    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie les infos de taille d'un bucket

        IN : $bucketName    -> Le nom du Bucket

        RET : Objet avec les éléments suivants:
                .storageUtilized    -> Taille utilisée en bytes
                .numberOfObjects    -> Nombre d'objets
    #>
    [PSObject]getBucketUsageInfos([string]$bucketName)
    {

        # Si on a une Infra Scality, on récupère les infos d'une certaine manière
        if($null -ne $this.scalityWebConsole)
        {
            return $this.scalityWebConsole.getBucketUsageInfos($bucketName)
        }
        else # Ce n'est pas une infra Scality
        {
            Throw "Other infrastructure than Scality must be implemented"    
        }
        
    }

}