<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière pas si simple vu qu'on doit décortiquer la manière de faire dans le 
         site https://s3.epfl.ch/_/console/ afin de savoir quels appels sont fait à l'API

         La classe parente est RESTAPI et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019    
#>
class ScalityWebConsole: RESTAPI
{

    hidden [string]$server
    hidden [System.Collections.Hashtable]$headers
    <#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $consoleUrl   -> Nom du serveur
        IN  : $username     -> Nom d'utilisateur pour la connexion. Attention à la casse !!!
        IN  : $password     -> Mot de passe pour la connexion
	#>
	ScalityWebConsole([string]$server, [string]$username, [string]$password) : base($server) # Ceci appelle le constructeur parent
	{
        $this.server = $server

        $this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
        $this.headers.Add('Content-Type', 'application/json')

        # On passe par une hashtable et on la mettra direct en JSON après pour la requête. Pas besoin de passer par
        # un fichier JSON dans les templates pour quelque chose de simple comme ça.
        $body = @{username = $username
                    password = $password}

        $uri = "https://{0}/_/console/authenticate" -f $this.server

        # Ajout du token pour les requêtes futures 
        $this.headers.Add('x-access-token', ($this.callAPI($uri, "Post",  (ConvertTo-Json -InputObject $body -Depth 20))).token)
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Gère les erreurs s'il y en a. Si on a une erreur dans la requête passée en paramètre, on propage une exception

        IN  : $requestResult    -> Résultat d'une requête.
    #>
    hidden [void]handleError([string]$requestResult)
    {
        if($null -ne $requestResult.error)
        {
            Throw $requestResult.error
        }
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie les noms des buckets associés à la policy passée.

        IN  : $policyArn        -> ARN de la Policy dont on veut les buckets
        IN  : $policyVersion    -> Version de la policy, ex: "v3" (ne pas oublier le "v" avant)
    #>
    [PSObject]getPolicyContent([string]$policyArn, [string]$policyVersion)
    {
        $uri = "https://{0}/_/console/iam/getpolicyversion" -f $this.server

        $body = @{policyArn = $policyArn
                policyVersion = $policyVersion}

        
        $result = $this.callAPI($uri, "POST", (ConvertTo-Json -InputObject $body -Depth 20))

        $this.handleError($result)

        # On décode le résultat pour avoir le JSON décrivant la policy, et on transforme celui-ci en objet
        return [System.Web.HttpUtility]::UrlDecode($result.policyVersion.Document) | ConvertFrom-Json
    }


    <#
        -------------------------------------------------------------------------------------
        BUT : Renvoie les noms des buckets associés à la policy passée.

        IN  : $policyArn        -> ARN de la Policy dont on veut les buckets
        IN  : $policyVersion    -> Version de la policy, ex: "v3" (ne pas oublier le "v" avant)
    #>
    [PSObject]getPolicyBuckets([string]$policyArn, [string]$policyVersion)
    {

        $policy = $this.getPolicyContent($policyArn, $policyVersion)

        $bucketList = @()

        ForEach($statement in $policy.Statement)
        {
            # Parcours des ressources 
            ForEach($resource in $statement.Resource)
            {
                <# Ici, on peut se retrouver avec les possibilités suivantes :
                arn:aws:s3:::my-bucket/*
                arn:aws:s3:::my-bucket
                arn:aws:s3:::*

                Il va falloir faire du ménage pour supprimer quelques caractères 
                #>
                $bucketName = $resource -replace "^arn:aws:s3:::|\/?\*$", ""

                if(($bucketName -ne "") -and ($bucketList -notcontains $bucketName))
                {
                    $bucketList += $bucketName
                }
            }
        }

        return $bucketList
    }
}