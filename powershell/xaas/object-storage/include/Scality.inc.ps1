<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière simple
       
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
 

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $endpointUrl          -> URL du endpoint Scality
	#>
	Scality([string]$endpointUrl)
	{
        $this.s3EndpointUrl = $endpointUrl
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
        BUT : Renvoie un utilisateur de Scality
        
        IN  : $username     -> Nom de l'utilisateur
	#>
    [PSObject] getUser([string]$username)
    {
        return Get-IAMUserList -EndpointUrl $this.s3EndpointUrl | Where-Object {$_.Username -eq $username}
    }


    <#
	-------------------------------------------------------------------------------------
        BUT : Renvoie une policy de Scality
        
        IN  : $policyName     -> Nom de la policy
	#>
    [PSObject] getPolicy([string]$policyName)
    {
        return Get-IAMPolicies -EndpointUrl $this.s3EndpointUrl  | Where-Object { $_.PolicyName -eq $policyName}
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
        Get-IAMUserList -EndpointUrl $this.s3EndpointUrl | ForEach-Object {

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
        Register-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -UserName $username -PolicyArn $policyArn
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
        Unregister-IAMUserPolicy -EndpointUrl $this.s3EndpointUrl -UserName $username -PolicyArn $policyArn
    }    


    



}