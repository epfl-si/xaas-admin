<#
   	BUT : Contient une classe permetant de faire des requêtes dans LDAP

   	AUTEUR : Lucien Chaboudez
   	DATE   : Mars 2018

	Documentation:
		- Fichier JSON de configuration: https://sico.epfl.ch:8443/display/SIAC/Configuration+-+PRJ0011976

   	----------
   	HISTORIQUE DES VERSIONS
   	08.03.2018 - 1.0 - Version de base
   	09.04.2019 - 1.1 - Modifications pour pouvoir faire les requêtes de récupération de membres d'unités
					  dans scoldap.epfl.ch car bah... dans ldap.epfl.ch ne se trouvent que les personnes 
					  accréditées dans l'unité MAIS dont ce n'est pas l'accréditation primaire.. WTF?
   	19.08.2019 - 1.2 - Ajout d'un fichier de configuration JSON pour spécifier où il faut aller chercher les
					  informations dans ldap.epfl.ch. On prenais uniquement dans 'o=epfl,c=ch' mais maintenant
					  il faut aussi aller chercher dans 'o=ehe,c=ch' ...
	31.01.2020 - 1.3 - Correction lors de l'utilisation de la fonction qui interroge scoldap.epfl.ch. Un no 
						d'unité doit obligatoirement être codé sur 5 chiffres, il faut donc ajouter des 0
						avant les nombres plus petits...
	09.11.2020 - 1.4 - Bon ben semblerait, pour une raison inconnue, que maintenant il ne soit plus valable 
						récupérer la liste des personnes d'une unité en allant dans SCOLDAP.epfl.ch... je ne
						sais pas depuis quand mais maintenant on trouve bien toutes les personnes de l'unité
						dans LDAP.epfl.ch...
	15.03.2021 - 1.5 - Ajout de la possibilité de récupérer des informations dans le LDAP de l'ActiveDirectory.
						Généralement, on utilise les CMDLETs "Get-AD*" mais pour une raison inconnue, lorsque
						l'on exécute un script sur le endpoint PowerShell depuis vRO, ces cmdlet ne fonctionnent
						pas renvoie une erreur "Unable to connecto to the server"...
						On fait donc une connexion "spécifique" au LDAP pour récupérer les informations.

#>
class EPFLLDAP
{
	hidden [System.DirectoryServices.AuthenticationTypes]$auth

	# Pour la recherche dans AD
	hidden [System.Management.Automation.PSCredential]$adCredentials

	# Pour stocker la configuration que l'on va aller lire dans le fichier JSON
	hidden [PSObject]$LDAPconfig

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion à LDAP
		
