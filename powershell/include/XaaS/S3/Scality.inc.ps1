<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière simple.

         Cette classe aura besoin d'un profil de credential pour fonctionner. De la 
         documentation pour créer un profil peut être trouvée ici : 
         https://docs.aws.amazon.com/powershell/latest/userguide/specifying-your-aws-credentials.html
       
         Pour trouver de la documentation sur un CMDLet, on peut exécuter la méthode 
         'generateHTMLDocumentation' ou alors forger l'URL de la documentation en mettant le 
         nom du cmdLet (en respectant la casse):
         https://docs.aws.amazon.com/ja_jp/powershell/latest/reference/items/<cmdLetCaseSensitive>.html


   AUTEUR : Lucien Chaboudez
   DATE   : Mai 2019    
#>
class Scality
{
	hidden [string]$s3EndpointUrl
    hidden [Amazon.Runtime.AWSCredentials]$credentials

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
        BUT : Renvoie un utilisateur de Scality
        
        IN  : $username     -> Nom de l'utilisateur
	#>
    [PSObject] getUser([string]$username)
    {
        return Get-IAMUserList -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object {$_.Username -eq $username}
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie une policy de Scality
        
        IN  : $policyName     -> Nom de la policy

	#>
    [PSObject] getPolicy([string]$policyName)
    {
        return Get-IAMPolicies -EndpointUrl $this.s3EndpointUrl -Credential $this.credentials | Where-Object { $_.PolicyName -eq $policyName}
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