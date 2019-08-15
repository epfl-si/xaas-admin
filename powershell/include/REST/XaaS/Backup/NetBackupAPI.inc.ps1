<#
   BUT : Contient les fonctions donnant accès à l'API NetBackup

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2018

    Des exemples d'utilsiation des API via Postman peuvent être trouvés dans le
    keepass Sanas-Backup

	De la documentation sur l'API peut être trouvée ici :
	https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/
	https://sort.veritas.com/documents/doc_details/nbu/8.2/Windows%20and%20UNIX/Documentation/

	Des exemples de code peuvent être trouvés ici :
	https://github.com/VeritasOS/netbackup-api-code-samples


	REMARQUES:
	- Si on utilise les filtres (filter) dans une requête (dans la query string), il ne faut pas mettre 
	de caractère $ avant (ex: $filter) comme pour l'API de vRA
	- On hérite de RESTAPICurl et pas RESTAPI parce que sur les machines de test/prod, il y a des problèmes
	de connexion refermée...

   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>

# Nombre d'éléments max supportés par NetBackup pour la pagination 
$global:NETBACKUP_API_PAGE_LIMIT_MAX = 99
$global:NETBACKUP_BACKUP_SEARCH_DAYS_AGO = 365
$global:NETBACKUP_SCHEDULE_FULL = "FULL"

class NetBackupAPI: RESTAPICurl
{
	hidden [string]$token
	

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $user         	-> Nom d'utilisateur 
		IN  : $password			-> Mot de passe

		Documentation:
		https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/#_gateway-login_post
	#>
	NetBackupAPI([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.server = $server

		<# Le plus souvent, on utilise 'application/json' pour les 'Accept' et 'Content-Type' mais NetBackup semble vouloir faire
			autrement... du coup, obligé de mettre ceci car sinon cela génère des erreurs. Et au final, c'est toujours du JSON... #>
		$this.headers.Add('Accept', 'application/vnd.netbackup+json;version=2.0')
		$this.headers.Add('Content-Type', 'application/vnd.netbackup+json;version=1.0')

		# On n'utilise pas de fichier JSON pour faire cette requête car la structure est relativement simple. De ce fait, on peut
		# se permettre de la "coder" directement.
		$body = @{userName = $user
					password = $password}

		$uri = "https://{0}/login" -f $this.server

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.token = ($this.callAPI($uri, "Post", $body)).token

		if($this.token -eq "")
		{
			Throw "Error recovering NetBackup API Token!"
		}

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("{0}" -f $this.token))

    }


	<#
		-------------------------------------------------------------------------------------
		BUT : Effectue un appel à l'API REST via Curl. La méthode parente a été surchargée afin
				de pouvoir gérer de manière spécifique les messages d'erreur renvoyés par l'API

		IN  : $uri		-> URL à appeler
		IN  : $method	-> Méthode à utiliser (Post, Get, Put, Delete)
		IN  : $body 	-> Objet à passer en Body de la requête. On va ensuite le transformer en JSON
						 	Si $null, on ne passe rien.

		RET : Retour de l'appel
	#>
	hidden [Object] callAPI([string]$uri, [string]$method, [System.Object]$body)
	{
		# Appel de la fonction parente
		$res = ([RESTAPICurl]$this).callAPI($uri, $method, $body)

		# Si on a un messgae d'erreur
		if([bool]($res.PSobject.Properties.name -match "errorMessage") -and ($res.errorMessage -ne ""))
		{
			# Création de l'erreur de base 
			$err = "{0}::{1}(): {2}" -f $this.gettype().Name, (Get-PSCallStack)[0].FunctionName, $res.errorMessage

			# Ajout des détails s'ils existent 
			$res.attributeErrors.PSObject.Properties | ForEach-Object {
			
				$err = "{0}`n{1}: {2}" -f $err, $_.Name, $_.Value
			}
			

			Throw $err
		}

		return $res
	}
	
    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		$uri = "https://{0}/logout" -f $this.server

		$this.callAPI($uri, "Post", $null)
    }
    

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des $global:NETBACKUP_API_PAGE_LIMIT_MAX derniers backups pour une VM.
		
		IN  : $vmName		-> le nom de la VM

		REMARQUE: Seuls les $global:NETBACKUP_API_PAGE_LIMIT_MAX derniers backups de la VM seront renvoyés.
					Dans le cas où il faudrait plus d'infos, il faudra faire plusieurs appels à l'API en 
					modifiant le paramètre "page[offset]"

		Documentation:
		https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/#_catalog-catalog_images_get	
    #>
    [Array] getVMBackupList([string]$vmName)
    {

		# Calcul de la date dans le passé en soustrayant les jours. Et on met celle-ci au format ISO8601 comme demandé par 
		# NetBackup (et on ajoute un Z à la fin sinon ça ne passe pas...)
		$dateAgo = "{0}Z" -f (get-date -date ((GET-Date).AddDays(-$global:NETBACKUP_BACKUP_SEARCH_DAYS_AGO)) -format "s")


		$pagination =  [System.Web.HttpUtility]::UrlEncode("page[offset]=0&page[limit]={0}&" -f $global:NETBACKUP_API_PAGE_LIMIT_MAX)

		$uri = "https://{0}/catalog/images?filter=clientName eq '{1}' and backupTime ge {2}&{3}" -f $this.server, $vmName, $dateAgo, $pagination

		

		return ($this.callAPI($uri, "Get", $null)).data
	}
	

	<#
		-------------------------------------------------------------------------------------
		BUT : Démarre la restauration d'une VM from scratch.
				On peut soit donner l'id du backup, soit le timestamp

		IN  : $vmName			-> Nom de la VM
		IN  : $backupId			-> ID du backup à restaurer
		IN  : $backupTimestamp	-> Timestamp du backup à restaurer

		Documentation (scroller pour voir les descriptions des différents éléments ):
		https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/#_recovery-recovery_workloads_vmware_scenarios_full-vm_recover_post

		RET : Objet avec les infos du job de backup
    #>
    [PSObject] restoreVM([string]$vmName, [string]$backupId, [string]$backupTimestamp)
    {
        $uri = "https://{0}/recovery/workloads/vmware/scenarios/full-vm/recover" -f $this.server

		# Si c'est le timestamp qui a été donné, 
		if($backupId -eq "")
		{
			# Mais si on n'a en fait pas donné de timestamp 
			if($backupTimestamp -eq "")
			{
				Throw "BackupID and Backup Timestamp can not both be empty! This could lead in a break in the time space continuum!"
			}

			# Recherche de l'ID de backup en prenant la totalité des backups et en filtrant sur le timestamp donné.
			$backup = $this.getVMBackupList($vmName) | Where-Object { $_.attributes.backupTime -eq $backupTimestamp}

			# Si pas de backup trouvé
			if($null -eq $backup)
			{
				Throw "No backup found for VM {0} and timestamp {1}" -f $vmName, $backupTimestamp
			}

			$backupId = $backup.id
		}

		$replace = @{vmName = $vmName
					backupId = $backupId}

		$body = $this.createObjectFromJSON("xaas-backup-restore-vm.json", $replace)

		# Appel de l'API 
		return ($this.callAPI($uri, "POST", $body)).data

	}



	


}