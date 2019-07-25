<#
   BUT : Contient les fonctions donnant accès à l'API NetBackup

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2018

    Des exemples d'utilsiation des API via Postman peuvent être trouvés dans le
    keepass Sanas-Backup

	De la documentation sur l'API peut être trouvée ici :
	https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/

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

class NetBackupAPI: RESTAPICurl
{
	hidden [string]$token
	

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion au serveur

		IN  : $server			-> Nom DNS du serveur
		IN  : $user         	-> Nom d'utilisateur 
		IN  : $password			-> Mot de passe

	#>
	NetBackupAPI([string] $server, [string] $user, [string] $password) : base($server) # Ceci appelle le constructeur parent
	{
		$this.server = $server

		<# Le plus souvent, on utilise 'application/json' pour les 'Accept' et 'Content-Type' mais NetBackup semble vouloir faire
			autrement... du coup, obligé de mettre ceci car sinon cela génère des erreurs. Et au final, c'est toujours du JSON... #>
		$this.headers.Add('Accept', 'application/vnd.netbackup+json;version=2.0')
		$this.headers.Add('Content-Type', 'application/vnd.netbackup+json;version=1.0')

		$replace = @{username = $user
						 password = $password}

		$body = $this.loadJSON("xaas-backup-user-credentials.json", $replace)

		$uri = "https://{0}/login" -f $this.server

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.token = ($this.callAPI($uri, "Post", (ConvertTo-Json -InputObject $body -Depth 20))).token

		# Mise à jour des headers
		$this.headers.Add('Authorization', ("{0}" -f $this.token))

    }

	
    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		$uri = "https://{0}/logout" -f $this.server

		$this.callAPI($uri, "Post", "")
    }
    

    <#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des $global:NETBACKUP_API_PAGE_LIMIT_MAX derniers backups pour une VM.
		
		IN  : $vmName		-> le nom de la VM
		IN  : $scheduleType	-> Le type de schedule (peut être une chaîne vide):
								FULL 
								DIFFERENTIAL_INCREMENTAL 
								USER_BACKUP 
								USER_ARCHIVE 
								CUMULATIVE_INCREMENTAL
		IN  : $nbDaysAgo	-> (optionnel) Nombre de jour en arrière dans le temps pour la recherche de backups
							   	Si pas passé, on prend 1 année.

		REMARQUE: Seuls les $global:NETBACKUP_API_PAGE_LIMIT_MAX derniers backups de la VM seront renvoyés.
					Dans le cas où il faudrait plus d'infos, il faudra faire plusieurs appels à l'API en 
					modifiant le paramètre "page[offset]"

		Documentation:
		https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/#_catalog-catalog_images_get	
    #>
    [Array] getVMBackupList([string]$vmName, [string]$scheduleType, [int]$nbDaysAgo)
    {

		if($nbDaysAgo -eq "")
		{
			$nbDaysAgo = 365
		}

		# Calcul de la date dans le passé en soustrayant les jours. Et on met celle-ci au format ISO8601 comme demandé par 
		# NetBackup (et on ajoute un Z à la fin sinon ça ne passe pas...)
		$dateAgo = "{0}Z" -f (get-date -date ((GET-Date).AddDays(-$nbDaysAgo)) -format "s")

		$uri = "https://{0}/catalog/images?page[offset]=0&page[limit]={2}&filter=clientName eq '{1}' and backupTime ge '{3}'" -f `
				$this.server, $vmName, $global:NETBACKUP_API_PAGE_LIMIT_MAX, $dateAgo
		
		if($scheduleType -ne "")
		{
			$uri = "{0} and scheduleType eq '{1}'" -f $uri, $scheduleType
		}

		return ($this.callAPI($uri, "Get", "")).data
	}
	

	<#
		-------------------------------------------------------------------------------------
		BUT : Démarre la restauration d'une VM from scratch

		IN  : $vmName	-> Nom de la VM
		IN  : $backupId	-> ID du backup à restaurer

		Documentation (scroller pour voir les descriptions des différents éléments ):
		https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/#_recovery-recovery_workloads_vmware_scenarios_full-vm_recover_post

		RET : Objet avec les infos du job de backup
    #>
    [PSObject] restoreVM([string]$vmName, [string]$backupId)
    {
        $uri = "https://{0}/recovery/workloads/vmware/scenarios/full-vm/recover" -f $this.server

		$replace = @{vmName = $vmName
					backupId = $backupId}

		$body = $this.loadJSON("xaas-backup-restore-vm.json", $replace)

		# Appel de l'API 
		return ($this.callAPI($uri, "POST", (ConvertTo-Json -InputObject $body -Depth 20))).data

	}



	


}