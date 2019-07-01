<#
   BUT : Contient les fonctions donnant accès à l'API NetBackup

   AUTEUR : Lucien Chaboudez
   DATE   : Juillet 2018

    Des exemples d'utilsiation des API via Postman peuvent être trouvés dans le
    keepass Sanas-Backup

	De la documentation sur l'API peut être trouvée ici :
	https://sort.veritas.com/public/documents/nbu/8.1.2/windowsandunix/productguides/html/index/


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class NetBackupAPI: RESTAPI
{
	hidden [string]$token
	hidden [System.Collections.Hashtable]$headers

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

		$this.headers = @{}
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

		$this.token = (Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers -Body (ConvertTo-Json -InputObject $body -Depth 20)).token

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

		Invoke-RestMethod -Uri $uri -Method Post -Headers $this.headers
    }
    

    <#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

    #>
    [Array] getVMBackupList([string]$vmName)
    {
        $uri = "https://{0}/catalog/images?`$filter=Name eq '{1}'" -f $this.server, $vmName

		return ($this.callAPI($uri, "Get", "")).data
    }


}