<#
   BUT : Contient une classe permetant de faire des requêtes dans LDAP

   AUTEUR : Lucien Chaboudez
   DATE   : Mars 2018

   ----------
   HISTORIQUE DES VERSIONS
   08.03.2018 - 1.0 - Version de base
   09.04.2019 - 1.1 - Modifications pour pouvoir faire les requêtes de récupération de membres d'unités
					  dans scoldap.epfl.ch car bah... dans ldap.epfl.ch ne se trouvent que les personnes 
					  accréditées dans l'unité MAIS dont ce n'est pas l'accréditation primaire.. WTF?
#>
class EPFLLDAP
{
	hidden [string]$LDAP_SERVER_FACULTY_UNIT = 'ldap.epfl.ch'
	hidden [string]$LDAP_SERVER_UNIT_MEMBERS = 'scoldap.epfl.ch'
	hidden [string]$LDAP_ROOT_DN = 'o=epfl,c=ch'
	hidden [System.DirectoryServices.AuthenticationTypes]$auth

	<#
	-------------------------------------------------------------------------------------
		BUT : Créer une instance de l'objet et ouvre une connexion à LDAP
	#>
	EPFLLDAP()
	{
		$this.auth = [System.DirectoryServices.AuthenticationTypes]::FastBind
	}

	<#
	-------------------------------------------------------------------------------------
		BUT : Effectue une recherche dans LDAP avec les paramètres donnés.

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
		# On ne fait pas de LDAPS car seul ldap.epfl.ch le supporte... visiblement, scoldap.epfl.ch pas car ça pète ensuite
		# sur l'appel à $ds.findAll()...
		$dn = New-Object System.DirectoryServices.DirectoryEntry ("LDAP://$($ldapServer):389/$($baseDN)", "", "", $this.auth)
		$ds = new-object System.DirectoryServices.DirectorySearcher($dn)

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
		$dn.Dispose()
		$ds.Dispose()

		return $result
	}

	<#
	-------------------------------------------------------------------------------------
		BUT : Effectue une recherche dans LDAP avec les paramètres donnés.

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

		# Recherche des facultés sur un niveau
		$allFac = $this.LDAPList($this.LDAP_SERVER_FACULTY_UNIT, $this.LDAP_ROOT_DN, "((uniqueidentifier=*))", @("OU", "uniqueidentifier"), 0)

		# Pour mettre le résultat
		$facList = @()

		# Parcours des résultats pour reformater,
		ForEach($curFac in $allFac)
		{
			# Création de l'objet
			$facList += @{name = $curFac.Properties['ou'][0]
							  uniqueidentifier = $curFac.Properties['uniqueidentifier'][0] }

		} # FIN BOUCLE de parcours des résultats

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
	#>
	[Array]getFacultyUnitList([string]$facName, [int]$nbLevels)
	{
		# Création du DN pour la recherche
		$facDN = "OU={0},{1}" -f $facName, $this.LDAP_ROOT_DN

		# Recherche des unités de manière récursive
		$allUnits = $this.LDAPList($this.LDAP_SERVER_FACULTY_UNIT, $facDN, "(&(objectClass=organizationalUnit)(uniqueidentifier=*))", @("OU", "uniqueidentifier"), $nbLevels-1)

		# Pour mettre le résultat
		$unitList = @()

		# Parcours des résultats pour reformater,
		ForEach($curUnit in $allUnits)
		{
			# Création de l'objet
			$unitList += @{name = $curUnit.Properties['ou'][0]
						     uniqueidentifier = $curUnit.Properties['uniqueidentifier'][0] }
		} # FIN BOUCLE de parcours des résultats

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
		# On fait la recherche dans SCOLDAP cette fois-ci... et vous noterez le "U" juste après le "="... ouais parce que dans SCOLDAP, y'a une faille spatio-temporelle
		# ou un truc over bizarre qui fait qu'il faut mettre un U avant le no d'unité... là de nouveau, WTF?
		$allMembers = $this.LDAPSearch($this.LDAP_SERVER_UNIT_MEMBERS, $this.LDAP_ROOT_DN, "subtree", "((uniqueidentifier=U$($unitUniqueIdentifier)))", @("memberuid"))

		# Si rien trouvé, 
		if($allMembers.count -eq 0)
		{
			# on retourne simplement la liste vide
			return $allMembers
		}

		return $allMembers.Properties['memberuid']
	}


}
