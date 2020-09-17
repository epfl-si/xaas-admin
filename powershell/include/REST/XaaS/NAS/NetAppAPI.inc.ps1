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

enum netAppObjectType 
{
    SVM
    Aggregate
    Volume
    ExportPolicy
}

class NetAppAPI: RESTAPICurl
{
    hidden [string] $extraArgs
    hidden [string] $password
    hidden [Array] $serverList
    hidden [String] $foundOnServer
    hidden [Hashtable] $objectToServerMapping

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet
        
        IN  : $server               -> Nom du serveur
        IN  : $username             -> Nom d'utilisateur
        IN  : $password             -> Mot de passe
	#>
	NetAppAPI([string]$server, [string]$username, [string]$password): base($server) 
	{
        # Mise à jour des headers
        $this.headers.Add('Accept', 'application/hal+json')
        
        $this.serverList = @()

        # Pour garder la localisation de différents éléments, sur quel serveur
        $this.objectToServerMapping = @{}

        # Pour l'API de NetApp, on ne peut pas s'authentifier en passant les informations dans le header de la requête. Non,
        # on doit utiliser le paramètre "-u" de Curl pour faire le job.
        # Exemple: http://docs.netapp.com/ontap-9/index.jsp?topic=%2Fcom.netapp.doc.dot-rest-api%2Fhome.html
        $this.extraArgs = "-u {0}:{1}" -f $username, $password

        # Ajout du serveur à la liste
        $this.addTargetServer($server)

    }

    <#
	-------------------------------------------------------------------------------------
        BUT : Ajoute un serveur. On peut en effet avoir plusieurs serveurs dans le NetApp donc
                on les met dans une liste et on passera ensuite automatiquement de l'un à 
                l'autre pour les opérations qu'on aura à faire.
        
        IN  : $server               -> Nom du serveur
	#>
    [void] addTargetServer([string]$server)
    {
        # Ajout à la liste
        $this.serverList += $server
    }


    <#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
                d'ajouter le paramètre supplémentaire en l'état des arguments additionnels, le tout
                en n'ayant qu'un point d'entrée

        IN  : $uri		            -> URL à appeler. Si elle ne démarre pas par "https://" c'est qu'on a passé
                                        que le chemin jusqu'à l'API (ex: /api/cluster/jobs/...) et dans ce cas-là,
                                        il faut boucler sur tous les serveurs
		IN  : $method	            -> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	            -> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
                                        Si $null, on ne passe rien.
        IN  : $getPropertyName      -> (optionnel) nom de la propriété dans laquelle regarder pour le résultat lorsque l'on 
                                        fait un GET
        