		IN  : $adUsername		-> Nom d'utilisateur (shortname) pour se connecter au LDAP AD
		IN  : $adPassword		-> Mot de passe
	#>
	EPFLLDAP([string]$adUsername, [string]$adPassword)
	{
		# Pour la connexion au LDAP école
		$this.auth = [System.DirectoryServices.AuthenticationTypes]::FastBind

		# Chemin complet jusqu'au fichier à charger
		$filepath = (Join-Path $global:CONFIG_FOLDER "LDAP.json")

		# Si le fichier n'existe pas
		if(-not( Test-Path $filepath))
		{
			Throw ("EPFLLDAP: JSON config file not found ({0})" -f $filepath)
		}

		# Chargement du code JSON
		$this.LDAPconfig = loadFromCommentedJSON -jsonFile $filepath

		# Création des credentials pour la connexion à AD
		$this.adCredentials = New-Object System.Management.Automation.PSCredential -ArgumentList @($adUsername, `
                                                (ConvertTo-SecureString -String $adPassword -AsPlainText -Force))
	}

	<#
	-------------------------------------------------------------------------------------
		BUT : Effectue une recherche dans LDAP avec les paramètres donnés. 
				Cette fonction est utilisée pour faire une recherche à un seul niveau.

		IN  : $ldapServer	-> Nom d'hôte du serveur LDAP à utiliser
		IN  : $baseDN		-> DN pour la recherche
		IN  : $scope		-> Le scope de recherche
									"subtree"
									"onelevel"
		IN  : $filter		-> (optionnel) Le filtre à mettre:
									Ex: ((uniqueidentifier=*))
		IN  : $properties -> Tableau avec les propriétés que l'on veut

	#>
	hidden [Array] LDAPSearch([string]$ldapServer, [string]$baseDN, [string]$scope, [string]$filter, [Array]$properties)
	{
		$searchDN = "LDAP://{0}/{1}" -f $ldapServer, $baseDN

		# On ne fait pas de LDAPS car seul ldap.epfl.ch le supporte... visiblement, scoldap.epfl.ch pas car ça pète ensuite
		# sur l'appel à $ds.findAll()...
		$dn = New-Object System.DirectoryServices.DirectoryEntry ($searchDN, "", "", $this.auth)

		# Si on ne peut pas récupérer le "SchemaEntry", c'est que le DN dans lequel on veut chercher n'existe pas. Donc il n'y a rien dedans.
		if($null -eq $dn.SchemaEntry)
		{
			return @()
		}

		$ds = New-Object System.DirectoryServices.DirectorySearcher($dn)

		if($filter -ne "")
		{
			$ds.filter = $filter
		}

		$ds.SearchScope = $scope

		ForEach($propName in $properties)
		{
			$ds.PropertiesToLoad.Add($propName)
		}

		# Recherche
		$result = $ds.FindAll()	

		# Nettoyage
		$ds.Dispose()
		$dn.Dispose()

		return $result
	}

	<#
	-------------------------------------------------------------------------------------
		BUT : Effectue une recherche dans LDAP avec les paramètres donnés. Cette fonction
				doit être utilisée quand on veut faire une recherche récursive dans une 
				arborescence.

		IN  : $ldapServer	-> Nom d'hôte du serveur LDAP à utiliser
		IN  : $baseDN		-> DN pour la recherche
		IN  : $filter		-> (optionnel) Le filtre à mettre:
									Ex: ((uniqueidentifier=*))
		IN  : $properties -> Tableau avec les propriétés que l'on veut
		IN  : $nbRecurse	-> Le nombre de récursivités à faire
	#>
	hidden [Array] LDAPList([string] $ldapServer, [string]$baseDN, [string]$filter, [Array]$properties, [int]$nbRecurse)
	{
		# Recherche pour le niveau donné
		$list = $this.LDAPSearch($ldapServer, $baseDN, "onelevel", $filter, $properties)

		# Si on doit encore descendre d'un niveau,
		if($nbRecurse -gt 0)
		{
			$nextLevel = @()
			# Parcours des résultats du niveau courant
			ForEach($item in $list)
			{
				# Nouveau DN de recherche pour l'item courant
				$itemDN = "OU={0},{1}" -f $item.Properties['ou'][0], $baseDN
				# Recherche des éléments pour l'item courant
				$nextLevel += $this.LDAPList($ldapServer, $itemDN, $filter, $properties, $nbRecurse-1)

			}
			$list += $nextLevel
		}

		return $list

	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne la liste des facultés

		RET : Tableau de tableaux associatifs avec la liste des facultés. Les tableaux
				associatifs contiennent les informations d'une faculté:
				- name
				- uniqueidentifier
	#>
	[Array]getLDAPFacultyList()
	{

		# Pour mettre le résultat
		$facList = @()

		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{
	
			# Recherche des facultés sur un niveau
			$allFac = $this.LDAPList($this.LDAPconfig.facultyUnits.server, $ldapInfos.rootDN, "((uniqueidentifier=*))", @("OU", "uniqueidentifier"), 0)

			# Parcours des résultats pour reformater,
			ForEach($curFac in $allFac)
			{
				$facName = $curFac.Properties['ou'][0]

				# Si on a une liste avec des filtres,
				if( (($ldapInfos.limitToFaculties.Count -gt 0) -and ($ldapInfos.limitToFaculties -contains $facName)) -or ($ldapInfos.limitToFaculties.Count -eq 0))
				{

					# Création de l'objet
					$facList += @{name = $facName
									uniqueidentifier = $curFac.Properties['uniqueidentifier'][0] }
				}

			} # FIN BOUCLE de parcours des résultats
		}

		return $facList
   }


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne la liste des unités pour une faculté

		IN  : $facName 	-> Nom de la faculté
		IN  : $nbLevels	-> Nombre des niveaux à descendre pour chercher.

		RET : Tableau de tableaux associatifs avec la liste des unités. Les tableaux
				associatifs contiennent les informations d'une unité:
				- name
				- uniqueidentifier
				- accountingnumber
				- level
				- path
	#>
	[Array]getFacultyUnitList([string]$facName, [int]$nbLevels)
	{
		# Pour mettre le résultat
		$unitList = @()

		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{

			# Création du DN pour la recherche
			$facDN = "OU={0},{1}" -f $facName, $ldapInfos.rootDN

			# Recherche des unités de manière récursive
			$allUnits = $this.LDAPList($this.LDAPconfig.facultyUnits.server, $facDN, "(&(objectClass=organizationalUnit)(uniqueidentifier=*))", @("OU", "uniqueidentifier", "accountingnumber"), $nbLevels-1)

			# Parcours des résultats pour reformater,
			ForEach($curUnit in $allUnits)
			{
				# Extraction de la fin du path et compte du nombre de niveau
				# Ex: LDAP://ldap.epfl.ch:636/ou=si-vp,ou=si,o=epfl,c=ch  vers OU=SI-VP,OU=SI,O=EPFL,C=CH
				$path = [Regex]::match($curunit.path, '.*\/(.*)').Groups[1].value.toUpper()
				$level = ($path -Split ",").Count -1
				
				# Création de l'objet
				$unitList += @{name = $curUnit.Properties['ou'][0]
								uniqueidentifier = $curUnit.Properties['uniqueidentifier'][0]
								accountingnumber = $curUnit.Properties['accountingnumber'][0]
								level = $level
								path = $path}
			} # FIN BOUCLE de parcours des résultats
		}
		return $unitList
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne la liste des membres d'une unité

		IN  : $unitUniqueIdentifier	-> Identifiant unique de l'unité (numérique)

		RET : Tableau avec les noms d'utilisateur (uid) des membres de l'unité
	#>
	[Array] getUnitMembers([string]$unitUniqueIdentifier)
	{
		# Pour mettre le résultat
		$memberList = @()

		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{

			# Recherche des members
			$allMembers = $this.LDAPSearch($this.LDAPconfig.facultyUnits.server, $ldapInfos.rootDN, "subtree", "((uniqueidentifier=$($unitUniqueIdentifier)))", @("memberuid"))

			# Si on a un résultat
			if(($allMembers.count -gt 0) -and ($allMembers.properties.keys -contains "memberuid"))
			{
				return $allMembers.properties.memberuid
			}

		}
		return $memberList

	}

	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne les informations d'une unité

		IN  : $unitUniqueIdentifier	-> Identifiant unique de l'unité (numérique)

		RET : Objet avec les informations suivantes
				- description
				- uniqueidentifier
				- memberuid
				- displayname
				- member
				- cn
				- memberuniqueid
				- adspath
				- objectclass
				- gidnumber
	#>
	[PSObject] getUnitInfos([string]$unitUniqueIdentifier)
	{
		# On ajoute des 0 si besoin au début du no de l'unité pour que ça renvoie bien un résultat après
		$unitUniqueIdentifier = $unitUniqueIdentifier.PadLeft(5, '0')

		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{

			# Recherche des unités de manière récursive
			$unit = $this.LDAPSearch($this.LDAPconfig.facultyUnits.server, $ldapInfos.rootDN, "subtree", `
									("(&(objectClass=organizationalUnit)(uniqueidentifier={0}))" -f $unitUniqueIdentifier), @("*"))

			if($unit.count -eq 1)
			{
				return $unit[0].Properties
			}
		}

