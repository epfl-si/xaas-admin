<#
   BUT : Contient une classe permetant de faire des faire certaines requêtes dans Scality
         de manière pas si simple vu qu'on doit décortiquer la manière de faire dans le 
         site https://s3.epfl.ch/_/console/ afin de savoir quels appels sont fait à l'API

         La classe parente est RESTAPI et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2019    
#>

<# On fait ceci pour pouvoir "System.Web.HttpUtility" plus loin dans le code. 
    Ce n'est pas nécessaire si on exécute le code manuellement mais dès que c'est exécuté
    depuis vRO via le endpoint, il y a une erreur
#>
Add-Type -AssemblyName System.Web

class ScalityWebConsoleAPI: RESTAPI
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
	ScalityWebConsoleAPI([string]$server, [string]$username, [string]$password) : base($server) # Ceci appelle le constructeur parent
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
        $this.headers.Add('x-access-token', ($this.callAPI($uri, "Post",  $body)).token)
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

        
        $result = $this.callAPI($uri, "POST", $body)

        $this.handleError($result)

        # On décode le résultat pour avoir le JSON décrivant la policy, et on transforme celui-ci en objet
        return [System.Net.WebUtility]::UrlDecode($result.policyVersion.Document) | ConvertFrom-Json
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
        $uri = "https://{0}/_/console/utapi/buckets" -f $this.server

        <# Documentation donnée pour l'appel à l'API dans le cas où on donnerait un "timeRange" incorrect:
        
        "Timestamps must be one of the following intervals for any past day/hour (mm:ss:SS) - start must be one of [00:00:000, 15:00:000, 30:00:000, 45:00:000], 
        end must be one of [14:59:999, 29:59:999, 44:59:999, 59:59:999]. Start must not be greater than end."
        #>

        $curMin = Get-Date -Format mm
        if(($curMin -ge 0) -and ($curMin -lt 15))
        {
            $startMin = 0
            $endMin = 14
        }
        elseif(($curMin -ge 15) -and ($curMin -lt 30))
        {
            $startMin = 15
            $endMin = 29
        }
        elseif(($curMin -ge 30) -and ($curMin -lt 45))
        {
            $startMin = 30
            $endMin = 44
        }
        else
        {
            $startMin = 45
            $endMin = 59
        }

        $year = Get-Date -Format yyyy
        $month = Get-Date -Format MM
        $day = Get-Date -Format dd
        $hour = Get-Date -Format HH

        # Création des 2 timestamp unix (en millisecondes en plus!) pour faire la requête. 
        $rangeStart = ([double]::Parse((Get-Date -Year $year -Month $month -Day $day -Hour $hour -Minute $startMin -Second 0 -Millisecond 0 -UFormat %s)) *1000)
        $rangeEnd = ([double]::Parse((Get-Date -Year $year -Month $month -Day $day -Hour $hour -Minute $endMin -Second 59 -Millisecond 999 -UFormat %s)) *1000)

        $body = @{
                    buckets = @($bucketName)
                    timeRange = @($rangeStart, $rangeEnd)
                 }

        
        $result = $this.callAPI($uri, "POST", $body)

        $this.handleError($result)

        # Retour du résultat 
        return @{
                    storageUtilized = $result[0].storageUtilized[1]
                    numberOfObjects = $result[0].numberOfObjects[1]
                }
    }
}