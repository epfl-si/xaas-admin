<#
   BUT : Contient une classe qui fourni les méthodes nécessaires pour accéder à l'API du NetApp

         La classe parente est APIUtils et celle-ci fourni juste une méthode, celle pour
         charger le nécessaire depuis des fichiers JSON.

    Documentation:
    - Appels synchrones vs asynchrones: https://library.netapp.com/ecmdocs/ECMLP2853739/html/GUID-142FC66E-7C9C-40E9-8F2D-80D7F0E32835.html
    - Check des appels asynchrones: https://library.netapp.com/ecmdocs/ECMLP2853739/html/GUID-E2B341A4-2FAD-44A3-8472-F14A83D6BA6C.html
    - API en elle-même: https://nas-mcc-t.epfl.ch/docs/api/ (nécessite ue authentification user/password)

   AUTEUR : Lucien Chaboudez
   DATE   : Août 2020
#>

class NetAppAPI: RESTAPICurl
{
    hidden [string] $extraArgs
    hidden [string] $password

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server               -> Nom du serveur Scality. Sera utilisé pour créer l'URL du endpoint
        IN  : $username             -> Nom du profile à utiliser pour les credentials
                                        de connexion.
        IN  : $password             -> Nom d'utilisateur pour se connecter à la console Web
	#>
	NetAppAPI([string]$server, [string]$username, [string]$password): base($server) 
	{
        # Pour l'API de NetApp, on ne peut pas s'authentifier en passant les informations dans le header de la requête. Non,
        # on doit utiliser le paramètre "-u" de Curl pour faire le job.
        # Exemple: http://docs.netapp.com/ontap-9/index.jsp?topic=%2Fcom.netapp.doc.dot-rest-api%2Fhome.html
        $this.extraArgs = "-u {0}:{1}" -f $username, $password

        # Mise à jour des headers
		$this.headers.Add('Accept', 'application/hal+json')
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
                d'ajouter le paramètre supplémentaire en l'état des arguments additionnels, le tout
                en n'ayant qu'un point d'entrée

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		# Appel de la fonction parente
        $res = ([RESTAPICurl]$this).callAPI($uri, $method, $body, $this.extraArgs)

        # Si on a un messgae d'erreur
		if([bool]($res.PSobject.Properties.name -match "error") -and ($res.error.messsage -ne ""))
		{
            Throw $res.error.message
        }

        return $res
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Attend qu'un job soit terminé
        
        https://nas-mcc-t.epfl.ch/docs/api/#/cluster/job_get

        RET: Objet représentant le statut du JOB
	#>
    hidden [void] waitForJobToFinish([string]$jobId)
    {
        $uri = "https://{0}/api/cluster/jobs/{1}" -f $this.server, $jobId
        
        # Statuts dans lesquels on admets que le JOB est toujours en train de tourner.
        $jobNotDoneStates = @("queued", "running", "paused")

        $job = $null
        Do
        {
            Start-Sleep -Seconds 10

            $job = $this.callAPI($uri, "GET", $null)

        # On continue tant que le statut n'est pas OK
        } while ($jobNotDoneStates -contains $job.state)

        # Quand on arrive ici, c'est que le job est terminé. On peut donc contrôler qu'ils se soit bien déroulé.
        if($job.state -ne "success")
        {
            Throw $job.message
        }
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Retourne les informations sur la version du NetApp
	#>
    [PSObject] getVersion()
    {
        $uri = "https://{0}/api/cluster?fields=version" -f $this.server

        return $this.callAPI($uri, "GET", $null).version
    }


    <#
        =====================================================================================
                                                SVM
        =====================================================================================
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des SVM disponibles
        
        https://nas-mcc-t.epfl.ch/docs/api/#/svm/svm_collection_get
	#>
    [Array] getSVMList()
    {
        $uri = "https://{0}/api/svm/svms" -f $this.server

        return $this.callAPI($uri, "GET", $null).records
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'une SVM en fonction de son ID
        
        IN  : $id   -> ID de la SVM
	#>
    [PSObject] getSVMById([string]$id)
    {
        $uri = "https://{0}/api/svm/svms/{1}" -f $this.server, $id

        return $this.callAPI($uri, "GET", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'une SVM en fonction de son nom
        
        IN  : $name   -> Nom de la SVM

        RET : Objet avec le résultat
                $null si pas trouvé
	#>
    [PSObject] getSVMByName([string]$name)
    {
        # Recherche de la SVM dans la liste
        $result = $this.getSVMList() | Where-Object { $_.name -eq $name }

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de la SVM
        return $this.getSVMById($result.uuid)
    }


    <#
        =====================================================================================
                                            AGGREGATS
        =====================================================================================
    #>


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des aggrégats
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/aggregate_collection_get
	#>
    [Array] getAggregateList()
    {
        $uri = "https://{0}/api/storage/aggregates" -f $this.server

        return $this.callAPI($uri, "GET", $null).records
    }
    

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un aggrégat en fonction de son ID
        
        IN  : $id   -> ID de l'aggrégat
	#>
    [PSObject] getAggregateById([string]$id)
    {
        $uri = "https://{0}/api/storage/aggregates/{1}" -f $this.server, $id

        return $this.callAPI($uri, "GET", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un aggrégat en fonction de son nom
        
        IN  : $name   -> Nom de l'aggrégat

        RET : Objet avec le résultat
                $null si pas trouvé
	#>
    [PSObject] getAggregateByName([string]$name)
    {
        # Recherche de la SVM dans la liste
        $result = $this.getAggregateList() | Where-Object { $_.name -eq $name }

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de la SVM
        return $this.getAggregateById($result.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les métriques d'un aggrégat en fonction de son ID
        
        IN  : $id   -> ID de l'aggrégat
	#>
    [PSObject] getAggregateMetrics([string]$id)
    {
        $uri = "https://{0}/api/storage/aggregates/{1}/metrics" -f $this.server, $id

        return $this.callAPI($uri, "GET", $null)
    }

    <#
        =====================================================================================
                                            VOLUMES
        =====================================================================================
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des volumes
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_collection_get
	#>
    [Array] getVolumeList()
    {
        $uri = "https://{0}/api/storage/volumes" -f $this.server

        return $this.callAPI($uri, "GET", $null).records
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un Volume en fonction de son ID
        
        IN  : $id   -> ID du volume
	#>
    [PSObject] getVolumeById([string]$id)
    {
        $uri = "https://{0}/api/storage/volumes/{1}" -f $this.server, $id

        return $this.callAPI($uri, "GET", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un Volume en fonction de son nom
        
        IN  : $name   -> Nom du volume

        RET : Objet avec le résultat
                $null si pas trouvé
	#>
    [PSObject] getVolumeByName([string]$name)
    {
        # Recherche de la SVM dans la liste
        $result = $this.getVolumeList() | Where-Object { $_.name -eq $name }

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de la SVM
        return $this.getVolumeById($result.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Créé un volume et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $name         -> Nom du volume
        IN  : $sizeGB       -> Taille du volume en GB
        IN  : $svm          -> Objet représentant la SVM à laquelle attacher le volume
        IN  : $aggregate    -> Objet représentant l'aggrégat où se trouvera le volume

        RET : Le volume créé
	#>
    [PSObject] addVolume([string]$name, [int]$sizeGB, [PSObject]$svm, [PSObject]$aggregate)
    {
        $uri = "https://{0}/api/storage/volumes" -f $this.server

        $sizeInBytes = $sizeGB * 1024 * 1024 * 1024

        $replace = @{
            aggregateName = $aggregate.name
            aggregateUUID = $aggregate.uuid
            svmName = $svm.name
            svmUUID = $svm.uuid
            volName = $name
            sizeInBytes = $sizeInBytes
        }

        $body = $this.createObjectFromJSON("xaas-nas-new-volume.json", $replace)

        $result = $this.callAPI($uri, "POST", $body)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($result.job.uuid)

        # Retour du volume créé
        return $this.getVolumeByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un volume et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $id   -> ID du volume que l'on désire supprimer
	#>
    [void] deleteVolume([PSObject]$id)
    {
        $uri = "https://{0}/api/storage/volumes/{1}" -f $this.server, $id

        $result = $this.callAPI($uri, "DELETE", $null)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($result.job.uuid)
    }
}
