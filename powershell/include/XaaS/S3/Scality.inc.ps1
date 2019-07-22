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
class Scality: APIUtils
{
	hidden [string]$s3EndpointUrl
    hidden [PSObject]$credentials

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $endpointUrl          -> URL du endpoint Scality
        IN  : $credProfileName      -> Nom du profile à utiliser pour les credentials
                                        de connexion.
	#>
	Scality([string]$endpointUrl, [string]$credProfileName)
	{
        $this.s3EndpointUrl = $endpointUrl

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
        return New-S3Bucket -EndpointUrl $this.s3EndpointUrl -BucketName $bucketName -Credential $this.credentials -
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie un bucket
        
        IN  : $bucketName   -> Le nom du bucket        

        RET : Le bucket que l'on veut ou $null si pas trouvé
	#>
    [PSObject] getBucket([string]$bucketName)
    {
        return Get-S3Bucket -EndpointUrl $this.s3EndpointUrl -BucketName $bucketName -Credential $this.credentials
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un bucket. 
        
        IN  : $bucketName   -> Le nom du bucket        
	#>
    [void] deleteBucket([string]$bucketName)
    {
        Remove-S3Bucket -EndpointUrl $this.s3EndpointUrl -BucketName $bucketName -DeleteBucketContent:$false -Credential $this.credentials -Confirm:$false
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

        return New-IAMUser -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username
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
        Remove-IAMUser -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username -Confirm:$false
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie la liste des utilisateurs présents dans une policy
        
        IN  : $policyName     -> Nom de la policy

	#>
    [Array] getPolicyUserList([string]$policyName)
    {
        $userList = @()

        # Parcours de tous les utilisateurs du système
        Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | ForEach-Object {

            # Recherche si l'utilisateur courant est attaché à la policy recherchée 
            # https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Get-IAMAttachedUserPolicyList.html
            if($null -ne (Get-IAMAttachedUserPolicyList -EndpointUrl $this.s3EndpointUrl -UserName $_.UserName | Where-Object { $_.PolicyName -eq $policyName}  ))
            {
                $userList += $_
            }
        }

        return $userList
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
        return New-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username
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
        return Get-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime toutes les access keys d'un utilisateur

        IN  : $username    -> Nom de l'utilisateur
	#>
    [void] deleteUserAccessKeys([string] $username)
    {
        Get-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username | ForEach-Object {
             Remove-IAMAccessKey -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -UserName $username -AccessKeyId $_.AccessKeyId -Confirm:$false
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

        $jsonFile = "xaas-s3-policy-{0}.json" -f $accessType

        $body = $this.loadJSON($jsonFile, $replace)

        # Ajout de la nouvelle policy
        $pol = New-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -PolicyName $policyName `
                            -PolicyDocument (ConvertTo-Json -InputObject $body -Depth 20)

        return $pol
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie une policy de Scality
        
        IN  : $policyName     -> Nom de la policy

	#>
    [PSObject] getPolicy([string]$policyName)
    {
        # Recherche des informations basiques de la policy
        $pol = Get-IAMPolicies -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object { $_.PolicyName -eq $policyName}

        # Si on n'a pas trouvé, pas besoin d'aller plus loin.
        if($null -eq $pol) 
        {
            return $null
        }

        # Retour des informations complètes en cherchant avec l'Arn
        return Get-IAMPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                            -PolicyArn $pol.Arn
    }


    [Array] getBucketsInPolicy([string] $policyName)
    {
        

        $b = Get-S3BucketPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -BucketName "chaboude-bucket"

        return Get-S3Bucket -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Foreach-Object {
                    Get-S3BucketPolicy -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                        -BucketName $_.BucketName | Where-Object {
                                            $_.polcicyName -eq $policyName
                                        }
        }
    }


    [PSObject] addBucketToPolicy([string]$policyName, [string]$bucketName)
    {
        $accessType = "rw"

        $pol = $this.getPolicy($policyName)

        $replace = @{
            bucketName = $bucketName
        }

        $jsonFile = "xaas-s3-policy-{0}.json" -f $accessType

        $body = $this.loadJSON($jsonFile, $replace)

        # Ajout de la nouvelle policy
        $pol = New-IAMPolicyVersion -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials `
                                    -PolicyArn $pol.Arn -PolicyDocument (ConvertTo-Json -InputObject $body -Depth 20) `
                                    -SetAsDefault $true
        
        return $pol


        #$pol = $this.getPolicy($policyName)

        #$ac = Get-IAMPolicyGrantingServiceAccessList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials -Arn $pol.Arn

    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un utilisateur à une policy
        
        IN  : $username     -> Nom d'utilisateur
        IN  : $policyArn    -> ARN de la policy
	#>
    [void] addUserToPolicy([string]$username, [string]$policyArn)
    {
        # Documentation : https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Register-IAMUserPolicy.html
        Register-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -UserName $username -PolicyArn $policyArn -Credential $this.credentials
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Supprime un utilisateur d'une policy
        
        IN  : $username     -> Nom d'utilisateur
        IN  : $policyArn    -> ARN de la policy
	#>
    [void] removeUserFromPolicy([string]$username, [string]$policyArn)
    {
        # Documentation : https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/Unregister-IAMUserPolicy.html
        Unregister-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -UserName $username -PolicyArn $policyArn -Credential $this.credentials
    }    



}