		return $null

	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne les informations d'un groupe

		IN  : $groupName	-> Nom du groupe

		RET : Objet avec les informations suivantes
				- description
				- uniqueidentifier
				- memberuid
				- displayname
				- member
				- cn
				- memberuniqueid
				- adspath
				- objectclass
				- gidnumber
	#>
	[PSObject] getGroupInfos([string]$groupName)
	{

		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{

			# Recherche des groupes de manière récursive
			$group = $this.LDAPSearch($this.LDAPconfig.facultyUnits.server, $ldapInfos.rootDN, "subtree", `
									("(&(objectClass=EPFLGroupOfPersons)(cn={0}))" -f $groupName), @("*"))

			if($group.count -eq 1)
			{
				return $group[0].Properties
			}
		}

		return $null
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne les informations d'une personne

		IN  : $sciperOrFullName	-> Sciper ou nom complet de la personne

		RET : Objet avec les informations suivantes
				- description
				- uniqueidentifier
				- memberuid
				- displayname
				- member
				- cn
				- memberuniqueid
				- adspath
				- objectclass
				- gidnumber
	#>
	[PSObject] getPersonInfos([string]$sciperOrFullName)
	{
		# Si on nous a donné un numero Sciper
		if($sciperOrFullName -match "^[0-9]+$")
		{
			$field = "uniqueidentifier"
		}
		else # C'est un nom complet
		{
			$field = "cn"
		}


		# Parcours des informations que l'on a
		ForEach($ldapInfos in $this.LDAPconfig.facultyUnits.locations)
		{

			# Recherche des groupes de manière récursive
			$person = $this.LDAPSearch($this.LDAPconfig.facultyUnits.server, $ldapInfos.rootDN, "subtree", `
									("(&(objectClass=organizationalPerson)({0}={1}))" -f $field, $sciperOrFullName), @("*"))

			if($person.count -gt 0)
			{
				return $person[0].Properties
			}
		}

		return $null
	}


	<#
	-------------------------------------------------------------------------------------
		BUT : Retourne les informations d'un groupe qui se trouve dans AD

		IN  : $groupName	-> Nom du groupe 

		RET : Objet avec le groupe
				.path		-> DN jusqu'au groupe
				.properties	-> dictionnaire avec les infos
			  $null si pas trouvé
	#>
	[PSObject] getADGroup([string]$groupName)
	{
		$Searcher = New-Object -TypeName System.DirectoryServices.DirectorySearcher                
		
		# Filtre de recherche
		$Searcher.Filter = "(&(objectClass~=group)(cn={0}))" -f $groupName
		
		$Searcher.SearchRoot = New-Object -TypeName System.DirectoryServices.DirectoryEntry `
					-ArgumentList $(([adsisearcher]"").Searchroot.path), # Domaine actuel
								$($this.adCredentials.UserName),
								$($this.adCredentials.GetNetworkCredential().password)
		
		# Execute the Search
		return $Searcher.FindOne()
	}

}
