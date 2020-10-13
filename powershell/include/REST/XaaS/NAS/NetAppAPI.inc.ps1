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

enum NetAppObjectType 
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
        
        IN  : $serverList           -> Liste avec les noms des serveurs
        IN  : $username             -> Nom d'utilisateur
        IN  : $password             -> Mot de passe
	#>
	NetAppAPI([Array]$serverList, [string]$username, [string]$password): base($server) 
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

        # Ajout des serveurs à la liste
        $serverList | ForEach-Object { $this.addTargetServer($_) }
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
        BUT : Encode un nom d'utilisateur pour qu'il soit utilisable dans du JSON
        
        IN  : $username -> le nom d'utilisateur

        RET : le nom d'utilisateur encodé
	#>
    hidden [string] encodeUsernameForJSON([string]$username)
    {
        # Si on a INTRANET\<user>
        if($username -match 'INTRANET\\[a-z0-9]+')
        {
            # Alors oui, on a l'impression que ceci ne va rien faire du tout niveau remplacement MAIS NON! 
            # Pourquoi? parce que le premier paramètre est interprété (donc transformé en \) et le 2e est pris tel quel
            # C'est vicieux hein ??
            $username = $username -replace "\\", "\\"
        }
        return $username
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
    hidden [string] getServerForObject([NetAppObjectType]$objectType, [string]$objectUUID)
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
		-------------------------------------------------------------------------------------
        BUT : Retourne le nom du serveur qui héberge la SVM donnée
        
        IN  : $svm  -> Objet réprésentant la SVM

        RET : Nom du serveur
	#>
    [string] getSVMClusterHost([PSObject]$svm)
    {
        return $this.getServerForObject([NetAppObjectType]::SVM, $svm.uuid)
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
        BUT : Retourne des informations supplémentaires de taille d'un Volume
        
        IN  : $vol   -> Objet représentant le volume

        NOTE : L'appel à cette fonction ne retourne que les champs spécifiquement passés en paramètre.
                Ce n'est donc pas comme si on pouvait juste "ajouter" des champs à ceux renvoyés par
                défaut par l'appel retournant les détails d'un volume.
	#>
    [PSObject] getVolumeSizeInfos([PSObject]$vol)
    {
        $uri = "/api/storage/volumes/{0}?fields=space.snapshot.used,space.snapshot.reserve_percent,files.maximum,files.used" -f $vol.uuid

        return $this.callAPI($uri, "GET", $null, "", $true)
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
        IN  : $snapSpacePercent -> Pourcentage d'espace à mettre pour les snapshots

        RET : Le volume créé

        https://nas-mcc-t.epfl.ch/docs/api/#/storage/volume_create
	#>
    [PSObject] addVolume([string]$name, [float]$sizeGB, [PSObject]$svm, [PSObject]$aggregate, [string]$securityStyle, [string]$mountPath, [int]$snapSpacePercent)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::SVM, $svm.uuid)

        $uri = "https://{0}/api/storage/volumes" -f $targetServer

        $sizeInBytes = [Math]::Ceiling($sizeGB * 1024 * 1024 * 1024)

        $replace = @{
            aggregateName = $aggregate.name
            aggregateUUID = $aggregate.uuid
            svmName = $svm.name
            svmUUID = $svm.uuid
            volName = $name
            securityStyle = $securityStyle
            mountPath = $mountPath
            # Tableau avec $true en 2e valeur pour faire en sorte de ne pas mettre les " " autour de la valeur dans le JSON
            sizeInBytes = @($sizeInBytes, $true)
            snapSpacePercent = @($snapSpacePercent, $true)
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
    [void] resizeVolume([string]$id, [float]$sizeGB)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $id)

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
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $id)

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
        $targetServer = $this.getServerForObject([NetAppObjectType]::SVM, $svm.uuid)

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
         $targetServer = $this.getServerForObject([NetAppObjectType]::SVM, $share.svm.uuid)

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
		-------------------------------------------------------------------------------------
        BUT : Retourne un share

        IN  : $svm          -> Objet représentant la SVM sur laquelle le share se trouve
        IN  : $shareName    -> Le nom du share

        RET : Objet représentant le share
	#>
    [PSObject] getCIFSShare([PSObject]$svm, [string]$shareName)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::SVM, $svm.uuid)

        $uri = "https://{0}/api/protocols/cifs/shares/{1}/{2}" -f $targetServer, $svm.uuid, [System.Net.WebUtility]::UrlEncode($shareName)

        return $this.callAPI($uri, "GET", $null, "", $true)
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
    [PSObject] getExportPolicyById([string]$id)
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
    [PSObject] getExportPolicyByName([string]$name)
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
    [PSObject] getExportPolicyByName([PSObject]$svm, [string]$name)
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
        $targetServer = $this.getServerForObject([NetAppObjectType]::ExportPolicy, $exportPolicy.id)

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
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $volume.uuid)

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
    [PSObject] getExportPolicyRuleList([PSObject]$exportPolicy)
    {
        $result = @{
            RO = @()
            RW = @()
            Root = @()
        }
        
        # C'te bande de branquigoles chez NetApp... ils fournissent le nécessaire pour retourner les infos sur les export policies MAIS
        # ils ne remplissent pas les champs avec les valeurs dont on a besoin !!! bananes !!
        $this.getExportPolicyRuleListQuery($exportPolicy.id, "fields=clients,protocols,ro_rule,rw_rule,superuser") | ForEach-Object {

            # Si RO
            if($_.ro_rule[0] -eq "any")
            {
                # Si RW aussi 
                if($_.rw_rule[0] -eq "any")
                {
                    # Si Root
                    if($_.superuser[0] -eq "any")
                    {
                        $result.Root += $_.clients[0].match
                    }
                    else # Que RW
                    {
                        $result.RW += $_.clients[0].match
                    }
                }
                else # Que RO
                {
                    $result.RO += $_.clients[0].match
                }
            }
        }

        return $result
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
        $targetServer = $this.getServerForObject([NetAppObjectType]::ExportPolicy, $exportPolicy.id)

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
        IN  : $protocol         -> "cifs"|"nfs3"


        https://nas-mcc-t.epfl.ch/docs/api/#/NAS/export_rule_create
	#>
    [void] updateExportPolicyRules([PSObject]$exportPolicy, [Array]$ROIPList, [Array]$RWIPList, [Array]$RootIPList, [string]$protocol)
    {
        # On commence par supprimer les règles existantes
        $this.deleteExportPolicyRuleList($exportPolicy)

        # Filtrage pour virer les IPs "vides" 
        $ROIPList   = $ROIPList | Where-Object { $_.Trim() -ne "" }
        $RWIPList   = $RWIPList | Where-Object { $_.Trim() -ne "" }
        $RootIPList = $RootIPList | Where-Object { $_.Trim() -ne "" }

        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::ExportPolicy, $exportPolicy.id)

        $doneIPs = @()

        # Parcours des IP ReadOnly
        ForEach($ip in $ROIPList)
        {
            if($doneIPs -contains $ip){ Continue }

            $replace = @{
                clientMatch = $ip.Trim()
                roRule = "any"
                protocol = $protocol.toString()
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
                clientMatch = $ip.Trim()
                rwRule = "any"
                roRule = "any"
                protocol = $protocol.toString()
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
                clientMatch = $ip.Trim()
                superUser = "any"
                rwRule = "any"
                roRule = "any"
                protocol = $protocol.toString()
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
    [PSObject] getSnapshotPolicyById([string]$id)
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
    [PSObject] getSnapshotPolicyByName([string]$name)
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
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $volume.uuid)

        $uri = "https://{0}/api/storage/volumes/{1}" -f $targetServer, $volume.uuid

        $replace = @{
            snapPolicyUuid = $snapPolicy.uuid
            snapPolicyName = $snapPolicy.name
        }

        $body = $this.createObjectFromJSON("xaas-nas-patch-volume-snapshot-policy.json", $replace)

        $this.callAPI($uri, "PATCH", $body)
    }


    <#
        =====================================================================================
                                        QUOTA RULES
        =====================================================================================
    #>

    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des règles de quota avec les paramètres passés.

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/quota_rule_collection_get
	#>
    hidden [Array] getQuotaRuleListQuery([string]$queryParams)
    {
        $uri = "/api/storage/quota/rules/?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des règles de quota pour un volume

        IN  : $volume       -> Objet représentant le volume

        RET : Liste
	#>
    [Array] getVolumeQuotaRuleList([PSObject]$volume)
    {
        # Bizarrement, on doit spécifiquement mettre les champs que l'on veut car ceux-ci ne sont pas retournés par défaut !?!
        return $this.getQuotaRuleListQuery( ("volume.uuid={0}&fields=users,space,files" -f $volume.uuid) )
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations sur la règle de quota pour un utilisateur sur un volume donné.
                Attention, on n'a que la règle, on n'a pas d'informations sur ce qui est réellement
                utilisé. Pour avoir les détails, il faut utiliser la fonction getUserQuotaRule()

        IN  : $volume       -> Objet représentant le volume
        IN  : $username     -> Nom d'utilisateur (format INTRANET\<username>) 

        RET : Objet avec les informations
	#>
    [PSObject] getUserQuotaRule([PSObject]$volume, [string]$username)
    {
        $res = $this.getQuotaRuleListQuery( ("volume.uuid={0}&users.name={1}&fields=users,space,files" -f $volume.uuid, $username) )

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Ajoute une règle de quota pour un utilisateur donné

        IN  : $volume       -> Objet représentant le volume
        IN  : $username     -> Nom d'utilisateur (format INTRANET\username)
        IN  : $quotaMB      -> Quota max autorisé en MB

        https://nas-mcc-t.epfl.ch/docs/api/#/storage/quota_rule_create

        INFO:
        Contraitement à l'utilisation du PowerShell où il fallait spécifiquement faire un "Resize quota"
        du volume après la modification d'un quota (pour que ça soit pris en compte), là, c'est fait 
        automatiquement, ce qui est agréable mais peut être chiant s'il s'avère que l'on créé
        beaucoup de règles à la suite, à espérer que NetApp fasse le job sans se tirer une balle dans le 
        cluster au niveau des performances... C'est pour ça aussi qu'on attend que le job se termine
	#>
    [void] addUserQuotaRule([PSObject]$volume, [string]$username, [int]$quotaMB)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $volume.uuid)

        $uri = "https://{0}/api/storage/quota/rules/" -f $targetServer

        $replace = @{
            limitBytes = @(($quotaMB * 1024 * 1024), $true)
            svmName = $volume.svm.name
            svmUUID = $volume.svm.uuid
            username = $this.encodeUsernameForJSON($username)
            volName = $volume.name
            volUUID = $volume.uuid
        }

        $body = $this.createObjectFromJSON("mynas-new-user-quota-rule.json", $replace)

        $result = $this.callAPI($uri, "POST", $body)

        # L'opération se fait en asynchrone donc on attend qu'elle se termine
        $this.waitForJobToFinish($targetServer, $result.job.uuid)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Met à jour une règle de quota pour un utilisateur donné. Si la règle n'existe
                pas encore, elle est mise à jour

        IN  : $volume       -> Objet représentant le volume
        IN  : $username     -> Nom d'utilisateur (format INTRANET\<username>)
        IN  : $quotaMB      -> Quota max autorisé en MB

        https://nas-mcc-t.epfl.ch/docs/api/#/storage/quota_rule_modify

        NOTE: La documentation sur le BODY à fournir pour cette requête est complètement
                fausse! la majorité des informations sont inutiles et génèrent une 
                erreur
	#>
    [void] updateUserQuotaRule([PSObject]$volume, [string]$username, [int]$quotaMB)
    {
        # Recherche de la règle de quota
        $rule = $this.getUserQuotaRule($volume, $username)

        # Si la règle n'existe pas,
        if($null -eq $rule)
        {
            # On doit donc avoir une règle "héritée", du coup, on ajoute une nouvelle règle
            $this.addUserQuotaRule($volume, $username, $quotaMB)

        }
        else # La règle existe, on peut la mettre à jour
        {
            # Recherche du serveur NetApp cible
            $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $volume.uuid)

            $uri = "https://{0}/api/storage/quota/rules/{1}" -f $targetServer, $rule.uuid

            $replace = @{
                limitBytes = @(($quotaMB * 1024 * 1024), $true)
            }

            $body = $this.createObjectFromJSON("mynas-update-user-quota-rule.json", $replace)

            $result = $this.callAPI($uri, "PATCH", $body)

            # L'opération se fait en asynchrone donc on attend qu'elle se termine
            $this.waitForJobToFinish($targetServer, $result.job.uuid)
        }
        
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime une règle de quota sur un volume

        IN  : $volume       -> Objet représentant le volume
        IN  : $rule         -> Objet représentant la règle à effacer

        https://nas-mcc-t.epfl.ch/docs/api/#/storage/quota_rule_delete
	#>
    [void] deleteUserQuotaRule([PSObject]$volume, [PSObject]$rule)
    {
        # Recherche du serveur NetApp cible
        $targetServer = $this.getServerForObject([NetAppObjectType]::Volume, $volume.uuid)
        
        $uri = "https://{0}/api/storage/quota/rules/{1}" -f $targetServer, $rule.uuid

        $this.callAPI($uri, "DELETE", $null)
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Supprime une règle de quota pour un utilisateur sur un volume

        IN  : $volume       -> Objet représentant le volume
        IN  : $username     -> Nom d'utilisateur pour lequel effacer la règle de quota
	#>
    [void] deleteUserQuotaRule([PSObject]$volume, [string]$username)
    {
        $rule = $this.getUserQuotaRule($volume, $username)

        if($null -ne $rule)
        {
            $this.deleteUserQuotaRule($volume, $rule)
        }
    }
    
    
    <#
        =====================================================================================
                                        QUOTA REPORT
        =====================================================================================
    #>


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des rapports de quota avec les paramètres passés.

        IN  : $queryParams	-> (Optionnel -> "") Chaine de caractères à ajouter à la fin
										de l'URI afin d'effectuer des opérations supplémentaires.
										Pas besoin de mettre le ? au début des $queryParams
        
        https://nas-mcc-t.epfl.ch/docs/api/#/storage/quota_report_collection_get
	#>
    hidden [Array] getQuotaReportListQuery([string]$queryParams)
    {
        $uri = "/api/storage/quota/reports/?max_records=9999"

        # Si un filtre a été passé, on l'ajoute
		if($queryParams -ne "")
		{
			$uri = "{0}&{1}" -f $uri, $queryParams
		}
        
        return $this.callAPI($uri, "GET", $null, "records")
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne la liste des rapports de quota pour un volume

        IN  : $volume       -> Objet représentant le volume

        RET : Liste
	#>
    [Array] getVolumeQuotaReportList([PSObject]$volume)
    {
        # Bizarrement, on doit spécifiquement mettre les champs que l'on veut car ceux-ci ne sont pas retournés par défaut !?!
        return $this.getQuotaReportListQuery( ("volume.uuid={0}&fields=users,space,files" -f $volume.uuid) )
    }


    <#
		-------------------------------------------------------------------------------------
        BUT : Retourne les informations de quota pour un utilisateur sur un volume donné

        IN  : $volume       -> Objet représentant le volume
        IN  : $username     -> Nom d'utilisateur

        RET : Objet avec les informations
	#>
    [PSObject] getUserQuotaReport([PSObject]$volume, [string]$username)
    {
        $res = $this.getQuotaReportListQuery( ("volume.uuid={0}&users.name={1}" -f $volume.uuid, $username) )

        if($res.count -eq 0)
        {
            return $null
        }
        return $res[0]
    }
}
