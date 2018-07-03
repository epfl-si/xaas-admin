<#
   BUT : Contient les fonctions donnant accès à l'API vRO. Cette classe ne nécessite pas le nom 
         du tenant en paramètre car elle se connecte toujours sur le tenant par défaut (vsphere.local)

   AUTEUR : Lucien Chaboudez
   DATE   : Juin 2018

	Des exemples d'utilsiation des API via Postman peuvent être trouvés ici :
	https://github.com/vmwaresamples/vra-api-samples-for-postman/tree/master/vRO


   ----------
   HISTORIQUE DES VERSIONS
   0.1 - Version de base

#>
class vROAPI
{
	hidden [string]$token
	hidden [string]$server
	hidden [string]$tenant  = $global:VRA_TENANT_DEFAULT
	hidden [System.Collections.Hashtable]$headers

	<#
	-------------------------------------------------------------------------------------
        BUT : Créer une instance de l'objet et ouvre une connexion au serveur.
              On ne peut employer que l'utilisateur local 'administrator@vsphere.local' car
              les autres utilisateurs n'ont pas accès à ceci. 

        IN  : $server			-> Nom DNS du serveur
        IN  : $cafeClientId     -> Id du client Cafe de vRA. Celui-ci peut être obtenu en passant la commande
                                   suivante sur la console SSH de l'appliance vRA:
                                   grep -i cafe_cli= /etc/vcac/solution-users.properties | sed -e 's/cafe_cli=//'
		IN  : $password			-> Mot de passe

	#>
	vROAPI([string] $server, [string] $cafeClientID, [string] $password)
	{
		$this.server = $server
        
        # Création du header pour la requête de connexion
        $loginHeaders = @{}
		$loginHeaders.Add('Accept', 'application/json')
		$loginHeaders.Add('Content-Type', 'application/x-www-form-urlencoded')

		$body = "username=administrator&password={0}&client_id={1}&domain={2}" -f $password, $cafeClientID, $this.tenant

		$uri = "https://{0}/SAAS/t/{1}/auth/oauthtoken?grant_type=password" -f $this.server, $this.tenant

		# Pour autoriser les certificats self-signed
		[System.Net.ServicePointManager]::ServerCertificateValidationCallback = { $True }

		[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

		$this.token = (Invoke-RestMethod -Uri $uri -Method Post -Headers $loginHeaders -Body $body).access_token

        # Création des headers pour les requêtes futures
        $this.headers = @{}
		$this.headers.Add('Accept', 'application/json')
		$this.headers.Add('Content-Type', 'application/json')
		$this.headers.Add('Authorization', ("Bearer {0}" -f $this.token))

	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Ferme une connexion via l'API REST

	#>
	[Void] disconnect()
	{
		# Aucune implémentation de cette méthode pour le moment car pas trouvé comment faire... 
	}	


	<#
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
											Workflows
		-------------------------------------------------------------------------------------
		-------------------------------------------------------------------------------------
	#>


	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie la liste des Workflows

		RET : Tableau de Workflow
	#>
	[Array] getWorkflowList()
	{
		$uri = "https://{0}/vco/api/workflows" -f $this.server

		return (Invoke-RestMethod -Uri $uri -Method Get -Headers $this.headers).link
	}

	<#
		-------------------------------------------------------------------------------------
		BUT : Renvoie un workflow donné par son nom

		IN  : $name		-> Nom du Workflow

		RET : Objet représentant le Workflow
	#>
	[PSCustomObject] getWorkflow($name)
	{
		# Récupération de tous les Workflows et filtre avec le nom
		$workflow = $this.getWorkflowList() | Where-Object {$_.attributes | Where-Object {$_.value -eq $name}}

		if($workflow -eq $null){ return $null }

		# On transforme la structure en une hashtable afin de pouvoir plus facilement récupérer les informations
		$workflowHashtable = @{}
		$workflow.attributes | ForEach-Object { $workflowHashtable.($_.name) = $_.value }
		return $workflowHashtable
		
	}


}