		RET : Retour de l'appel
    #>
    hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
    {
        return $this.callAPI($uri, $method, $body, "")
    }
    hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$getPropertyName)
    {
        return $this.callAPI($uri, $method, $body, $getPropertyName, $false)
    }
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body, [string]$getPropertyName, [bool]$stopAtFirstGetResult)
	{
        # Si on a l'adresse du serveur dans l'URL
        if($uri -match "^https:")
        {
            $uriList = @($uri)
        }
        else # On n'a pas l'adresse du serveur donc on doit faire en sorte d'interroger tous les serveurs
        {
            $uriList = @()
            $this.serverList | ForEach-Object {
                $uriList += "https://{0}{1}" -f $_, $uri
            }
        }

        $allRes = @()
        # Parcours des URL à interroger
        ForEach($currentUri in $uriList)
        {

            # Appel de la fonction parente
            $res = ([RESTAPICurl]$this).callAPI($currentUri, $method, $body, $this.extraArgs)

            # Si on a un messgae d'erreur
            if([bool]($res.PSobject.Properties.name -match "error") -and ($res.error.messsage -ne ""))
            {
                Throw $res.error.message
            }

            # Si on devait interroger un server donné
            if($uri -match "^https:")
            {
                # On retourne le résultat
                return $res
            }
            else # Il y a plusieurs serveurs à interroger 
            {
                # Si c'était une requête GET et qu'on a un nom pour la propriété où chercher le résultat
                if(($method.ToLower() -eq "get"))
                {
                    # Si la property existe
                    if(($getPropertyName -ne "") -and ([bool]($res.PSobject.Properties.name -eq $getPropertyName)))
                    {
                        $res = $res.$getPropertyName
                    }

                    # Si on a un résultat
                    if(($null -ne $res) -or ($res.count -gt 0))
                    {
                        # Si on doit s'arrêter au premier résultat
                        if($stopAtFirstGetResult)
                        {
                            # Enregistrement du serveur sur lequel on a trouvé l'info
                            $this.foundOnServer = [Regex]::match($currentUri, 'https:\/\/(.*?)\/').Groups[1].Value
                            # Retour du résultat
                            return $res
                        }
                        else # On ne doit pas s'arrêter au premier résultat
                        {
                            $allRes += $res
                        }
                    }# FIN Si on a un résultat
                     
                }
                else # Ce n'est pas une requête GET donc on fait "normal"
                {
                    $allRes += $res
                }

            }# FIN S'il y a plusieurs serveurs à interroger

        }# FIN BOUCLE parcours des URI à interroger

        # Si on devait s'arrêter au premier résultat trouvé et qu'on arrive ici, c'est que rien n'a été trouvé
        if($stopAtFirstGetResult)
        {
            # On retourne donc NULL
            return $null
        }
        else
        {
            if($allRes.Count -eq 0)
            {
                return $null
            }
            return $allRes
        }
        
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Attend qu'un job soit terminé
        
        IN  : $server       -> Le nom du serveur sur lequel tourne le job
        IN  : $jobId        -> ID du job

        https://nas-mcc-t.epfl.ch/docs/api/#/cluster/job_get

        RET: Objet représentant le statut du JOB
	#>
    hidden [void] waitForJobToFinish([string]$server, [string]$jobId)
    {
        $uri = "https://{0}/api/cluster/jobs/{1}" -f $server, $jobId
        
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
            Throw ("JOB {0} finished with state {1}" -f $jobId, $job.message)
        }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations sur la version du NetApp
        
        IN  : $objectType   -> Type de l'objet recherché
        IN  : $objectUUID   -> UUID de l'objet que l'on cherche

        RET : serveur sur lequel se trouve l'élément
	#>
    hidden [string] getServerForObject([netAppObjectType]$objectType, [string]$objectUUID)
    {
        $object = $null
        # Recherche de l'objet en fonction du type
        switch($objectType)
        {
            SVM { $object = $this.getSVMById($objectUUID) }

            Aggregate { $object = $this.getAggregateById($objectUUID) }

            Volume { $object = $this.getVolumeById($objectUUID) }

            ExportPolicy { $object = $this.getExportPolicyById($objectUUID) }

            default { Throw ("Object type {0} not handled" -f $objectType.ToString())}
        }

        if($null -eq $object)
        {
            Throw ("Server not found for {0} with UUID {1}" -f $objectType.toString(), $objectUUID)
        }

        # Si on arrive ici, c'est qu'on a trouvé l'info
        return $this.foundOnServer
    }


    <#
        =====================================================================================
                                                SVM
        =====================================================================================
    #>

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des SVM disponibles sur l'ensemble des serveurs définis

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/svm/svm_collection_get
	#>
    hidden [Array] getSVMListQuery([string]$queryParams)
    {
        $uri = "/api/svm/svms?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

        return $this.callAPI($uri, "GET", $null, "records")
        
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des SVM disponibles sur l'ensemble des serveurs définis
        
        https://nas-mcc-t.epfl.ch/docs/api/#/svm/svm_collection_get
	#>
    [Array] getSVMList()
    {
        return $this.getSVMListQuery($null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'une SVM en fonction de son ID
        
        IN  : $id   -> ID de la SVM
	#>
    [PSObject] getSVMById([string]$id)
    {
        $uri = "/api/svm/svms/{0}" -f $id

        return $this.callAPI($uri, "GET", $null, "", $true)
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
        BUT : Retourne la liste des aggrégats avec des paramètres de filtrage optionnels

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/aggregate_collection_get
	#>
    hidden [Array] getAggregateListQuery([string]$queryParams)
    {
        $uri = "/api/storage/aggregates?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}

        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des aggrégats
	#>
    [Array] getAggregateList()
    {
        return $this.getAggregateListQuery($null)
    }
    

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un aggrégat en fonction de son ID
        
        IN  : $id   -> ID de l'aggrégat
	#>
    [PSObject] getAggregateById([string]$id)
    {
        $uri = "/api/storage/aggregates/{0}" -f $id

        return $this.callAPI($uri, "GET", $null, "", $true)

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
        =====================================================================================
                                            VOLUMES
        =====================================================================================
    #>
    

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des volumes avec des paramètres de filtrage optionnels

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_collection_get
	#>
    hidden [Array] getVolumeListQuery([string]$queryParams)
    {
        $uri = "/api/storage/volumes?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des volumes 
	#>
    [Array] getVolumeList()
    {
        return $this.getVolumeListQuery($null)
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des volumes pour une SVM
	#>
    [Array] getSVMVolumes([PSObject]$svm)
    {
        return $this.getVolumeListQuery("svm.name={0}" -f $svm.name)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations d'un Volume en fonction de son ID
        
        IN  : $id   -> ID du volume
	#>
    [PSObject] getVolumeById([string]$id)
    {
        $uri = "/api/storage/volumes/{0}" -f $id

        return $this.callAPI($uri, "GET", $null, "", $true)

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
        # Recherche du volume dans la liste
        $result = $this.getVolumeListQuery(("name={0}" -f $name))

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails du volume
        return $this.getVolumeById($result.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Créé un volume et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $name             -> Nom du volume
        IN  : $sizeGB           -> Taille du volume en GB
        IN  : $svm              -> Objet représentant la SVM à laquelle attacher le volume
        IN  : $aggregate        -> Objet représentant l'aggrégat où se trouvera le volume
        IN  : $securityStyle    -> le type de sécurité:
                                    "unix", "ntfs", "mixed", "unified"
        IN  : $mountPath        -> Chemin de montage du volume

        RET : Le volume créé

        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_create
	#>
    [PSObject] addVolume([string]$name, [int]$sizeGB, [PSObject]$svm, [PSObject]$aggregate, [string]$securityStyle, [string]$mountPath)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::SVM, $svm.uuid)

        $uri = "https://{0}/api/storage/volumes" -f $targetServer

        $sizeInBytes = $sizeGB * 1024 * 1024 * 1024

        $replace = @{
            aggregateName = $aggregate.name
            aggregateUUID = $aggregate.uuid
            svmName = $svm.name
            svmUUID = $svm.uuid
            volName = $name
            sizeInBytes = @($sizeInBytes, $true)
            securityStyle = $securityStyle
            mountPath = $mountPath
        }

        $body = $this.createObjectFromJSON("xaas-nas-new-volume.json", $replace)

        $result = $this.callAPI($uri, "POST", $body)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($targetServer, $result.job.uuid)

        # Retour du volume créé
        return $this.getVolumeByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Modifie la taille d'un volume et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $id           -> ID du volume
        IN  : $sizeGB       -> Taille du volume en GB
	#>
    [void] resizeVolume([string]$id, [int]$sizeGB)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::Volume, $id)

        $uri = "https://{0}/api/storage/volumes/{1}" -f $targetServer, $id

        $sizeInBytes = $sizeGB * 1024 * 1024 * 1024

        $replace = @{
            sizeInBytes = $sizeInBytes
        }

        $body = $this.createObjectFromJSON("xaas-nas-resize-volume.json", $replace)

        $result = $this.callAPI($uri, "PATCH", $body)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($targetServer, $result.job.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un volume et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $id   -> ID du volume que l'on désire supprimer
	#>
    [void] deleteVolume([string]$id)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::Volume, $id)

        $uri = "https://{0}/api/storage/volumes/{1}" -f $targetServer, $id

        $result = $this.callAPI($uri, "DELETE", $null)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($targetServer, $result.job.uuid)
    }


    <#
        =====================================================================================
                                        SHARES CIFS
        =====================================================================================
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Créé un share CIFS et attend que la tâche qui tourne en fond pour la création se
                termine.
        
        IN  : $name                     -> Nom du share
        IN  : $svm                      -> Objet représentant la SVM sur laquelle il faut créer le share
        IN  : $path                     -> Chemin pour le share
        
        RET : rien

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/cifs_share_create
	#>
    [void] addCIFSShare([string]$name, [PSObject]$svm, [string]$path)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::SVM, $svm.uuid)

        $uri = "https://{0}/api/protocols/cifs/shares" -f $targetServer

        $replace = @{
            svmName = $svm.name
            svmUUID = $svm.uuid
            shareName = $name
            path = $path
        }

        $body = $this.createObjectFromJSON("xaas-nas-new-cifs-share.json", $replace)

        $this.callAPI($uri, "POST", $body)

    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime un share CIFS
        
        IN  : $share    -> Objet représentant le share
        
        RET : rien

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/cifs_share_delete
	#>
    [void] deleteCIFSShare([PSObject]$share)
    {
         # Recherche du serveur NetApp cible
         $targetServer = $this.getServerForObject([netAppObjectType]::SVM, $share.svm.uuid)

         $uri = "https://{0}/api/protocols/cifs/shares/{1}/{2}" -f $targetServer, $share.svm.uuid, [System.Net.WebUtility]::UrlEncode($share.name)

         $this.callAPI($uri, "DELETE", $null)

    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des shares CIFS avec des paramètres de filtrage optionnels

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/cifs_share_collection_get
	#>
    hidden [Array] getCIFSShareListQuery([string]$queryParams)
    {
        $uri = "/api/protocols/cifs/shares?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des shares sur une SVM

        IN  : $svmName  -> Nom de la SVM

        RET : Liste des shares
	#>
    [Array] getSVMCIFSShareList([string]$svmName)
    {
        return $this.getCIFSShareListQuery(("svm.name={0}" -f $svmName))
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des shares pour un volume

        IN  : $volName  -> nom du volume

        RET : Liste des shares
	#>
    [Array] getVolCIFSShareList([string]$volName)
    {
        return $this.getCIFSShareListQuery(("volume.name={0}" -f $volName))
    }


    <#
        =====================================================================================
                                    EXPORT POLICIES (NFS)
        =====================================================================================
    #>


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des export policies avec des paramètres de filtrage optionnels

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_policy_collection_get
	#>
    hidden [Array] getExportPolicyListQuery([string]$queryParams)
    {
        $uri = "/api/protocols/nfs/export-policies?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des export policies

        RET : Liste des export policies
	#>
    [Array] getExportPolicyList()
    {
        return $this.getExportPolicyListQuery("")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne une export policy par son id

        IN  : $id   -> ID de l'export policy

        RET : L'export policy
                $null si pas trouvé

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_policy_get
	#>
    [Array] getExportPolicyById([string]$id)
    {
        $uri = "/api/protocols/nfs/export-policies/{0}" -f $id

        return $this.callAPI($uri, "GET", $null, "", $true)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne une export policy par son nom

        IN  : $name -> Nom de l'export policy

        RET : L'export policy
                $null si pas trouvé
	#>
    [Array] getExportPolicyByName([string]$name)
    {
        $result = $this.getExportPolicyListQuery( ("name={0}" -f $name) )

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de l'export policy
        return $this.getExportPolicyById($result.id)
    }

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne une export policy d'une SVM par son nom

        IN  : $svm  -> Objet représentant la SVM
        IN  : $name -> Nom de l'export policy

        RET : L'export policy
                $null si pas trouvé
	#>
    [Array] getExportPolicyByName([PSObject]$svm, [string]$name)
    {
        $result = $this.getExportPolicyListQuery( ("svm.name={0}&name={1}" -f $svm.name, $name) )

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de l'export policy
        return $this.getExportPolicyById($result.id)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute une export policy

        IN  : $name     -> Nom de l'export policy
        IN  : $svm      -> Objet représentant la SVM à laquelle la policy doit être attachée.
        
        RET : L'export policy créée

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_policy_create
	#>
    [PSObject] addExportPolicy([string]$name, [PSObject]$svm)
    {
        $uri = "/api/protocols/nfs/export-policies"

        $replace = @{
            name = $name
            svmName = $svm.name
            svmUUID = $svm.uuid
        }

        $body = $this.createObjectFromJSON("xaas-nas-new-export-policy.json", $replace)

        $result = $this.callAPI($uri, "POST", $body)

        # Retour de l'élément créé
        return $this.getExportPolicyByName($name)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime une export policy

        IN  : $exportPolicy      -> Objet représentant l'export policy à supprimer
        
        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_policy_delete
	#>
    [void] deleteExportPolicy([PSObject]$exportPolicy)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::ExportPolicy, $exportPolicy.id)

        $uri = "https://{0}/api/protocols/nfs/export-policies/{1}" -f $targetServer, $exportPolicy.id

        $this.callAPI($uri, "DELETE", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Applique une export policy sur un volume

        IN  : $exportPolicy      -> Objet représentant l'export policy à appliquer
        IN  : $volume            -> Objet représentant le volume sur lequel appliquer la policy
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_modify
	#>
    [void] applyExportPolicyOnVolume([PSObject]$exportPolicy, [PSObject]$volume)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::Volume, $volume.uuid)

        $uri = "https://{0}/api/storage/volumes/{1}" -f $targetServer, $volume.uuid

        $replace = @{
            exportPolicyId = @($exportPolicy.id, $true)
            exportPolicyName = $exportPolicy.name
        }

        $body = $this.createObjectFromJSON("xaas-nas-patch-volume-export-policy.json", $replace)

        $this.callAPI($uri, "PATCH", $body)
    }


    <#
        =====================================================================================
                                    EXPORT POLICIES RULES (NFS)
        =====================================================================================
    #>


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des règles d'export policies avec des paramètres de filtrage optionnels

        IN  : $exportPolicyId   -> ID de l'export policy pour laquelle on veut les règles
        IN  : $queryParams	    -> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_rule_collection_get
	#>
    hidden [Array] getExportPolicyRuleListQuery([string]$exportPolicyId, [string]$queryParams)
    {
        $uri = "/api/protocols/nfs/export-policies/{0}/rules?max_records=9999" -f  $exportPolicyId

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des règles d'export policies

        IN  : $exportPolicy     -> Objet représentant l'export policy

        RET : Liste des règles d'export policies
	#>
    [Array] getExportPolicyRuleList([PSObject]$exportPolicy)
    {
        return $this.getExportPolicyRuleListQuery($exportPolicy.id, "")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime la liste des règles d'une export policies

        IN  : $exportPolicy     -> Objet représentant l'export policy
        IN  : $targetServer     -> Serveur cible sur lequel se trouve l'export policy
    #>
    hidden [void] deleteExportPolicyRule([PSObject]$exportPolicy, [string]$targetServer, [int]$index)
    {
        $uri = "https://{0}/api/protocols/nfs/export-policies/{1}/rules/{2}" -f $targetServer, $exportPolicy.id, $index

        $this.callAPI($uri, "DELETE", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime la liste des règles d'une export policies

        IN  : $exportPolicy     -> Objet représentant l'export policy
    #>
    [void] deleteExportPolicyRuleList([PSObject]$exportPolicy)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::ExportPolicy, $exportPolicy.id)

        # Parcours des règles et effacement de celles-ci
        ForEach($rule in $this.getExportPolicyRuleListQuery($exportPolicy.id, ""))
        {
            $this.deleteExportPolicyRule($exportPolicy, $targetServer, $rule.index)
        }
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute une règle d'export policy

        IN  : $exportPolicy     -> Objet représentant l'export policy
        IN  : $targetServer     -> Nom du serveur où exécuter la requête
        IN  : $replaceInBody    -> Hashtable avec les éléments à remplacer dans le body

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_rule_create
	#>
    hidden [void] addExportPolicyRule([PSObject]$exportPolicy, [string]$targetServer, [HashTable]$replaceInBody)
    {
        $uri = "https://{0}/api/protocols/nfs/export-policies/{1}/rules" -f $targetServer, $exportPolicy.id

        $body = $this.createObjectFromJSON("xaas-nas-new-export-policy-rule.json", $replaceInBody)

        $result = $this.callAPI($uri, "POST", $body)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute les règles dans une export policy

        IN  : $exportPolicy     -> Objet représentant l'export policy
        IN  : $ROIPList         -> tableau avec la liste des IP Read-Only
        IN  : $RWIPList         -> Tableau avec la liste des IP Read-Write
        IN  : $RootIPList       -> Tableau avec la liste des IP Root

        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_rule_create
	#>
    [void] updateExportPolicyRules([PSObject]$exportPolicy, [Array]$ROIPList, [Array]$RWIPList, [Array]$RootIPList)
    {
        # On commence par supprimer les règles existantes
        $this.deleteExportPolicyRuleList($exportPolicy)

        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::ExportPolicy, $exportPolicy.id)

        $doneIPs = @()

        # Parcours des IP ReadOnly
        ForEach($ip in $ROIPList)
        {
            if($doneIPs -contains $ip){ Continue }

            $replace = @{
                clientMatch = $ip
                roRule = "any"
            }

            # Si l'IP a ausi les accès Root
            if($RootIPList -contains $ip)
            {
                $replace.rwRule = "any"
                $replace.superUser = "any"
            }
            else # Pas dans le root
            {
                # Si dans les RW
                if($RWIPList -contains $ip)
                {
                    $replace.rwRule = "any"
                }
                else # Pas dans le RW
                {
                    $replace.rwRule = "never"
                }

                $replace.superUser = "none"

            }# FIN SI pas dans le root

            $doneIPs += $ip

            # Ajout de la règle
            $this.addExportPolicyRule($exportPolicy, $targetServer, $replace)

        }# FIN BOUCLE sur les IP ReadOnly


        # Parcours des IP ReadWrite
        ForEach($ip in $RWIPList)
        {
            if($doneIPs -contains $ip){ continue }

            $replace = @{
                clientMatch = $ip
                rwRule = "any"
                roRule = "any"
            }

            if($RootIPList -contains $ip)
            {
                $replace.superUser = "any"
            }
            else
            {
                $replace.superUser = "none"
            }

            $doneIPs += $ip

            # Ajout de la règle
            $this.addExportPolicyRule($exportPolicy, $targetServer, $replace)

        }# FIN BOUCLE sur les IP ReadWrite


        # Parcours des IP Root 
        ForEach($ip in $RootIPList)
        {
            if($doneIPs -contains $ip){ continue }

            $replace = @{
                clientMatch = $ip
                superUser = "any"
                rwRule = "any"
                roRule = "any"
            }

            $doneIPs += $ip

            # Ajout de la règle
            $this.addExportPolicyRule($exportPolicy, $targetServer, $replace)

        }# FIN BOUCLE parcours des IP Root

    }


    <#
        =====================================================================================
                                    SNAPSHOT POLICIES
        =====================================================================================
    #>


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des policies de snapshot avec les paramètres passés.

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/snapshot_policy_collection_get
	#>
    hidden [Array] getSnapshotPolicyListQuery([string]$queryParams)
    {
        $uri = "/api/storage/snapshot-policies?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }

    
    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des policies de snapshot

        RET : Liste des règles des policies de snapshot
	#>
    [Array] getSnapshotPolicyList()
    {
        return $this.getSnapshotPolicyListQuery("")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne une policy de snapshot par son id

        IN  : $id   -> ID de l'export policy

        RET : L'export policy
                $null si pas trouvé
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/snapshot_policy_get
	#>
    [Array] getSnapshotPolicyById([string]$id)
    {
        $uri = "/api/storage/snapshot-policies/{0}" -f $id

        return $this.callAPI($uri, "GET", $null, "", $true)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne une policy de snapshot par son nom

        IN  : $name -> Nom de la policy de snapshot

        RET : La policy de snapshot
                $null si pas trouvé
	#>
    [Array] getSnapshotPolicyByName([string]$name)
    {
        $result = $this.getSnapshotPolicyListQuery( ("name={0}" -f $name) )

        if($null -eq $result)
        {
            return $null
        }

        # Recheche des détails de l'export policy
        return $this.getSnapshotPolicyById($result.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Applique une policy de snapshot sur un volume

        IN  : $exportPolicy      -> Objet représentant la policy de snapshot à appliquer
        IN  : $volume            -> Objet représentant le volume sur lequel appliquer la policy
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_modify
	#>
    [void] applySnapshotPolicyOnVolume([PSObject]$snapPolicy, [PSObject]$volume)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([netAppObjectType]::Volume, $volume.uuid)

        $uri = "https://{0}/api/storage/volumes/{1}" -f $targetServer, $volume.uuid

        $replace = @{
            snapPolicyUuid = $snapPolicy.uuid
            snapPolicyName = $snapPolicy.name
        }

        $body = $this.createObjectFromJSON("xaas-nas-patch-volume-snapshot-policy.json", $replace)

        $this.callAPI($uri, "PATCH", $body)
    }



}
